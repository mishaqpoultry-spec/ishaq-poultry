"""Customers (shops, hotels, restaurants) and Suppliers (farms)."""

import enum
from decimal import Decimal

from sqlalchemy import Enum, ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import ZERO, Base, Money, TimestampMixin


class PartyStatus(str, enum.Enum):
    active = "active"
    inactive = "inactive"


class CustomerType(str, enum.Enum):
    shop = "shop"
    hotel = "hotel"
    restaurant = "restaurant"
    other = "other"


class Customer(TimestampMixin, Base):
    __tablename__ = "customers"

    id: Mapped[int] = mapped_column(primary_key=True)
    code: Mapped[str] = mapped_column(String(20), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(120), index=True)
    business_name: Mapped[str | None] = mapped_column(String(160))
    customer_type: Mapped[CustomerType] = mapped_column(
        Enum(CustomerType, name="customer_type", native_enum=False, length=20),
        default=CustomerType.shop,
    )
    phone: Mapped[str | None] = mapped_column(String(30), index=True)
    whatsapp: Mapped[str | None] = mapped_column(String(30))
    address: Mapped[str | None] = mapped_column(Text)
    # Positive = customer owes us at the start of using the system.
    opening_balance: Mapped[Decimal] = mapped_column(Money, default=ZERO)
    status: Mapped[PartyStatus] = mapped_column(
        Enum(PartyStatus, name="party_status", native_enum=False, length=20),
        default=PartyStatus.active,
    )
    notes: Mapped[str | None] = mapped_column(Text)
    created_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"))


class Supplier(TimestampMixin, Base):
    __tablename__ = "suppliers"

    id: Mapped[int] = mapped_column(primary_key=True)
    code: Mapped[str] = mapped_column(String(20), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(120), index=True)
    farm_name: Mapped[str | None] = mapped_column(String(160))
    phone: Mapped[str | None] = mapped_column(String(30), index=True)
    address: Mapped[str | None] = mapped_column(Text)
    # Positive = we owe the supplier at the start of using the system.
    opening_balance: Mapped[Decimal] = mapped_column(Money, default=ZERO)
    status: Mapped[PartyStatus] = mapped_column(
        Enum(PartyStatus, name="party_status", native_enum=False, length=20),
        default=PartyStatus.active,
    )
    notes: Mapped[str | None] = mapped_column(Text)
    created_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
