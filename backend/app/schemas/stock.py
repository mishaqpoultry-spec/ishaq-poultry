from datetime import date, datetime, time
from decimal import Decimal

from pydantic import BaseModel, Field, model_validator

from app.models import ChickenType, LossKind, RateUnit, RecordStatus, StockTxnKind
from app.schemas.common import ORMModel

WeightField = Field(max_digits=12, decimal_places=3)
MoneyField = Field(max_digits=14, decimal_places=2)


class PurchaseCreate(BaseModel):
    idempotency_key: str | None = Field(default=None, max_length=64)
    supplier_id: int
    purchase_date: date
    receiving_time: time | None = None
    chicken_type: ChickenType = ChickenType.live
    birds: int = Field(ge=0, le=1_000_000)
    gross_weight: Decimal = Field(gt=0, max_digits=12, decimal_places=3)
    net_weight: Decimal = Field(gt=0, max_digits=12, decimal_places=3)
    rate: Decimal = Field(ge=0, max_digits=14, decimal_places=2)
    rate_unit: RateUnit = RateUnit.per_kg
    transport_charges: Decimal = Field(default=Decimal("0"), ge=0, max_digits=14, decimal_places=2)
    other_expenses: Decimal = Field(default=Decimal("0"), ge=0, max_digits=14, decimal_places=2)
    supplier_ref: str | None = Field(default=None, max_length=60)
    notes: str | None = Field(default=None, max_length=2000)

    @model_validator(mode="after")
    def check(self):
        if self.net_weight > self.gross_weight:
            raise ValueError("Net weight cannot be more than gross weight")
        if self.rate_unit == RateUnit.per_bird and self.birds == 0:
            raise ValueError("Number of birds is required when rate is per bird")
        if self.chicken_type == ChickenType.live and self.birds == 0:
            raise ValueError("Number of birds is required for live chicken")
        return self


class SupplierBrief(ORMModel):
    id: int
    code: str
    name: str


class PurchaseOut(ORMModel):
    id: int
    ref_no: str
    supplier: SupplierBrief
    purchase_date: date
    receiving_time: time | None
    chicken_type: ChickenType
    birds: int
    gross_weight: Decimal
    net_weight: Decimal
    rate: Decimal
    rate_unit: RateUnit
    amount: Decimal
    transport_charges: Decimal
    other_expenses: Decimal
    total_cost: Decimal
    supplier_ref: str | None
    notes: str | None
    status: RecordStatus
    cancel_reason: str | None
    created_at: datetime


class PurchaseTotals(BaseModel):
    count: int
    birds: int
    net_weight: Decimal
    amount: Decimal
    total_cost: Decimal


class PurchaseList(BaseModel):
    items: list[PurchaseOut]
    totals: PurchaseTotals


class CancelIn(BaseModel):
    reason: str = Field(min_length=3, max_length=500)
    allow_negative_stock: bool = False


class LossCreate(BaseModel):
    idempotency_key: str | None = Field(default=None, max_length=64)
    loss_date: date
    chicken_type: ChickenType = ChickenType.live
    kind: LossKind
    birds: int = Field(default=0, ge=0, le=1_000_000)
    weight: Decimal = Field(default=Decimal("0"), ge=0, max_digits=12, decimal_places=3)
    purchase_id: int | None = None
    reason: str | None = Field(default=None, max_length=1000)

    @model_validator(mode="after")
    def check(self):
        if self.birds == 0 and self.weight == 0:
            raise ValueError("Enter birds or weight")
        return self


class LossOut(ORMModel):
    id: int
    ref_no: str
    loss_date: date
    chicken_type: ChickenType
    kind: LossKind
    birds: int
    weight: Decimal
    purchase_id: int | None
    reason: str | None
    status: RecordStatus
    created_at: datetime


class ProcessingCreate(BaseModel):
    idempotency_key: str | None = Field(default=None, max_length=64)
    process_date: date
    input_type: ChickenType = ChickenType.live
    output_type: ChickenType = ChickenType.dressed
    input_birds: int = Field(ge=1, le=1_000_000)
    input_weight: Decimal = Field(gt=0, max_digits=12, decimal_places=3)
    output_birds: int | None = Field(default=None, ge=0, le=1_000_000)
    output_weight: Decimal = Field(gt=0, max_digits=12, decimal_places=3)
    notes: str | None = Field(default=None, max_length=1000)

    @model_validator(mode="after")
    def check(self):
        if self.input_type == self.output_type:
            raise ValueError("Output type must differ from input type")
        if self.output_type == ChickenType.live:
            raise ValueError("Output cannot be live chicken")
        if self.output_weight > self.input_weight:
            raise ValueError("Output weight cannot exceed input weight")
        return self


class ProcessingOut(ORMModel):
    id: int
    ref_no: str
    process_date: date
    input_type: ChickenType
    output_type: ChickenType
    input_birds: int
    input_weight: Decimal
    output_birds: int
    output_weight: Decimal
    wastage_weight: Decimal
    yield_percent: Decimal
    notes: str | None
    status: RecordStatus
    created_at: datetime


class StockTxnOut(ORMModel):
    id: int
    txn_date: date
    chicken_type: ChickenType
    kind: StockTxnKind
    birds: int
    weight: Decimal
    ref_type: str
    ref_id: int
    ref_no: str | None
    notes: str | None
    created_at: datetime
