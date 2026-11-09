from datetime import date, datetime, time
from decimal import Decimal

from pydantic import BaseModel, Field, model_validator

from app.models import ChickenType, PaymentMethod, RateUnit, RecordStatus
from app.schemas.common import ORMModel


class RateCreate(BaseModel):
    customer_id: int | None = None  # None = default rate for all customers
    chicken_type: ChickenType = ChickenType.live
    rate_unit: RateUnit = RateUnit.per_kg
    rate: Decimal = Field(ge=0, max_digits=14, decimal_places=2)
    effective_from: date
    notes: str | None = Field(default=None, max_length=500)


class RateOut(ORMModel):
    id: int
    customer_id: int | None
    chicken_type: ChickenType
    rate_unit: RateUnit
    rate: Decimal
    effective_from: date
    notes: str | None
    created_at: datetime


class CustomerBrief(ORMModel):
    id: int
    code: str
    name: str
    business_name: str | None
    phone: str | None
    whatsapp: str | None


class DeliveryCreate(BaseModel):
    idempotency_key: str | None = Field(default=None, max_length=64)
    customer_id: int
    delivery_date: date
    delivery_time: time | None = None
    chicken_type: ChickenType = ChickenType.live
    birds: int = Field(default=0, ge=0, le=1_000_000)
    pieces: int | None = Field(default=None, ge=0, le=10_000_000)
    gross_weight: Decimal | None = Field(default=None, gt=0, max_digits=12, decimal_places=3)  # defaults to net
    net_weight: Decimal = Field(gt=0, max_digits=12, decimal_places=3)
    rate: Decimal = Field(ge=0, max_digits=14, decimal_places=2)
    rate_unit: RateUnit = RateUnit.per_kg
    # Discount is given per KG; total discount = discount_per_kg x net_weight.
    discount_per_kg: Decimal = Field(default=Decimal("0"), ge=0, max_digits=14, decimal_places=2)
    additional_charges: Decimal = Field(default=Decimal("0"), ge=0, max_digits=14, decimal_places=2)
    payment_received: Decimal = Field(default=Decimal("0"), ge=0, max_digits=14, decimal_places=2)
    payment_method: PaymentMethod = PaymentMethod.cash
    payment_reference: str | None = Field(default=None, max_length=80)
    driver: str | None = Field(default=None, max_length=80)
    vehicle: str | None = Field(default=None, max_length=40)
    notes: str | None = Field(default=None, max_length=2000)
    allow_negative_stock: bool = False

    @model_validator(mode="after")
    def check(self):
        if self.gross_weight is None:
            self.gross_weight = self.net_weight
        if self.net_weight > self.gross_weight:
            raise ValueError("Net weight cannot be more than gross weight")
        if self.rate_unit == RateUnit.per_bird and self.birds == 0:
            raise ValueError("Number of pieces is required when rate is per piece")
        if self.discount_per_kg > self.rate and self.rate_unit == RateUnit.per_kg:
            raise ValueError("Discount per KG cannot be more than the rate")
        return self


class DeliveryOut(ORMModel):
    id: int
    invoice_no: str
    customer: CustomerBrief
    delivery_date: date
    delivery_time: time | None
    chicken_type: ChickenType
    birds: int
    pieces: int | None
    gross_weight: Decimal
    net_weight: Decimal
    rate: Decimal
    rate_unit: RateUnit
    amount: Decimal
    discount_per_kg: Decimal
    discount: Decimal
    additional_charges: Decimal
    total_amount: Decimal
    previous_balance: Decimal
    payment_received: Decimal
    balance_after: Decimal
    driver: str | None
    vehicle: str | None
    notes: str | None
    status: RecordStatus
    cancel_reason: str | None
    created_at: datetime


class DeliveryTotals(BaseModel):
    count: int
    birds: int
    net_weight: Decimal
    total_amount: Decimal
    payment_received: Decimal


class DeliveryList(BaseModel):
    items: list[DeliveryOut]
    totals: DeliveryTotals


class PaymentCreate(BaseModel):
    idempotency_key: str | None = Field(default=None, max_length=64)
    customer_id: int
    payment_date: date
    amount: Decimal = Field(gt=0, max_digits=14, decimal_places=2)
    method: PaymentMethod = PaymentMethod.cash
    reference: str | None = Field(default=None, max_length=80)
    notes: str | None = Field(default=None, max_length=1000)


class PaymentOut(ORMModel):
    id: int
    receipt_no: str
    customer_id: int
    delivery_id: int | None
    payment_date: date
    amount: Decimal
    method: PaymentMethod
    reference: str | None
    notes: str | None
    status: RecordStatus
    created_at: datetime


class LedgerEntryOut(BaseModel):
    date: date
    time: time | None
    kind: str
    ref_no: str
    ref_id: int
    description: str
    chicken_type: str | None
    birds: int
    weight: Decimal
    rate: Decimal | None
    rate_unit: str | None
    debit: Decimal
    credit: Decimal
    balance: Decimal


class LedgerOut(BaseModel):
    customer_id: int
    date_from: date
    date_to: date
    opening_balance: Decimal
    entries: list[LedgerEntryOut]
    total_debit: Decimal
    total_credit: Decimal
    total_birds: int
    total_weight: Decimal
    closing_balance: Decimal
