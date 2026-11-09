"""Tests run on in-memory SQLite by default (no setup needed).

Set PG_TEST=1 to run the same tests against the real PostgreSQL database from
.env — each test runs inside a transaction that is rolled back, so no data is
left behind.
"""

import os

PG = os.environ.get("PG_TEST") == "1"
if not PG:
    os.environ["DATABASE_URL"] = "sqlite+pysqlite:///:memory:"
os.environ["JWT_SECRET"] = "test-secret-test-secret-test-secret"

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.core.database import get_db
from app.core.security import hash_password
from app.main import app
from app.models import Base, User, UserRole


@pytest.fixture()
def db():
    if PG:
        from app.core.database import engine

        conn = engine.connect()
        outer = conn.begin()
        session = Session(bind=conn, join_transaction_mode="create_savepoint", expire_on_commit=False, autoflush=False)
        yield session
        session.close()
        outer.rollback()
        conn.close()
    else:
        engine = create_engine(
            "sqlite+pysqlite:///:memory:", connect_args={"check_same_thread": False}, poolclass=StaticPool
        )
        Base.metadata.create_all(engine)
        session = Session(bind=engine, autoflush=False, expire_on_commit=False)
        yield session
        session.close()


@pytest.fixture()
def client(db):
    def _override():
        try:
            yield db
        except Exception:
            db.rollback()
            raise

    app.dependency_overrides[get_db] = _override
    yield TestClient(app)
    app.dependency_overrides.clear()


def _make_user(db, username, role):
    u = User(username=username, full_name=username.title(), password_hash=hash_password("secret123"), role=role)
    db.add(u)
    db.commit()
    return u


def _token(client, username):
    r = client.post("/api/v1/auth/login", json={"username": username, "password": "secret123"})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


@pytest.fixture()
def admin_headers(client, db):
    _make_user(db, "test_owner", UserRole.admin)
    return _token(client, "test_owner")


@pytest.fixture()
def operator_headers(client, db):
    _make_user(db, "test_worker", UserRole.operator)
    return _token(client, "test_worker")
