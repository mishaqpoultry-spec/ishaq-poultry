from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, Field, field_validator

from app.models import CustomerType, PartyStatus
from app.schemas.common import ORMModel

PHONE_PATTERN = r"^[0-9+\-\s]{7,20}$"


def _strip(v):
    if isinstance(v, str):
        v = v.strip()
        return v or None
    return v


class _PartyBase(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    phone: str | None = Field(default=None, pattern=PHONE_PATTERN)
    address: str | None = Field(default=None, max_length=500)
    notes: str | None = Field(default=None, max_length=2000)

    @field_validator("*", mode="before")
    @classmethod
    def strip_strings(cls, v):
        return _strip(v)


class CustomerCreate(_PartyBase):
    business_name: str | None = Field(default=None, max_length=160)
    customer_type: CustomerType = CustomerType.shop
    whatsapp: str | None = Field(default=None, pattern=PHONE_PATTERN)
    opening_balance: Decimal = Field(default=Decimal("0"), max_digits=14, decimal_places=2)


class CustomerUpdate(BaseModel):
    """Opening balance is intentionally NOT editable here once set (use adjustments)."""

    name: str | None = Field(default=None, min_length=1, max_length=120)
    business_name: str | None = Field(default=None, max_length=160)
    customer_type: CustomerType | None = None
    phone: str | None = Field(default=None, pattern=PHONE_PATTERN)
    whatsapp: str | None = Field(default=None, pattern=PHONE_PATTERN)
    address: str | None = Field(default=None, max_length=500)
    status: PartyStatus | None = None
    notes: str | None = Field(default=None, max_length=2000)

    @field_validator("*", mode="before")
    @classmethod
    def strip_strings(cls, v):
        return _strip(v)


class CustomerOut(ORMModel):
    id: int
    code: str
    name: str
    business_name: str | None
    customer_type: CustomerType
    phone: str | None
    whatsapp: str | None
    address: str | None
    opening_balance: Decimal
    status: PartyStatus
    notes: str | None
    created_at: datetime
    # Filled by the ledger service once deliveries/payments exist (Phase 3/4).
    current_balance: Decimal | None = None


class SupplierCreate(_PartyBase):
    farm_name: str | None = Field(default=None, max_length=160)
    opening_balance: Decimal = Field(default=Decimal("0"), max_digits=14, decimal_places=2)


class SupplierUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    farm_name: str | None = Field(default=None, max_length=160)
    phone: str | None = Field(default=None, pattern=PHONE_PATTERN)
    address: str | None = Field(default=None, max_length=500)
    status: PartyStatus | None = None
    notes: str | None = Field(default=None, max_length=2000)

    @field_validator("*", mode="before")
    @classmethod
    def strip_strings(cls, v):
        return _strip(v)


class SupplierOut(ORMModel):
    id: int
    code: str
    name: str
    farm_name: str | None
    phone: str | None
    address: str | None
    opening_balance: Decimal
    status: PartyStatus
    notes: str | None
    created_at: datetime
    current_balance: Decimal | None = None
