from datetime import date, datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.api.deps import any_user, require_roles
from app.core.config import get_settings
from app.core.database import get_db
from app.models import (
    Customer,
    Delivery,
    PartyStatus,
    Payment,
    RateUnit,
    RecordStatus,
    StockTxnKind,
    User,
    UserRole,
)
from app.schemas.sales import DeliveryCreate, DeliveryList, DeliveryOut, DeliveryTotals
from app.schemas.stock import CancelIn
from app.services.common import audit, next_number, snapshot
from app.services.ledger import customer_balance
from app.services.pdf import invoice_message, invoice_pdf
from app.services.stock import kg, money, move_stock

router = APIRouter(prefix="/deliveries", tags=["deliveries"])

# Operators (drivers / munshi) may record supplies; cancelling needs manager+.
can_record = require_roles(UserRole.admin, UserRole.manager, UserRole.operator)
can_cancel = require_roles(UserRole.admin, UserRole.manager)


def _get(db: Session, did: int) -> Delivery:
    d = db.get(Delivery, did)
    if d is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Invoice not found")
    return d


@router.get("", response_model=DeliveryList)
def list_deliveries(
    date_from: date | None = None,
    date_to: date | None = None,
    customer_id: int | None = None,
    q: str | None = Query(default=None, max_length=100),
    include_cancelled: bool = False,
    limit: int = Query(default=500, ge=1, le=5000),
    db: Session = Depends(get_db),
    _: User = Depends(any_user),
):
    stmt = select(Delivery).join(Delivery.customer)
    if date_from:
        stmt = stmt.where(Delivery.delivery_date >= date_from)
    if date_to:
        stmt = stmt.where(Delivery.delivery_date <= date_to)
    if customer_id:
        stmt = stmt.where(Delivery.customer_id == customer_id)
    if q:
        like = f"%{q.strip()}%"
        stmt = stmt.where(or_(Delivery.invoice_no.ilike(like), Customer.name.ilike(like), Customer.business_name.ilike(like)))
    if not include_cancelled:
        stmt = stmt.where(Delivery.status == RecordStatus.active)
    active = stmt.where(Delivery.status == RecordStatus.active).subquery()
    t = db.execute(
        select(
            func.count(),
            func.coalesce(func.sum(active.c.birds), 0),
            func.coalesce(func.sum(active.c.net_weight), 0),
            func.coalesce(func.sum(active.c.total_amount), 0),
            func.coalesce(func.sum(active.c.payment_received), 0),
        )
    ).one()
    items = (
        db.execute(stmt.order_by(Delivery.delivery_date.desc(), Delivery.id.desc()).limit(limit)).unique().scalars().all()
    )
    return DeliveryList(
        items=items,
        totals=DeliveryTotals(
            count=t[0], birds=t[1], net_weight=kg(t[2]), total_amount=money(t[3]), payment_received=money(t[4])
        ),
    )


@router.get("/{delivery_id}", response_model=DeliveryOut)
def get_delivery(delivery_id: int, db: Session = Depends(get_db), _: User = Depends(any_user)):
    return _get(db, delivery_id)


@router.post("", response_model=DeliveryOut, status_code=201)
def create_delivery(body: DeliveryCreate, db: Session = Depends(get_db), user: User = Depends(can_record)):
    """Record one supply and generate its invoice in a single DB transaction:
    stock out + invoice + (optional) payment received on the spot."""
    if body.idempotency_key:
        ex = db.execute(select(Delivery).where(Delivery.idempotency_key == body.idempotency_key)).unique().scalar_one_or_none()
        if ex:
            return ex
    if body.allow_negative_stock and user.role != UserRole.admin:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Only admin can allow negative stock")

    # Lock the customer row so two invoices for the same customer can't read the same previous balance.
    cust = db.execute(select(Customer).where(Customer.id == body.customer_id).with_for_update()).scalar_one_or_none()
    if cust is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Customer not found")
    if cust.status != PartyStatus.active:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Customer account is inactive")

    qty = body.net_weight if body.rate_unit == RateUnit.per_kg else body.birds
    amount = money(body.rate * qty)
    discount = money(body.discount_per_kg * body.net_weight)
    total = money(amount - discount + body.additional_charges)
    if total < 0:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Discount cannot be more than the bill")
    previous = customer_balance(db, cust)
    paid = money(body.payment_received)

    d = Delivery(
        **body.model_dump(
            exclude={"idempotency_key", "payment_received", "payment_method", "payment_reference", "allow_negative_stock"}
        ),
        idempotency_key=body.idempotency_key,
        invoice_no=next_number(db, "invoice", "INV", 6),
        amount=amount,
        discount=discount,
        total_amount=total,
        previous_balance=previous,
        payment_received=paid,
        balance_after=money(previous + total - paid),
        created_by_id=user.id,
    )
    db.add(d)
    db.flush()
    move_stock(
        db,
        chicken_type=d.chicken_type,
        kind=StockTxnKind.delivery,
        birds=-d.birds,
        weight=-d.net_weight,
        txn_date=d.delivery_date,
        ref_type="delivery",
        ref_id=d.id,
        ref_no=d.invoice_no,
        user_id=user.id,
        notes=cust.name,
        # Supply is unlimited unless stock enforcement is switched on in settings.
        allow_negative=body.allow_negative_stock or not get_settings().enforce_stock,
    )
    if paid > 0:
        db.add(
            Payment(
                receipt_no=next_number(db, "receipt", "RCP", 6),
                customer_id=cust.id,
                delivery_id=d.id,
                payment_date=d.delivery_date,
                amount=paid,
                method=body.payment_method,
                reference=body.payment_reference,
                notes=f"Received with {d.invoice_no}",
                created_by_id=user.id,
            )
        )
    db.flush()
    audit(db, user.id, "create", "delivery", d.id, after=snapshot(d))
    db.commit()
    db.refresh(d)
    return d


@router.post("/{delivery_id}/cancel", response_model=DeliveryOut)
def cancel_delivery(delivery_id: int, body: CancelIn, db: Session = Depends(get_db), user: User = Depends(can_cancel)):
    """Never deletes: returns the stock, cancels the payment taken with it, keeps history."""
    d = _get(db, delivery_id)
    if d.status == RecordStatus.cancelled:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invoice is already cancelled")
    before = snapshot(d)
    move_stock(
        db,
        chicken_type=d.chicken_type,
        kind=StockTxnKind.delivery_cancel,
        birds=d.birds,
        weight=d.net_weight,
        txn_date=d.delivery_date,
        ref_type="delivery",
        ref_id=d.id,
        ref_no=d.invoice_no,
        user_id=user.id,
        notes=body.reason,
    )
    for p in db.execute(
        select(Payment).where(Payment.delivery_id == d.id, Payment.status == RecordStatus.active)
    ).scalars():
        p.status = RecordStatus.cancelled
        p.cancel_reason = f"Invoice {d.invoice_no} cancelled: {body.reason}"
        audit(db, user.id, "cancel", "payment", p.id)
    d.status = RecordStatus.cancelled
    d.cancel_reason = body.reason
    d.cancelled_at = datetime.now(timezone.utc)
    d.cancelled_by_id = user.id
    db.flush()
    audit(db, user.id, "cancel", "delivery", d.id, before=before, after=snapshot(d))
    db.commit()
    return d


@router.get("/{delivery_id}/message")
def get_message(delivery_id: int, db: Session = Depends(get_db), _: User = Depends(any_user)):
    """Invoice summary text for WhatsApp / SMS plus the numbers to open."""
    d = _get(db, delivery_id)
    return {
        "text": invoice_message(d),  # WhatsApp: emoji + bold
        "sms_text": invoice_message(d, emoji=False),
        "whatsapp": d.customer.whatsapp or d.customer.phone,
        "phone": d.customer.phone,
    }


@router.get("/{delivery_id}/pdf")
def get_pdf(delivery_id: int, db: Session = Depends(get_db), _: User = Depends(any_user)):
    d = _get(db, delivery_id)
    return Response(
        content=invoice_pdf(d),
        media_type="application/pdf",
        headers={"Content-Disposition": f'inline; filename="{d.invoice_no}.pdf"'},
    )
