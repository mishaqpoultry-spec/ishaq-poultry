"""Stock engine. All stock movement goes through `move_stock`."""

from dataclasses import dataclass, field
from datetime import date
from decimal import ROUND_HALF_UP, Decimal

from fastapi import HTTPException, status
from sqlalchemy import case, func, select
from sqlalchemy.orm import Session

from app.models import ChickenType, Purchase, RecordStatus, StockBalance, StockTransaction, StockTxnKind

Q2 = Decimal("0.01")
Q3 = Decimal("0.001")
W0 = Decimal("0.000")


def money(v: Decimal) -> Decimal:
    return Decimal(v).quantize(Q2, rounding=ROUND_HALF_UP)


def kg(v: Decimal) -> Decimal:
    return Decimal(v).quantize(Q3, rounding=ROUND_HALF_UP)


class StockError(HTTPException):
    def __init__(self, msg: str):
        super().__init__(status.HTTP_409_CONFLICT, msg)


def _locked_balance(db: Session, ct: ChickenType) -> StockBalance:
    bal = db.execute(
        select(StockBalance).where(StockBalance.chicken_type == ct).with_for_update()
    ).scalar_one_or_none()
    if bal is None:
        bal = StockBalance(chicken_type=ct, birds=0, weight=W0)
        db.add(bal)
        db.flush()
    return bal


def move_stock(
    db: Session,
    *,
    chicken_type: ChickenType,
    kind: StockTxnKind,
    birds: int,
    weight: Decimal,
    txn_date: date,
    ref_type: str,
    ref_id: int,
    ref_no: str | None,
    user_id: int | None,
    notes: str | None = None,
    allow_negative: bool = False,
) -> StockTransaction:
    """birds/weight are signed: + into stock, - out of stock."""
    weight = kg(weight)
    bal = _locked_balance(db, chicken_type)
    new_birds = bal.birds + birds
    new_weight = kg(bal.weight + weight)
    if not allow_negative and (new_birds < 0 or new_weight < 0):
        short = []
        if new_birds < 0:
            short.append("birds")
        if new_weight < 0:
            short.append("KG")
        raise StockError(
            f"Not enough {chicken_type.value} stock ({' aur '.join(short)} kam hai). "
            f"Bacha hua stock: {bal.birds} birds, {kg(bal.weight)} KG. "
            f"Aap nikal rahe hain: {abs(birds)} birds, {abs(weight)} KG. "
            f"Pehle Stock receiving mein entry karein ya ghalat entry theek karein."
        )
    bal.birds = new_birds
    bal.weight = new_weight
    txn = StockTransaction(
        txn_date=txn_date,
        chicken_type=chicken_type,
        kind=kind,
        birds=birds,
        weight=weight,
        ref_type=ref_type,
        ref_id=ref_id,
        ref_no=ref_no,
        notes=notes,
        created_by_id=user_id,
    )
    db.add(txn)
    return txn


def current_stock(db: Session) -> dict[ChickenType, tuple[int, Decimal]]:
    rows = db.execute(select(StockBalance)).scalars().all()
    out = {ct: (0, W0) for ct in ChickenType}
    for r in rows:
        out[r.chicken_type] = (r.birds, kg(r.weight))
    return out


# --- Summary for a date range (opening / movements / closing) -------------

GROUPS: dict[str, tuple[StockTxnKind, ...]] = {
    "received": (StockTxnKind.purchase, StockTxnKind.purchase_cancel),
    "supplied": (StockTxnKind.delivery, StockTxnKind.delivery_cancel),
    "customer_returns": (StockTxnKind.customer_return,),
    "supplier_returns": (StockTxnKind.supplier_return,),
    "losses": (StockTxnKind.loss, StockTxnKind.loss_cancel),
    "processing_out": (StockTxnKind.processing_out,),
    "processing_in": (StockTxnKind.processing_in,),
}
# processing_cancel reverses either direction; it is folded into the matching group below.


@dataclass
class Qty:
    birds: int = 0
    weight: Decimal = field(default_factory=lambda: W0)

    def add(self, b: int, w: Decimal) -> None:
        self.birds += int(b or 0)
        self.weight = kg(self.weight + Decimal(w or 0))


def stock_summary(db: Session, date_from: date, date_to: date) -> dict:
    """Per chicken type: opening, each movement group (as positive numbers where
    the group is an outflow), and closing. Birds and KG stay separate."""
    result: dict[str, dict] = {}
    opening_rows = db.execute(
        select(
            StockTransaction.chicken_type,
            func.coalesce(func.sum(StockTransaction.birds), 0),
            func.coalesce(func.sum(StockTransaction.weight), 0),
        )
        .where(StockTransaction.txn_date < date_from)
        .group_by(StockTransaction.chicken_type)
    ).all()
    opening = {ct: Qty() for ct in ChickenType}
    for ct, b, w in opening_rows:
        opening[ct].add(b, w)

    # processing_cancel: positive amounts undo processing_out, negative undo processing_in
    group_expr = case(
        *[(StockTransaction.kind.in_(kinds), name) for name, kinds in GROUPS.items()],
        (
            (StockTransaction.kind == StockTxnKind.processing_cancel) & (StockTransaction.weight > 0),
            "processing_out",
        ),
        else_="processing_in",
    )
    rows = db.execute(
        select(
            StockTransaction.chicken_type,
            group_expr.label("grp"),
            func.coalesce(func.sum(StockTransaction.birds), 0),
            func.coalesce(func.sum(StockTransaction.weight), 0),
        )
        .where(StockTransaction.txn_date >= date_from, StockTransaction.txn_date <= date_to)
        .group_by(StockTransaction.chicken_type, "grp")
    ).all()
    moves = {ct: {g: Qty() for g in GROUPS} for ct in ChickenType}
    for ct, grp, b, w in rows:
        moves[ct][grp].add(b, w)

    outflows = {"supplied", "supplier_returns", "losses", "processing_out"}
    for ct in ChickenType:
        o = opening[ct]
        closing = Qty(o.birds, o.weight)
        entry = {"opening": _q(o)}
        for g, q in moves[ct].items():
            closing.add(q.birds, q.weight)
            shown = Qty(-q.birds, -q.weight) if g in outflows else q
            entry[g] = _q(shown)
        entry["closing"] = _q(closing)
        result[ct.value] = entry
    return result


def _q(q: Qty) -> dict:
    return {"birds": q.birds, "weight": str(kg(q.weight))}


def supplier_purchase_totals(db: Session, supplier_ids: list[int] | None = None) -> dict[int, Decimal]:
    stmt = (
        select(Purchase.supplier_id, func.coalesce(func.sum(Purchase.amount), 0))
        .where(Purchase.status == RecordStatus.active)
        .group_by(Purchase.supplier_id)
    )
    if supplier_ids is not None:
        stmt = stmt.where(Purchase.supplier_id.in_(supplier_ids))
    return {sid: money(total) for sid, total in db.execute(stmt).all()}
