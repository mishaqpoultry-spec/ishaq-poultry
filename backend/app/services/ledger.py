"""Customer balances and ledger.

Balance = Opening + Deliveries(total) - Payments   (returns/adjustments: Phase 4)
Only active (non-cancelled) records count. Everything is Decimal.
"""

from dataclasses import dataclass, field
from datetime import date, time
from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import ChickenType, Customer, CustomerRate, Delivery, Payment, RecordStatus
from app.services.stock import W0, kg, money

ZERO = Decimal("0.00")


def _sum_deliveries(db: Session, customer_ids: list[int] | None, before: date | None = None):
    stmt = select(Delivery.customer_id, func.coalesce(func.sum(Delivery.total_amount), 0)).where(
        Delivery.status == RecordStatus.active
    )
    if customer_ids is not None:
        stmt = stmt.where(Delivery.customer_id.in_(customer_ids))
    if before is not None:
        stmt = stmt.where(Delivery.delivery_date < before)
    return {cid: Decimal(v) for cid, v in db.execute(stmt.group_by(Delivery.customer_id)).all()}


def _sum_payments(db: Session, customer_ids: list[int] | None, before: date | None = None):
    stmt = select(Payment.customer_id, func.coalesce(func.sum(Payment.amount), 0)).where(
        Payment.status == RecordStatus.active
    )
    if customer_ids is not None:
        stmt = stmt.where(Payment.customer_id.in_(customer_ids))
    if before is not None:
        stmt = stmt.where(Payment.payment_date < before)
    return {cid: Decimal(v) for cid, v in db.execute(stmt.group_by(Payment.customer_id)).all()}


def customer_balances(db: Session, customers: list[Customer], before: date | None = None) -> dict[int, Decimal]:
    ids = [c.id for c in customers]
    d = _sum_deliveries(db, ids, before)
    p = _sum_payments(db, ids, before)
    return {c.id: money(c.opening_balance + d.get(c.id, ZERO) - p.get(c.id, ZERO)) for c in customers}


def customer_balance(db: Session, customer: Customer, before: date | None = None) -> Decimal:
    return customer_balances(db, [customer], before)[customer.id]


def with_balances(db: Session, customers: list[Customer]) -> list[Customer]:
    bal = customer_balances(db, customers)
    for c in customers:
        c.current_balance = bal[c.id]
    return customers


# --- Ledger --------------------------------------------------------------


@dataclass
class LedgerEntry:
    date: date
    time: time | None
    kind: str  # delivery / payment
    ref_no: str
    ref_id: int
    description: str
    chicken_type: str | None = None
    birds: int = 0
    weight: Decimal = W0
    rate: Decimal | None = None
    rate_unit: str | None = None
    debit: Decimal = ZERO  # bill (increases balance)
    credit: Decimal = ZERO  # payment / return (decreases balance)
    balance: Decimal = ZERO
    _order: tuple = field(default=(), repr=False)


@dataclass
class Ledger:
    customer: Customer
    date_from: date
    date_to: date
    opening_balance: Decimal
    entries: list[LedgerEntry]
    total_debit: Decimal
    total_credit: Decimal
    total_birds: int
    total_weight: Decimal
    closing_balance: Decimal


def build_ledger(db: Session, customer: Customer, date_from: date, date_to: date) -> Ledger:
    opening = customer_balance(db, customer, before=date_from)
    deliveries = db.execute(
        select(Delivery).where(
            Delivery.customer_id == customer.id,
            Delivery.status == RecordStatus.active,
            Delivery.delivery_date >= date_from,
            Delivery.delivery_date <= date_to,
        )
    ).unique().scalars().all()
    payments = db.execute(
        select(Payment).where(
            Payment.customer_id == customer.id,
            Payment.status == RecordStatus.active,
            Payment.payment_date >= date_from,
            Payment.payment_date <= date_to,
        )
    ).scalars().all()

    entries: list[LedgerEntry] = []
    for d in deliveries:
        qty = f"{d.birds} birds, {kg(d.net_weight)} KG" if d.birds else f"{kg(d.net_weight)} KG"
        entries.append(
            LedgerEntry(
                date=d.delivery_date,
                time=d.delivery_time,
                kind="delivery",
                ref_no=d.invoice_no,
                ref_id=d.id,
                description=f"{d.chicken_type.value.title()} chicken supply ({qty})",
                chicken_type=d.chicken_type.value,
                birds=d.birds,
                weight=kg(d.net_weight),
                rate=d.rate,
                rate_unit=d.rate_unit.value,
                debit=money(d.total_amount),
                _order=(d.delivery_date, 0, d.delivery_time or time(0), d.id, 0),
            )
        )
    for p in payments:
        # A payment taken with a delivery is listed right after that delivery.
        linked = next((e for e in entries if e.kind == "delivery" and e.ref_id == p.delivery_id), None)
        order = (linked._order[:4] + (1,)) if linked else (p.payment_date, 1, time(23, 59), p.id, 0)
        entries.append(
            LedgerEntry(
                date=p.payment_date,
                time=None,
                kind="payment",
                ref_no=p.receipt_no,
                ref_id=p.id,
                description=f"Payment received ({p.method.value})" + (f" — {p.reference}" if p.reference else ""),
                credit=money(p.amount),
                _order=order,
            )
        )
    entries.sort(key=lambda e: e._order)
    running = opening
    for e in entries:
        running = money(running + e.debit - e.credit)
        e.balance = running
    return Ledger(
        customer=customer,
        date_from=date_from,
        date_to=date_to,
        opening_balance=opening,
        entries=entries,
        total_debit=money(sum((e.debit for e in entries), ZERO)),
        total_credit=money(sum((e.credit for e in entries), ZERO)),
        total_birds=sum(e.birds for e in entries),
        total_weight=kg(sum((e.weight for e in entries), W0)),
        closing_balance=running,
    )


# --- Rates ---------------------------------------------------------------


def applicable_rate(db: Session, customer_id: int, chicken_type: ChickenType, on: date) -> CustomerRate | None:
    """Customer-specific rate if one exists, else the default rate."""
    for cid_filter in (CustomerRate.customer_id == customer_id, CustomerRate.customer_id.is_(None)):
        r = db.execute(
            select(CustomerRate)
            .where(cid_filter, CustomerRate.chicken_type == chicken_type, CustomerRate.effective_from <= on)
            .order_by(CustomerRate.effective_from.desc(), CustomerRate.id.desc())
            .limit(1)
        ).scalar_one_or_none()
        if r:
            return r
    return None
