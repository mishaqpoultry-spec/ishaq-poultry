from datetime import date, datetime, time
from decimal import Decimal
from enum import Enum

from sqlalchemy import inspect, select
from sqlalchemy.orm import Session

from app.models import AuditLog, Counter


def next_number(db: Session, name: str, prefix: str, width: int = 4) -> str:
    """Return the next document number for `name`, locking the counter row."""
    counter = db.execute(
        select(Counter).where(Counter.name == name).with_for_update()
    ).scalar_one_or_none()
    if counter is None:
        counter = Counter(name=name, next_value=1)
        db.add(counter)
        db.flush()
    value = counter.next_value
    counter.next_value = value + 1
    return f"{prefix}-{value:0{width}d}"


def _jsonable(v):
    if isinstance(v, Decimal):
        return str(v)
    if isinstance(v, (date, datetime, time)):
        return v.isoformat()
    if isinstance(v, Enum):
        return v.value
    return v


def snapshot(obj) -> dict:
    return {c.key: _jsonable(getattr(obj, c.key)) for c in inspect(obj).mapper.column_attrs}


def audit(
    db: Session,
    user_id: int | None,
    action: str,
    entity: str,
    entity_id: int | None,
    before: dict | None = None,
    after: dict | None = None,
) -> None:
    db.add(
        AuditLog(
            user_id=user_id,
            action=action,
            entity=entity,
            entity_id=entity_id,
            before=before,
            after=after,
        )
    )
