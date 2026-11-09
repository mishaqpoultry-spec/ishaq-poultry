from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.api.deps import any_user, staff
from app.core.database import get_db
from app.models import PartyStatus, Supplier, User
from app.schemas.common import Page
from app.schemas.party import SupplierCreate, SupplierOut, SupplierUpdate
from app.services.common import audit, next_number, snapshot
from app.services.stock import money, supplier_purchase_totals

router = APIRouter(prefix="/suppliers", tags=["suppliers"])


def _get(db: Session, supplier_id: int) -> Supplier:
    s = db.get(Supplier, supplier_id)
    if s is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Supplier not found")
    return _with_balance(db, [s])[0]


def _with_balance(db: Session, suppliers: list[Supplier]) -> list[Supplier]:
    """Payable = opening balance + active purchases (payments subtract in Phase 4)."""
    totals = supplier_purchase_totals(db, [s.id for s in suppliers])
    for s in suppliers:
        s.current_balance = money(s.opening_balance + totals.get(s.id, 0))
    return suppliers


@router.get("", response_model=Page[SupplierOut])
def list_suppliers(
    q: str | None = Query(default=None, max_length=100),
    status_: PartyStatus | None = Query(default=None, alias="status"),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=50, ge=1, le=500),
    db: Session = Depends(get_db),
    _: User = Depends(any_user),
):
    stmt = select(Supplier)
    if q:
        like = f"%{q.strip()}%"
        stmt = stmt.where(
            or_(
                Supplier.name.ilike(like),
                Supplier.farm_name.ilike(like),
                Supplier.code.ilike(like),
                Supplier.phone.ilike(like),
            )
        )
    if status_:
        stmt = stmt.where(Supplier.status == status_)
    total = db.execute(select(func.count()).select_from(stmt.subquery())).scalar_one()
    items = (
        db.execute(stmt.order_by(Supplier.name).offset((page - 1) * page_size).limit(page_size))
        .scalars()
        .all()
    )
    return Page(items=_with_balance(db, list(items)), total=total, page=page, page_size=page_size)


@router.get("/{supplier_id}", response_model=SupplierOut)
def get_supplier(supplier_id: int, db: Session = Depends(get_db), _: User = Depends(any_user)):
    return _get(db, supplier_id)


@router.post("", response_model=SupplierOut, status_code=201)
def create_supplier(body: SupplierCreate, db: Session = Depends(get_db), user: User = Depends(staff)):
    dup = db.execute(
        select(Supplier).where(
            func.lower(Supplier.name) == body.name.lower(),
            Supplier.phone.is_not_distinct_from(body.phone),
        )
    ).scalar_one_or_none()
    if dup:
        raise HTTPException(
            status.HTTP_409_CONFLICT, f"Supplier '{body.name}' with this phone already exists ({dup.code})"
        )
    s = Supplier(**body.model_dump(), code=next_number(db, "supplier", "SUP"), created_by_id=user.id)
    db.add(s)
    db.flush()
    audit(db, user.id, "create", "supplier", s.id, after=snapshot(s))
    db.commit()
    return _with_balance(db, [s])[0]


@router.patch("/{supplier_id}", response_model=SupplierOut)
def update_supplier(
    supplier_id: int, body: SupplierUpdate, db: Session = Depends(get_db), user: User = Depends(staff)
):
    s = _get(db, supplier_id)
    before = snapshot(s)
    for k, v in body.model_dump(exclude_unset=True).items():
        if k == "name" and v is None:
            continue
        setattr(s, k, v)
    db.flush()
    audit(db, user.id, "update", "supplier", s.id, before=before, after=snapshot(s))
    db.commit()
    return _with_balance(db, [s])[0]
