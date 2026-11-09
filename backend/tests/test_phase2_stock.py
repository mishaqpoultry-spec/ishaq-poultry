from decimal import Decimal

from sqlalchemy import func, select

from app.models import StockBalance, StockTransaction

API = "/api/v1"
D = Decimal


def _supplier(client, h, name="Rana Farms", opening="0"):
    return client.post(f"{API}/suppliers", json={"name": name, "opening_balance": opening}, headers=h).json()["id"]


def _purchase(client, h, sid, **kw):
    body = {
        "supplier_id": sid,
        "purchase_date": "2026-11-09",
        "receiving_time": "06:30:00",
        "chicken_type": "live",
        "birds": 500,
        "gross_weight": "1050.500",
        "net_weight": "1030.250",
        "rate": "480.00",
        "rate_unit": "per_kg",
        "transport_charges": "3000",
        "other_expenses": "500",
    }
    body.update(kw)
    return client.post(f"{API}/purchases", json=body, headers=h)


def _current(client, h, ct="live"):
    c = client.get(f"{API}/stock/current", headers=h).json()[ct]
    return c["birds"], D(c["weight"])


def test_purchase_amount_cost_and_stock(client, admin_headers):
    sid = _supplier(client, admin_headers)
    r = _purchase(client, admin_headers, sid)
    assert r.status_code == 201, r.text
    p = r.json()
    assert p["ref_no"] == "PUR-000001"
    # 1030.250 kg x 480 = 494,520.00
    assert D(p["amount"]) == D("494520.00")
    assert D(p["total_cost"]) == D("498020.00")
    assert _current(client, admin_headers) == (500, D("1030.250"))


def test_per_bird_rate(client, admin_headers):
    sid = _supplier(client, admin_headers)
    p = _purchase(client, admin_headers, sid, rate="950", rate_unit="per_bird", birds=200).json()
    assert D(p["amount"]) == D("190000.00")


def test_validation(client, admin_headers):
    sid = _supplier(client, admin_headers)
    assert _purchase(client, admin_headers, sid, net_weight="1100", gross_weight="1000").status_code == 422
    assert _purchase(client, admin_headers, sid, birds=0).status_code == 422  # live needs birds
    assert _purchase(client, admin_headers, sid, net_weight="10.1234").status_code == 422
    assert _purchase(client, admin_headers, 9999).status_code == 404


def test_duplicate_submit_is_ignored(client, admin_headers):
    sid = _supplier(client, admin_headers)
    a = _purchase(client, admin_headers, sid, idempotency_key="abc-123").json()
    b = _purchase(client, admin_headers, sid, idempotency_key="abc-123").json()
    assert a["id"] == b["id"]
    assert _current(client, admin_headers) == (500, D("1030.250"))


def test_supplier_payable_balance(client, admin_headers):
    sid = _supplier(client, admin_headers, opening="10000")
    _purchase(client, admin_headers, sid, birds=10, net_weight="20", gross_weight="21", rate="500")
    s = client.get(f"{API}/suppliers/{sid}", headers=admin_headers).json()
    # opening 10,000 + 20 kg x 500 (transport is a cost, not payable to supplier)
    assert D(s["current_balance"]) == D("20000.00")


def test_cancel_reverses_stock_and_keeps_record(client, admin_headers):
    sid = _supplier(client, admin_headers)
    pid = _purchase(client, admin_headers, sid).json()["id"]
    r = client.post(f"{API}/purchases/{pid}/cancel", json={"reason": "wrong entry"}, headers=admin_headers)
    assert r.status_code == 200 and r.json()["status"] == "cancelled"
    assert _current(client, admin_headers) == (0, D("0.000"))
    assert client.get(f"{API}/purchases", headers=admin_headers).json()["totals"]["count"] == 0
    all_ = client.get(f"{API}/purchases", params={"include_cancelled": True}, headers=admin_headers).json()
    assert len(all_["items"]) == 1
    again = client.post(f"{API}/purchases/{pid}/cancel", json={"reason": "again"}, headers=admin_headers)
    assert again.status_code == 400


def test_loss_cannot_make_stock_negative(client, admin_headers):
    sid = _supplier(client, admin_headers)
    _purchase(client, admin_headers, sid, birds=100, net_weight="200", gross_weight="205")
    r = client.post(
        f"{API}/stock/losses",
        json={"loss_date": "2026-11-09", "kind": "dead", "birds": 101, "weight": "2"},
        headers=admin_headers,
    )
    assert r.status_code == 409
    assert "Not enough live stock" in r.json()["detail"]
    r = client.post(
        f"{API}/stock/losses",
        json={"loss_date": "2026-11-09", "kind": "dead", "birds": 3, "weight": "5.400", "reason": "heat"},
        headers=admin_headers,
    )
    assert r.status_code == 201
    assert _current(client, admin_headers) == (97, D("194.600"))


def test_processing_live_to_dressed(client, admin_headers):
    sid = _supplier(client, admin_headers)
    _purchase(client, admin_headers, sid, birds=100, net_weight="200", gross_weight="205")
    r = client.post(
        f"{API}/stock/processing",
        json={"process_date": "2026-11-09", "input_birds": 50, "input_weight": "100", "output_weight": "70.500"},
        headers=admin_headers,
    )
    assert r.status_code == 201, r.text
    p = r.json()
    assert D(p["wastage_weight"]) == D("29.500")
    assert D(p["yield_percent"]) == D("70.50")
    assert _current(client, admin_headers, "live") == (50, D("100.000"))
    assert _current(client, admin_headers, "dressed") == (50, D("70.500"))

    client.post(f"{API}/stock/processing/{p['id']}/cancel", json={"reason": "mistake"}, headers=admin_headers)
    assert _current(client, admin_headers, "live") == (100, D("200.000"))
    assert _current(client, admin_headers, "dressed") == (0, D("0.000"))


def test_summary_opening_closing_reconciles(client, db, admin_headers):
    sid = _supplier(client, admin_headers)
    _purchase(client, admin_headers, sid, purchase_date="2026-11-08", birds=100, net_weight="200", gross_weight="201")
    _purchase(client, admin_headers, sid, purchase_date="2026-11-09", birds=50, net_weight="110.5", gross_weight="111")
    client.post(
        f"{API}/stock/losses",
        json={"loss_date": "2026-11-09", "kind": "wastage", "weight": "1.5"},
        headers=admin_headers,
    )
    s = client.get(
        f"{API}/stock/summary", params={"date_from": "2026-11-09", "date_to": "2026-11-09"}, headers=admin_headers
    ).json()["types"]["live"]
    assert s["opening"] == {"birds": 100, "weight": "200.000"}
    assert s["received"] == {"birds": 50, "weight": "110.500"}
    assert s["losses"] == {"birds": 0, "weight": "1.500"}
    assert s["closing"] == {"birds": 150, "weight": "309.000"}

    # Ledger and balance table must always agree.
    bal = db.execute(select(StockBalance).where(StockBalance.chicken_type == "live")).scalar_one()
    b, w = db.execute(
        select(func.sum(StockTransaction.birds), func.sum(StockTransaction.weight)).where(
            StockTransaction.chicken_type == "live"
        )
    ).one()
    assert (bal.birds, D(bal.weight)) == (b, D(w))


def test_operator_cannot_record_purchase(client, admin_headers, operator_headers):
    sid = _supplier(client, admin_headers)
    assert _purchase(client, operator_headers, sid).status_code == 403
