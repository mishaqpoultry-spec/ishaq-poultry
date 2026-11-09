"""Purchases (stock receiving), stock ledger, losses and live->dressed processing.

Birds and weight are ALWAYS stored in separate columns and never combined.
Every stock change writes one StockTransaction row and updates StockBalance
(row-locked) in the same DB transaction, so balance == sum(transactions).
"""

import enum
from datetime import date, datetime, time
from decimal import Decimal

from sqlalchemy import (
    CheckConstraint,
    Date,
    DateTime,
    Enum,
    ForeignKey,
    Integer,
    String,
    Text,
    Time,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import ZERO, Base, Money, TimestampMixin, Weight
from app.models.party import Supplier


def _enum(cls, name):
    return Enum(cls, name=name, native_enum=False, length=20)


class ChickenType(str, enum.Enum):
    live = "live"
    dressed = "dressed"
    cleaned = "cleaned"


class RateUnit(str, enum.Enum):
    per_kg = "per_kg"
    per_bird = "per_bird"


class RecordStatus(str, enum.Enum):
    active = "active"
    cancelled = "cancelled"


class StockTxnKind(str, enum.Enum):
    purchase = "purchase"
    purchase_cancel = "purchase_cancel"
    delivery = "delivery"
    delivery_cancel = "delivery_cancel"
    customer_return = "customer_return"
    supplier_return = "supplier_return"
    loss = "loss"  # dead / damaged / wastage / shortage
    loss_cancel = "loss_cancel"
    processing_out = "processing_out"  # live leaving for processing
    processing_in = "processing_in"  # dressed/cleaned produced
    processing_cancel = "processing_cancel"


class LossKind(str, enum.Enum):
    dead = "dead"
    damaged = "damaged"
    wastage = "wastage"
    shortage = "shortage"


class Purchase(TimestampMixin, Base):
    """One receiving entry = one batch with its own rate and costs."""

    __tablename__ = "purchases"
    __table_args__ = (
        CheckConstraint("birds >= 0", name="birds_nonneg"),
        CheckConstraint("net_weight > 0", name="net_weight_pos"),
        CheckConstraint("gross_weight >= net_weight", name="gross_ge_net"),
        CheckConstraint("rate >= 0", name="rate_nonneg"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    ref_no: Mapped[str] = mapped_column(String(20), unique=True, index=True)  # PUR-000001
    idempotency_key: Mapped[str | None] = mapped_column(String(64), unique=True)
    supplier_id: Mapped[int] = mapped_column(ForeignKey("suppliers.id"), index=True)
    purchase_date: Mapped[date] = mapped_column(Date, index=True)
    receiving_time: Mapped[time | None] = mapped_column(Time)
    chicken_type: Mapped[ChickenType] = mapped_column(_enum(ChickenType, "chicken_type"))
    birds: Mapped[int] = mapped_column(Integer, default=0)
    gross_weight: Mapped[Decimal] = mapped_column(Weight)
    net_weight: Mapped[Decimal] = mapped_column(Weight)
    rate: Mapped[Decimal] = mapped_column(Money)
    rate_unit: Mapped[RateUnit] = mapped_column(_enum(RateUnit, "rate_unit"))
    amount: Mapped[Decimal] = mapped_column(Money)  # payable to supplier
    transport_charges: Mapped[Decimal] = mapped_column(Money, default=ZERO)
    other_expenses: Mapped[Decimal] = mapped_column(Money, default=ZERO)
    total_cost: Mapped[Decimal] = mapped_column(Money)  # amount + transport + other (for profit)
    supplier_ref: Mapped[str | None] = mapped_column(String(60))
    notes: Mapped[str | None] = mapped_column(Text)
    status: Mapped[RecordStatus] = mapped_column(_enum(RecordStatus, "record_status"), default=RecordStatus.active)
    cancel_reason: Mapped[str | None] = mapped_column(Text)
    cancelled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    cancelled_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    created_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"))

    supplier: Mapped[Supplier] = relationship(lazy="joined")


class StockBalance(Base):
    """Current stock per chicken type. Locked FOR UPDATE on every change."""

    __tablename__ = "stock_balances"

    chicken_type: Mapped[ChickenType] = mapped_column(_enum(ChickenType, "chicken_type"), primary_key=True)
    birds: Mapped[int] = mapped_column(Integer, default=0)
    weight: Mapped[Decimal] = mapped_column(Weight, default=Decimal("0.000"))


class StockTransaction(Base):
    """Append-only stock ledger. Positive = stock in, negative = stock out."""

    __tablename__ = "stock_transactions"

    id: Mapped[int] = mapped_column(primary_key=True)
    txn_date: Mapped[date] = mapped_column(Date, index=True)
    chicken_type: Mapped[ChickenType] = mapped_column(_enum(ChickenType, "chicken_type"), index=True)
    kind: Mapped[StockTxnKind] = mapped_column(_enum(StockTxnKind, "stock_txn_kind"), index=True)
    birds: Mapped[int] = mapped_column(Integer, default=0)
    weight: Mapped[Decimal] = mapped_column(Weight, default=Decimal("0.000"))
    ref_type: Mapped[str] = mapped_column(String(30))
    ref_id: Mapped[int] = mapped_column(Integer)
    ref_no: Mapped[str | None] = mapped_column(String(30))
    notes: Mapped[str | None] = mapped_column(Text)
    created_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class StockLoss(TimestampMixin, Base):
    __tablename__ = "stock_losses"
    __table_args__ = (
        CheckConstraint("birds >= 0", name="birds_nonneg"),
        CheckConstraint("weight >= 0", name="weight_nonneg"),
        CheckConstraint("birds > 0 OR weight > 0", name="something"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    ref_no: Mapped[str] = mapped_column(String(20), unique=True, index=True)  # LOS-000001
    idempotency_key: Mapped[str | None] = mapped_column(String(64), unique=True)
    loss_date: Mapped[date] = mapped_column(Date, index=True)
    chicken_type: Mapped[ChickenType] = mapped_column(_enum(ChickenType, "chicken_type"))
    kind: Mapped[LossKind] = mapped_column(_enum(LossKind, "loss_kind"))
    birds: Mapped[int] = mapped_column(Integer, default=0)
    weight: Mapped[Decimal] = mapped_column(Weight, default=Decimal("0.000"))
    purchase_id: Mapped[int | None] = mapped_column(ForeignKey("purchases.id"))
    reason: Mapped[str | None] = mapped_column(Text)
    status: Mapped[RecordStatus] = mapped_column(_enum(RecordStatus, "record_status"), default=RecordStatus.active)
    cancel_reason: Mapped[str | None] = mapped_column(Text)
    created_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"))


class Processing(TimestampMixin, Base):
    """Live chicken converted to dressed/cleaned. Output weight < input weight."""

    __tablename__ = "processings"
    __table_args__ = (
        CheckConstraint("input_weight > 0", name="input_pos"),
        CheckConstraint("output_weight > 0", name="output_pos"),
        CheckConstraint("output_weight <= input_weight", name="output_le_input"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    ref_no: Mapped[str] = mapped_column(String(20), unique=True, index=True)  # PRC-000001
    idempotency_key: Mapped[str | None] = mapped_column(String(64), unique=True)
    process_date: Mapped[date] = mapped_column(Date, index=True)
    input_type: Mapped[ChickenType] = mapped_column(_enum(ChickenType, "chicken_type"))
    output_type: Mapped[ChickenType] = mapped_column(_enum(ChickenType, "chicken_type"))
    input_birds: Mapped[int] = mapped_column(Integer)
    input_weight: Mapped[Decimal] = mapped_column(Weight)
    output_birds: Mapped[int] = mapped_column(Integer)
    output_weight: Mapped[Decimal] = mapped_column(Weight)
    wastage_weight: Mapped[Decimal] = mapped_column(Weight)
    yield_percent: Mapped[Decimal] = mapped_column(Money)
    notes: Mapped[str | None] = mapped_column(Text)
    status: Mapped[RecordStatus] = mapped_column(_enum(RecordStatus, "record_status"), default=RecordStatus.active)
    cancel_reason: Mapped[str | None] = mapped_column(Text)
    created_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
