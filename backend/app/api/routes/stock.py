from datetime import date
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import any_user, staff
from app.core.database import get_db
from app.models import (
    ChickenType,
    Processing,
    Purchase,
    RecordStatus,
    StockLoss,
    StockTransaction,
    StockTxnKind,
    User,
)
from app.schemas.stock import (
    CancelIn,
    LossCreate,
    LossOut,
    ProcessingCreate,
    ProcessingOut,
    StockTxnOut,
)
from app.services.common import audit, next_number, snapshot
from app.services.stock import current_stock, kg, move_stock, stock_summary

router = APIRouter(prefix="/stock", tags=["stock"])


def _check_admin_negative(body: CancelIn, user: User):
    if body.allow_negative_stock and user.role.value != "admin":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Only admin can allow negative stock")


@router.get("/current")
def get_current(db: Session = Depends(get_db), _: User = Depends(any_user)):
    return {ct.value: {"birds": b, "weight": str(w)} for ct, (b, w) in current_stock(db).items()}


@router.get("/summary")
def get_summary(
    date_from: date,
    date_to: date,
    db: Session = Depends(get_db),
    _: User = Depends(any_user),
):
    if date_to < date_from:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "End date is before start date")
    return {"date_from": date_from, "date_to": date_to, "types": stock_summary(db, date_from, date_to)}


@router.get("/transactions", response_model=list[StockTxnOut])
def list_transactions(
    date_from: date | None = None,
    date_to: date | None = None,
    chicken_type: ChickenType | None = None,
    limit: int = Query(default=300, ge=1, le=5000),
    db: Session = Depends(get_db),
    _: User = Depends(any_user),
):
    stmt = select(StockTransaction)
    if date_from:
        stmt = stmt.where(StockTransaction.txn_date >= date_from)
    if date_to:
        stmt = stmt.where(StockTransaction.txn_date <= date_to)
    if chicken_type:
        stmt = stmt.where(StockTransaction.chicken_type == chicken_type)
    return db.execute(stmt.order_by(StockTransaction.id.desc()).limit(limit)).scalars().all()


# --- Losses: dead / damaged / wastage / shortage ---------------------------


@router.get("/losses", response_model=list[LossOut])
def list_losses(
    date_from: date | None = None,
    date_to: date | None = None,
    db: Session = Depends(get_db),
    _: User = Depends(any_user),
):
    stmt = select(StockLoss)
    if date_from:
        stmt = stmt.where(StockLoss.loss_date >= date_from)
    if date_to:
        stmt = stmt.where(StockLoss.loss_date <= date_to)
    return db.execute(stmt.order_by(StockLoss.loss_date.desc(), StockLoss.id.desc())).scalars().all()


@router.post("/losses", response_model=LossOut, status_code=201)
def create_loss(body: LossCreate, db: Session = Depends(get_db), user: User = Depends(staff)):
    if body.idempotency_key:
        ex = db.execute(select(StockLoss).where(StockLoss.idempotency_key == body.idempotency_key)).scalar_one_or_none()
        if ex:
            return ex
    if body.purchase_id and db.get(Purchase, body.purchase_id) is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Purchase not found")
    loss = StockLoss(**body.model_dump(), ref_no=next_number(db, "loss", "LOS", 6), created_by_id=user.id)
    db.add(loss)
    db.flush()
    move_stock(
        db,
        chicken_type=loss.chicken_type,
        kind=StockTxnKind.loss,
        birds=-loss.birds,
        weight=-loss.weight,
        txn_date=loss.loss_date,
        ref_type="loss",
        ref_id=loss.id,
        ref_no=loss.ref_no,
        user_id=user.id,
        notes=f"{loss.kind.value}: {loss.reason or ''}".strip(": "),
    )
    audit(db, user.id, "create", "stock_loss", loss.id, after=snapshot(loss))
    db.commit()
    return loss


@router.post("/losses/{loss_id}/cancel", response_model=LossOut)
def cancel_loss(loss_id: int, body: CancelIn, db: Session = Depends(get_db), user: User = Depends(staff)):
    loss = db.get(StockLoss, loss_id)
    if loss is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Record not found")
    if loss.status == RecordStatus.cancelled:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Already cancelled")
    before = snapshot(loss)
    move_stock(
        db,
        chicken_type=loss.chicken_type,
        kind=StockTxnKind.loss_cancel,
        birds=loss.birds,
        weight=loss.weight,
        txn_date=loss.loss_date,
        ref_type="loss",
        ref_id=loss.id,
        ref_no=loss.ref_no,
        user_id=user.id,
        notes=body.reason,
    )
    loss.status = RecordStatus.cancelled
    loss.cancel_reason = body.reason
    db.flush()
    audit(db, user.id, "cancel", "stock_loss", loss.id, before=before, after=snapshot(loss))
    db.commit()
    return loss


# --- Processing: live -> dressed / cleaned ---------------------------------


@router.get("/processing", response_model=list[ProcessingOut])
def list_processing(
    date_from: date | None = None,
    date_to: date | None = None,
    db: Session = Depends(get_db),
    _: User = Depends(any_user),
):
    stmt = select(Processing)
    if date_from:
        stmt = stmt.where(Processing.process_date >= date_from)
    if date_to:
        stmt = stmt.where(Processing.process_date <= date_to)
    return db.execute(stmt.order_by(Processing.process_date.desc(), Processing.id.desc())).scalars().all()


def _move_processing(db: Session, p: Processing, user: User, sign: int, kind_out, kind_in, notes=None, allow_negative=False):
    move_stock(
        db,
        chicken_type=p.input_type,
        kind=kind_out,
        birds=-sign * p.input_birds,
        weight=-sign * p.input_weight,
        txn_date=p.process_date,
        ref_type="processing",
        ref_id=p.id,
        ref_no=p.ref_no,
        user_id=user.id,
        notes=notes,
        allow_negative=allow_negative,
    )
    move_stock(
        db,
        chicken_type=p.output_type,
        kind=kind_in,
        birds=sign * p.output_birds,
        weight=sign * p.output_weight,
        txn_date=p.process_date,
        ref_type="processing",
        ref_id=p.id,
        ref_no=p.ref_no,
        user_id=user.id,
        notes=notes,
        allow_negative=allow_negative,
    )


@router.post("/processing", response_model=ProcessingOut, status_code=201)
def create_processing(body: ProcessingCreate, db: Session = Depends(get_db), user: User = Depends(staff)):
    if body.idempotency_key:
        ex = db.execute(select(Processing).where(Processing.idempotency_key == body.idempotency_key)).scalar_one_or_none()
        if ex:
            return ex
    out_birds = body.input_birds if body.output_birds is None else body.output_birds
    wastage = kg(body.input_weight - body.output_weight)
    yield_pct = (body.output_weight * 100 / body.input_weight).quantize(Decimal("0.01"))
    p = Processing(
        **body.model_dump(exclude={"output_birds"}),
        output_birds=out_birds,
        wastage_weight=wastage,
        yield_percent=yield_pct,
        ref_no=next_number(db, "processing", "PRC", 6),
        created_by_id=user.id,
    )
    db.add(p)
    db.flush()
    _move_processing(db, p, user, 1, StockTxnKind.processing_out, StockTxnKind.processing_in)
    audit(db, user.id, "create", "processing", p.id, after=snapshot(p))
    db.commit()
    return p


@router.post("/processing/{processing_id}/cancel", response_model=ProcessingOut)
def cancel_processing(processing_id: int, body: CancelIn, db: Session = Depends(get_db), user: User = Depends(staff)):
    _check_admin_negative(body, user)
    p = db.get(Processing, processing_id)
    if p is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Record not found")
    if p.status == RecordStatus.cancelled:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Already cancelled")
    before = snapshot(p)
    _move_processing(
        db, p, user, -1, StockTxnKind.processing_cancel, StockTxnKind.processing_cancel,
        notes=body.reason, allow_negative=body.allow_negative_stock,
    )
    p.status = RecordStatus.cancelled
    p.cancel_reason = body.reason
    db.flush()
    audit(db, user.id, "cancel", "processing", p.id, before=before, after=snapshot(p))
    db.commit()
    return p
