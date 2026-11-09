from datetime import date, datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.api.deps import any_user, staff
from app.core.database import get_db
from app.models import PartyStatus, Purchase, RateUnit, RecordStatus, StockTxnKind, Supplier, User, UserRole
from app.schemas.stock import CancelIn, PurchaseCreate, PurchaseList, PurchaseOut, PurchaseTotals
from app.services.common import audit, next_number, snapshot
from app.services.stock import kg, money, move_stock

router = APIRouter(prefix="/purchases", tags=["purchases"])


def _get(db: Session, pid: int) -> Purchase:
    p = db.get(Purchase, pid)
    if p is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Purchase not found")
    return p


@router.get("", response_model=PurchaseList)
def list_purchases(
    date_from: date | None = None,
    date_to: date | None = None,
    supplier_id: int | None = None,
    q: str | None = Query(default=None, max_length=100),
    include_cancelled: bool = False,
    limit: int = Query(default=500, ge=1, le=5000),
    db: Session = Depends(get_db),
    _: User = Depends(any_user),
):
    stmt = select(Purchase).join(Purchase.supplier)
    if date_from:
        stmt = stmt.where(Purchase.purchase_date >= date_from)
    if date_to:
        stmt = stmt.where(Purchase.purchase_date <= date_to)
    if supplier_id:
        stmt = stmt.where(Purchase.supplier_id == supplier_id)
    if q:
        like = f"%{q.strip()}%"
        stmt = stmt.where(or_(Purchase.ref_no.ilike(like), Supplier.name.ilike(like), Purchase.supplier_ref.ilike(like)))
    if not include_cancelled:
        stmt = stmt.where(Purchase.status == RecordStatus.active)

    active = stmt.where(Purchase.status == RecordStatus.active).subquery()
    t = db.execute(
        select(
            func.count(),
            func.coalesce(func.sum(active.c.birds), 0),
            func.coalesce(func.sum(active.c.net_weight), 0),
            func.coalesce(func.sum(active.c.amount), 0),
            func.coalesce(func.sum(active.c.total_cost), 0),
        )
    ).one()
    items = (
        db.execute(stmt.order_by(Purchase.purchase_date.desc(), Purchase.id.desc()).limit(limit))
        .unique()
        .scalars()
        .all()
    )
    return PurchaseList(
        items=items,
        totals=PurchaseTotals(count=t[0], birds=t[1], net_weight=kg(t[2]), amount=money(t[3]), total_cost=money(t[4])),
    )


@router.get("/{purchase_id}", response_model=PurchaseOut)
def get_purchase(purchase_id: int, db: Session = Depends(get_db), _: User = Depends(any_user)):
    return _get(db, purchase_id)


@router.post("", response_model=PurchaseOut, status_code=201)
def create_purchase(body: PurchaseCreate, db: Session = Depends(get_db), user: User = Depends(staff)):
    # Duplicate-submit protection: same key returns the already-saved record.
    if body.idempotency_key:
        existing = db.execute(
            select(Purchase).where(Purchase.idempotency_key == body.idempotency_key)
        ).scalar_one_or_none()
        if existing:
            return existing

    supplier = db.get(Supplier, body.supplier_id)
    if supplier is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Supplier not found")
    if supplier.status != PartyStatus.active:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Supplier is inactive")

    qty = body.net_weight if body.rate_unit == RateUnit.per_kg else body.birds
    amount = money(body.rate * qty)
    p = Purchase(
        **body.model_dump(exclude={"idempotency_key"}),
        idempotency_key=body.idempotency_key,
        ref_no=next_number(db, "purchase", "PUR", 6),
        amount=amount,
        total_cost=money(amount + body.transport_charges + body.other_expenses),
        created_by_id=user.id,
    )
    db.add(p)
    db.flush()
    move_stock(
        db,
        chicken_type=p.chicken_type,
        kind=StockTxnKind.purchase,
        birds=p.birds,
        weight=p.net_weight,
        txn_date=p.purchase_date,
        ref_type="purchase",
        ref_id=p.id,
        ref_no=p.ref_no,
        user_id=user.id,
    )
    audit(db, user.id, "create", "purchase", p.id, after=snapshot(p))
    db.commit()
    return p


@router.post("/{purchase_id}/cancel", response_model=PurchaseOut)
def cancel_purchase(purchase_id: int, body: CancelIn, db: Session = Depends(get_db), user: User = Depends(staff)):
    """Records are never deleted: cancelling reverses the stock and keeps history."""
    p = _get(db, purchase_id)
    if p.status == RecordStatus.cancelled:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Purchase is already cancelled")
    if body.allow_negative_stock and user.role != UserRole.admin:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Only admin can allow negative stock")
    before = snapshot(p)
    move_stock(
        db,
        chicken_type=p.chicken_type,
        kind=StockTxnKind.purchase_cancel,
        birds=-p.birds,
        weight=-p.net_weight,
        txn_date=p.purchase_date,
        ref_type="purchase",
        ref_id=p.id,
        ref_no=p.ref_no,
        user_id=user.id,
        notes=body.reason,
        allow_negative=body.allow_negative_stock,
    )
    p.status = RecordStatus.cancelled
    p.cancel_reason = body.reason
    p.cancelled_at = datetime.now(timezone.utc)
    p.cancelled_by_id = user.id
    db.flush()
    audit(db, user.id, "cancel", "purchase", p.id, before=before, after=snapshot(p))
    db.commit()
    return p
