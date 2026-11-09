"""Customer rates, deliveries (each delivery = one invoice) and payments."""

import enum
from datetime import date, datetime, time
from decimal import Decimal

from sqlalchemy import CheckConstraint, Date, DateTime, Enum, ForeignKey, Integer, String, Text, Time, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import ZERO, Base, Money, TimestampMixin, Weight
from app.models.party import Customer
from app.models.stock import ChickenType, RateUnit, RecordStatus


def _enum(cls, name):
    return Enum(cls, name=name, native_enum=False, length=20)


class PaymentMethod(str, enum.Enum):
    cash = "cash"
    bank = "bank"
    online = "online"
    other = "other"


class CustomerRate(Base):
    """Append-only rate history. customer_id NULL = default rate for everyone.
    The applicable rate is the latest row with effective_from <= delivery date;
    a customer-specific rate wins over the default."""

    __tablename__ = "customer_rates"
    __table_args__ = (CheckConstraint("rate >= 0", name="rate_nonneg"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    customer_id: Mapped[int | None] = mapped_column(ForeignKey("customers.id"), index=True)
    chicken_type: Mapped[ChickenType] = mapped_column(_enum(ChickenType, "chicken_type"))
    rate_unit: Mapped[RateUnit] = mapped_column(_enum(RateUnit, "rate_unit"))
    rate: Mapped[Decimal] = mapped_column(Money)
    effective_from: Mapped[date] = mapped_column(Date, index=True)
    notes: Mapped[str | None] = mapped_column(Text)
    created_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Delivery(TimestampMixin, Base):
    """One supply to a customer. It IS the invoice: rate and totals are frozen
    here and never recalculated, so later rate changes cannot alter it."""

    __tablename__ = "deliveries"
    __table_args__ = (
        CheckConstraint("birds >= 0", name="birds_nonneg"),
        CheckConstraint("net_weight > 0", name="net_pos"),
        CheckConstraint("gross_weight >= net_weight", name="gross_ge_net"),
        CheckConstraint("discount >= 0", name="discount_nonneg"),
        CheckConstraint("discount_per_kg >= 0", name="discount_per_kg_nonneg"),
        CheckConstraint("additional_charges >= 0", name="charges_nonneg"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    invoice_no: Mapped[str] = mapped_column(String(20), unique=True, index=True)  # INV-000001
    idempotency_key: Mapped[str | None] = mapped_column(String(64), unique=True)
    customer_id: Mapped[int] = mapped_column(ForeignKey("customers.id"), index=True)
    delivery_date: Mapped[date] = mapped_column(Date, index=True)
    delivery_time: Mapped[time | None] = mapped_column(Time)
    chicken_type: Mapped[ChickenType] = mapped_column(_enum(ChickenType, "chicken_type"))
    birds: Mapped[int] = mapped_column(Integer, default=0)
    pieces: Mapped[int | None] = mapped_column(Integer)
    gross_weight: Mapped[Decimal] = mapped_column(Weight)
    net_weight: Mapped[Decimal] = mapped_column(Weight)
    rate: Mapped[Decimal] = mapped_column(Money)
    rate_unit: Mapped[RateUnit] = mapped_column(_enum(RateUnit, "rate_unit"))
    amount: Mapped[Decimal] = mapped_column(Money)  # qty x rate
    discount_per_kg: Mapped[Decimal] = mapped_column(Money, default=ZERO, server_default="0")
    discount: Mapped[Decimal] = mapped_column(Money, default=ZERO)  # = discount_per_kg x net_weight
    additional_charges: Mapped[Decimal] = mapped_column(Money, default=ZERO)
    total_amount: Mapped[Decimal] = mapped_column(Money)  # amount - discount (+ charges); after-discount bill
    # Snapshots taken when the invoice was generated (printed on the invoice).
    previous_balance: Mapped[Decimal] = mapped_column(Money)
    payment_received: Mapped[Decimal] = mapped_column(Money, default=ZERO)
    balance_after: Mapped[Decimal] = mapped_column(Money)
    driver: Mapped[str | None] = mapped_column(String(80))
    vehicle: Mapped[str | None] = mapped_column(String(40))
    notes: Mapped[str | None] = mapped_column(Text)
    status: Mapped[RecordStatus] = mapped_column(_enum(RecordStatus, "record_status"), default=RecordStatus.active)
    cancel_reason: Mapped[str | None] = mapped_column(Text)
    cancelled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    cancelled_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    created_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"))

    customer: Mapped[Customer] = relationship(lazy="joined")


class Payment(TimestampMixin, Base):
    """Money received from a customer. May be linked to the delivery it was
    collected with, or stand alone (e.g. weekly settlement)."""

    __tablename__ = "payments"
    __table_args__ = (CheckConstraint("amount > 0", name="amount_pos"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    receipt_no: Mapped[str] = mapped_column(String(20), unique=True, index=True)  # RCP-000001
    idempotency_key: Mapped[str | None] = mapped_column(String(64), unique=True)
    customer_id: Mapped[int] = mapped_column(ForeignKey("customers.id"), index=True)
    delivery_id: Mapped[int | None] = mapped_column(ForeignKey("deliveries.id"), index=True)
    payment_date: Mapped[date] = mapped_column(Date, index=True)
    amount: Mapped[Decimal] = mapped_column(Money)
    method: Mapped[PaymentMethod] = mapped_column(_enum(PaymentMethod, "payment_method"), default=PaymentMethod.cash)
    reference: Mapped[str | None] = mapped_column(String(80))
    notes: Mapped[str | None] = mapped_column(Text)
    status: Mapped[RecordStatus] = mapped_column(_enum(RecordStatus, "record_status"), default=RecordStatus.active)
    cancel_reason: Mapped[str | None] = mapped_column(Text)
    created_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
