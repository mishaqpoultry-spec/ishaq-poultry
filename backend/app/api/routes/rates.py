from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import any_user, staff
from app.core.database import get_db
from app.models import ChickenType, Customer, CustomerRate, User
from app.schemas.sales import RateCreate, RateOut
from app.services.common import audit, snapshot
from app.services.ledger import applicable_rate

router = APIRouter(prefix="/rates", tags=["rates"])


@router.get("", response_model=list[RateOut])
def list_rates(
    customer_id: int | None = None,
    defaults_only: bool = False,
    limit: int = Query(default=200, ge=1, le=2000),
    db: Session = Depends(get_db),
    _: User = Depends(any_user),
):
    """Rate history, newest first. Rows are never edited — a new rate is a new row."""
    stmt = select(CustomerRate)
    if defaults_only:
        stmt = stmt.where(CustomerRate.customer_id.is_(None))
    elif customer_id is not None:
        stmt = stmt.where(CustomerRate.customer_id == customer_id)
    return (
        db.execute(stmt.order_by(CustomerRate.effective_from.desc(), CustomerRate.id.desc()).limit(limit))
        .scalars()
        .all()
    )


@router.get("/applicable", response_model=RateOut | None)
def get_applicable(
    customer_id: int,
    chicken_type: ChickenType = ChickenType.live,
    on: date | None = None,
    db: Session = Depends(get_db),
    _: User = Depends(any_user),
):
    return applicable_rate(db, customer_id, chicken_type, on or date.today())


@router.post("", response_model=RateOut, status_code=201)
def create_rate(body: RateCreate, db: Session = Depends(get_db), user: User = Depends(staff)):
    if body.customer_id is not None and db.get(Customer, body.customer_id) is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Customer not found")
    r = CustomerRate(**body.model_dump(), created_by_id=user.id)
    db.add(r)
    db.flush()
    audit(db, user.id, "create", "rate", r.id, after=snapshot(r))
    db.commit()
    return r
