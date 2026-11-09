from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.api.deps import any_user, staff
from app.core.database import get_db
from app.models import Customer, PartyStatus, User
from app.schemas.common import Page
from app.schemas.party import CustomerCreate, CustomerOut, CustomerUpdate
from app.schemas.sales import LedgerOut
from app.services.common import audit, next_number, snapshot
from app.services.ledger import build_ledger, with_balances

router = APIRouter(prefix="/customers", tags=["customers"])


def _get(db: Session, customer_id: int) -> Customer:
    c = db.get(Customer, customer_id)
    if c is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Customer not found")
    return with_balances(db, [c])[0]


@router.get("", response_model=Page[CustomerOut])
def list_customers(
    q: str | None = Query(default=None, max_length=100),
    status_: PartyStatus | None = Query(default=None, alias="status"),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=50, ge=1, le=500),
    db: Session = Depends(get_db),
    _: User = Depends(any_user),
):
    stmt = select(Customer)
    if q:
        like = f"%{q.strip()}%"
        stmt = stmt.where(
            or_(
                Customer.name.ilike(like),
                Customer.business_name.ilike(like),
                Customer.code.ilike(like),
                Customer.phone.ilike(like),
            )
        )
    if status_:
        stmt = stmt.where(Customer.status == status_)
    total = db.execute(select(func.count()).select_from(stmt.subquery())).scalar_one()
    items = (
        db.execute(stmt.order_by(Customer.name).offset((page - 1) * page_size).limit(page_size))
        .scalars()
        .all()
    )
    return Page(items=with_balances(db, list(items)), total=total, page=page, page_size=page_size)


@router.get("/{customer_id}", response_model=CustomerOut)
def get_customer(customer_id: int, db: Session = Depends(get_db), _: User = Depends(any_user)):
    return _get(db, customer_id)


@router.post("", response_model=CustomerOut, status_code=201)
def create_customer(body: CustomerCreate, db: Session = Depends(get_db), user: User = Depends(staff)):
    dup = db.execute(
        select(Customer).where(
            func.lower(Customer.name) == body.name.lower(),
            Customer.phone.is_not_distinct_from(body.phone),
        )
    ).scalar_one_or_none()
    if dup:
        raise HTTPException(
            status.HTTP_409_CONFLICT, f"Customer '{body.name}' with this phone already exists ({dup.code})"
        )
    c = Customer(**body.model_dump(), code=next_number(db, "customer", "CUS"), created_by_id=user.id)
    db.add(c)
    db.flush()
    audit(db, user.id, "create", "customer", c.id, after=snapshot(c))
    db.commit()
    return with_balances(db, [c])[0]


@router.patch("/{customer_id}", response_model=CustomerOut)
def update_customer(
    customer_id: int, body: CustomerUpdate, db: Session = Depends(get_db), user: User = Depends(staff)
):
    c = _get(db, customer_id)
    before = snapshot(c)
    for k, v in body.model_dump(exclude_unset=True).items():
        if k == "name" and v is None:
            continue
        setattr(c, k, v)
    db.flush()
    audit(db, user.id, "update", "customer", c.id, before=before, after=snapshot(c))
    db.commit()
    return with_balances(db, [c])[0]


@router.get("/{customer_id}/ledger", response_model=LedgerOut)
def customer_ledger(
    customer_id: int,
    date_from: date,
    date_to: date,
    db: Session = Depends(get_db),
    _: User = Depends(any_user),
):
    """Opening balance at date_from, every delivery/payment in the period with a
    running balance, and the closing balance."""
    if date_to < date_from:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "End date is before start date")
    lg = build_ledger(db, _get(db, customer_id), date_from, date_to)
    return LedgerOut(
        customer_id=customer_id,
        date_from=lg.date_from,
        date_to=lg.date_to,
        opening_balance=lg.opening_balance,
        entries=[e.__dict__ for e in lg.entries],
        total_debit=lg.total_debit,
        total_credit=lg.total_credit,
        total_birds=lg.total_birds,
        total_weight=lg.total_weight,
        closing_balance=lg.closing_balance,
    )
