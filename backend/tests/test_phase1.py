from decimal import Decimal

from app.models import AuditLog

API = "/api/v1"


def test_login_rejects_wrong_password(client, admin_headers):
    r = client.post(f"{API}/auth/login", json={"username": "owner", "password": "wrong"})
    assert r.status_code == 401


def test_requires_auth(client):
    assert client.get(f"{API}/customers").status_code == 401


def test_customer_create_codes_and_decimal(client, admin_headers):
    r1 = client.post(
        f"{API}/customers",
        json={"name": "Ali Chicken Shop", "phone": "0301-1234567", "opening_balance": "15000.50"},
        headers=admin_headers,
    )
    assert r1.status_code == 201, r1.text
    body = r1.json()
    assert body["code"] == "CUS-0001"
    assert Decimal(body["opening_balance"]) == Decimal("15000.50")

    r2 = client.post(f"{API}/customers", json={"name": "Hotel Lahore"}, headers=admin_headers)
    assert r2.json()["code"] == "CUS-0002"


def test_customer_duplicate_rejected(client, admin_headers):
    data = {"name": "Ali Shop", "phone": "03011234567"}
    assert client.post(f"{API}/customers", json=data, headers=admin_headers).status_code == 201
    dup = {"name": "ali shop", "phone": "03011234567"}
    assert client.post(f"{API}/customers", json=dup, headers=admin_headers).status_code == 409


def test_customer_validation(client, admin_headers):
    assert client.post(f"{API}/customers", json={"name": ""}, headers=admin_headers).status_code == 422
    bad_phone = {"name": "X", "phone": "abc"}
    assert client.post(f"{API}/customers", json=bad_phone, headers=admin_headers).status_code == 422
    too_precise = {"name": "Y", "opening_balance": "10.123"}
    assert client.post(f"{API}/customers", json=too_precise, headers=admin_headers).status_code == 422


def test_customer_search_and_update_is_audited(client, db, admin_headers):
    cid = client.post(
        f"{API}/customers", json={"name": "Bismillah Hotel", "customer_type": "hotel"}, headers=admin_headers
    ).json()["id"]
    client.post(f"{API}/customers", json={"name": "Madina Shop"}, headers=admin_headers)

    r = client.get(f"{API}/customers", params={"q": "bism"}, headers=admin_headers)
    assert r.json()["total"] == 1

    r = client.patch(
        f"{API}/customers/{cid}", json={"whatsapp": "+92 300 1112223", "status": "inactive"}, headers=admin_headers
    )
    assert r.status_code == 200
    assert r.json()["status"] == "inactive"

    logs = db.query(AuditLog).filter_by(entity="customer", entity_id=cid).all()
    assert [l.action for l in logs] == ["create", "update"]
    assert logs[1].before["status"] == "active" and logs[1].after["status"] == "inactive"


def test_opening_balance_not_editable_via_update(client, admin_headers):
    cid = client.post(
        f"{API}/customers", json={"name": "Z", "opening_balance": "500"}, headers=admin_headers
    ).json()["id"]
    client.patch(f"{API}/customers/{cid}", json={"opening_balance": "0"}, headers=admin_headers)
    assert Decimal(client.get(f"{API}/customers/{cid}", headers=admin_headers).json()["opening_balance"]) == 500


def test_operator_cannot_create_customer(client, operator_headers):
    r = client.post(f"{API}/customers", json={"name": "X"}, headers=operator_headers)
    assert r.status_code == 403


def test_supplier_crud(client, admin_headers):
    r = client.post(
        f"{API}/suppliers",
        json={"name": "Rana Farms", "farm_name": "Rana Poultry Farm", "opening_balance": "250000"},
        headers=admin_headers,
    )
    assert r.status_code == 201, r.text
    assert r.json()["code"] == "SUP-0001"
    sid = r.json()["id"]
    r = client.patch(f"{API}/suppliers/{sid}", json={"phone": "0300 1234567"}, headers=admin_headers)
    assert r.json()["phone"] == "0300 1234567"
    assert client.get(f"{API}/suppliers", params={"q": "rana"}, headers=admin_headers).json()["total"] == 1


def test_admin_user_management(client, admin_headers):
    r = client.post(
        f"{API}/users",
        json={"username": "munshi", "full_name": "Munshi", "password": "abc12345", "role": "manager"},
        headers=admin_headers,
    )
    assert r.status_code == 201
    me = client.get(f"{API}/auth/me", headers=admin_headers).json()
    r = client.patch(f"{API}/users/{me['id']}", json={"is_active": False}, headers=admin_headers)
    assert r.status_code == 400
