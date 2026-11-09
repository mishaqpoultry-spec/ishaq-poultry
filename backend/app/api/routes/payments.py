from datetime import date

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import any_user, staff
from app.core.database import get_db
from app.models import Customer, Payment, RecordStatus, User
from app.schemas.sales import PaymentCreate, PaymentOut
from app.schemas.stock import CancelIn
from app.services.common import audit, next_number, snapshot

router = APIRouter(prefix="/payments", tags=["payments"])


@router.get("", response_model=list[PaymentOut])
def list_payments(
    customer_id: int | None = None,
    date_from: date | None = None,
    date_to: date | None = None,
    include_cancelled: bool = False,
    db: Session = Depends(get_db),
    _: User = Depends(any_user),
):
    stmt = select(Payment)
    if customer_id:
        stmt = stmt.where(Payment.customer_id == customer_id)
    if date_from:
        stmt = stmt.where(Payment.payment_date >= date_from)
    if date_to:
        stmt = stmt.where(Payment.payment_date <= date_to)
    if not include_cancelled:
        stmt = stmt.where(Payment.status == RecordStatus.active)
    return db.execute(stmt.order_by(Payment.payment_date.desc(), Payment.id.desc())).scalars().all()


@router.post("", response_model=PaymentOut, status_code=201)
def create_payment(body: PaymentCreate, db: Session = Depends(get_db), user: User = Depends(staff)):
    """Standalone payment (e.g. customer pays old balance without a new supply)."""
    if body.idempotency_key:
        ex = db.execute(select(Payment).where(Payment.idempotency_key == body.idempotency_key)).scalar_one_or_none()
        if ex:
            return ex
    cust = db.execute(select(Customer).where(Customer.id == body.customer_id).with_for_update()).scalar_one_or_none()
    if cust is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Customer not found")
    p = Payment(**body.model_dump(), receipt_no=next_number(db, "receipt", "RCP", 6), created_by_id=user.id)
    db.add(p)
    db.flush()
    audit(db, user.id, "create", "payment", p.id, after=snapshot(p))
    db.commit()
    return p


@router.post("/{payment_id}/cancel", response_model=PaymentOut)
def cancel_payment(payment_id: int, body: CancelIn, db: Session = Depends(get_db), user: User = Depends(staff)):
    p = db.get(Payment, payment_id)
    if p is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Payment not found")
    if p.status == RecordStatus.cancelled:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Payment is already cancelled")
    before = snapshot(p)
    p.status = RecordStatus.cancelled
    p.cancel_reason = body.reason
    db.flush()
    audit(db, user.id, "cancel", "payment", p.id, before=before, after=snapshot(p))
    db.commit()
    return p
