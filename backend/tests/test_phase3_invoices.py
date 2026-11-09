from decimal import Decimal

API = "/api/v1"
D = Decimal


def _setup(client, h, opening="24500"):
    sid = client.post(f"{API}/suppliers", json={"name": "Rana Farms"}, headers=h).json()["id"]
    client.post(
        f"{API}/purchases",
        json={
            "supplier_id": sid, "purchase_date": "2026-11-01", "chicken_type": "live", "birds": 1000,
            "gross_weight": "2100", "net_weight": "2000", "rate": "450", "rate_unit": "per_kg",
        },
        headers=h,
    )
    cid = client.post(
        f"{API}/customers",
        json={"name": "Ali Chicken Shop", "whatsapp": "0300-1112223", "opening_balance": opening},
        headers=h,
    ).json()["id"]
    return cid


def _deliver(client, h, cid, **kw):
    body = {
        "customer_id": cid, "delivery_date": "2026-11-09", "delivery_time": "06:30:00", "chicken_type": "live",
        "birds": 40, "gross_weight": "86", "net_weight": "85.5", "rate": "520", "rate_unit": "per_kg",
        "payment_received": "40000",
    }
    body.update(kw)
    return client.post(f"{API}/deliveries", json=body, headers=h)


def test_invoice_matches_daily_flow(client, admin_headers):
    """Pichla baqaya 24,500 + 85.5kg x 520 = 44,460 -> 68,960; wusool 40,000 -> baqaya 28,960."""
    cid = _setup(client, admin_headers)
    r = _deliver(client, admin_headers, cid)
    assert r.status_code == 201, r.text
    d = r.json()
    assert d["invoice_no"] == "INV-000001"
    assert D(d["amount"]) == D("44460.00")
    assert D(d["previous_balance"]) == D("24500.00")
    assert D(d["payment_received"]) == D("40000.00")
    assert D(d["balance_after"]) == D("28960.00")
    c = client.get(f"{API}/customers/{cid}", headers=admin_headers).json()
    assert D(c["current_balance"]) == D("28960.00")
    stock = client.get(f"{API}/stock/current", headers=admin_headers).json()["live"]
    assert stock == {"birds": 960, "weight": "1914.500"}


def test_each_supply_gets_its_own_invoice(client, admin_headers):
    cid = _setup(client, admin_headers)
    a = _deliver(client, admin_headers, cid).json()
    b = _deliver(client, admin_headers, cid, delivery_time="13:00:00", birds=10, net_weight="20", gross_weight="20",
                 payment_received="0").json()
    assert a["invoice_no"] != b["invoice_no"]
    # Second invoice starts from the first one's remaining balance.
    assert D(b["previous_balance"]) == D("28960.00")
    assert D(b["balance_after"]) == D("39360.00")  # + 20 x 520


def test_discount_per_kg(client, admin_headers):
    """85.5 KG x 520 = 44,460; discount 10/KG x 85.5 = 855 -> 43,605; + old 24,500 - paid 40,000 = 28,105."""
    cid = _setup(client, admin_headers)
    d = _deliver(client, admin_headers, cid, discount_per_kg="10").json()
    assert D(d["amount"]) == D("44460.00")
    assert D(d["discount_per_kg"]) == D("10.00")
    assert D(d["discount"]) == D("855.00")
    assert D(d["total_amount"]) == D("43605.00")
    assert D(d["balance_after"]) == D("28105.00")
    # Rounding: 0.333 KG x 1.50/KG = 0.4995 -> 0.50
    d2 = _deliver(client, admin_headers, cid, net_weight="0.333", gross_weight="0.333", rate="100",
                  discount_per_kg="1.50", payment_received="0").json()
    assert D(d2["discount"]) == D("0.50") and D(d2["total_amount"]) == D("32.80")
    assert _deliver(client, admin_headers, cid, discount_per_kg="600").status_code == 422


def test_historical_invoice_keeps_rate(client, admin_headers):
    cid = _setup(client, admin_headers)
    client.post(f"{API}/rates", json={"rate": "520", "effective_from": "2026-11-01"}, headers=admin_headers)
    d = _deliver(client, admin_headers, cid).json()
    client.post(f"{API}/rates", json={"rate": "600", "effective_from": "2026-11-09"}, headers=admin_headers)
    again = client.get(f"{API}/deliveries/{d['id']}", headers=admin_headers).json()
    assert D(again["rate"]) == D("520.00") and D(again["amount"]) == D("44460.00")


def test_applicable_rate_customer_beats_default(client, admin_headers):
    cid = _setup(client, admin_headers)
    client.post(f"{API}/rates", json={"rate": "500", "effective_from": "2026-11-01"}, headers=admin_headers)
    client.post(f"{API}/rates", json={"rate": "510", "effective_from": "2026-11-05"}, headers=admin_headers)
    q = {"customer_id": cid, "chicken_type": "live", "on": "2026-11-04"}
    assert D(client.get(f"{API}/rates/applicable", params=q, headers=admin_headers).json()["rate"]) == D("500")
    q["on"] = "2026-11-09"
    assert D(client.get(f"{API}/rates/applicable", params=q, headers=admin_headers).json()["rate"]) == D("510")
    client.post(f"{API}/rates", json={"customer_id": cid, "rate": "495", "effective_from": "2026-11-08"}, headers=admin_headers)
    assert D(client.get(f"{API}/rates/applicable", params=q, headers=admin_headers).json()["rate"]) == D("495")


def test_supply_is_unlimited_by_default(client, admin_headers):
    cid = client.post(f"{API}/customers", json={"name": "No Stock Shop"}, headers=admin_headers).json()["id"]
    r = _deliver(client, admin_headers, cid, birds=5000, net_weight="9000", gross_weight="9000")
    assert r.status_code == 201, r.text


def test_cannot_supply_more_than_stock_when_enforced(client, admin_headers):
    from app.core.config import get_settings

    get_settings().enforce_stock = True
    try:
        cid = _setup(client, admin_headers)
        r = _deliver(client, admin_headers, cid, birds=1001)
        assert r.status_code == 409
        assert client.get(f"{API}/deliveries", headers=admin_headers).json()["totals"]["count"] == 0
    finally:
        get_settings().enforce_stock = False


def test_gross_weight_optional_and_pieces_optional(client, admin_headers):
    cid = _setup(client, admin_headers)
    body = {"customer_id": cid, "delivery_date": "2026-11-09", "net_weight": "10", "rate": "500"}
    r = client.post(f"{API}/deliveries", json=body, headers=admin_headers)
    assert r.status_code == 201, r.text
    assert D(r.json()["gross_weight"]) == D("10.000") and r.json()["birds"] == 0


def test_cancel_restores_stock_and_balance(client, admin_headers):
    cid = _setup(client, admin_headers)
    d = _deliver(client, admin_headers, cid).json()
    r = client.post(f"{API}/deliveries/{d['id']}/cancel", json={"reason": "wrong customer"}, headers=admin_headers)
    assert r.status_code == 200
    assert D(client.get(f"{API}/customers/{cid}", headers=admin_headers).json()["current_balance"]) == D("24500.00")
    assert client.get(f"{API}/stock/current", headers=admin_headers).json()["live"]["birds"] == 1000
    assert client.get(f"{API}/payments", params={"customer_id": cid}, headers=admin_headers).json() == []


def test_duplicate_submit(client, admin_headers):
    cid = _setup(client, admin_headers)
    a = _deliver(client, admin_headers, cid, idempotency_key="k1").json()
    b = _deliver(client, admin_headers, cid, idempotency_key="k1").json()
    assert a["id"] == b["id"]
    assert client.get(f"{API}/deliveries", headers=admin_headers).json()["totals"]["count"] == 1


def test_operator_can_record_but_not_cancel(client, admin_headers, operator_headers):
    cid = _setup(client, admin_headers)
    d = _deliver(client, operator_headers, cid)
    assert d.status_code == 201
    r = client.post(f"{API}/deliveries/{d.json()['id']}/cancel", json={"reason": "x" * 5}, headers=operator_headers)
    assert r.status_code == 403


def test_ledger_running_balance(client, admin_headers):
    cid = _setup(client, admin_headers)
    _deliver(client, admin_headers, cid, delivery_date="2026-11-08")  # before period
    _deliver(client, admin_headers, cid, delivery_date="2026-11-09", payment_received="0", birds=10, net_weight="10", gross_weight="10")
    client.post(f"{API}/payments", json={"customer_id": cid, "payment_date": "2026-11-09", "amount": "5000"}, headers=admin_headers)
    lg = client.get(
        f"{API}/customers/{cid}/ledger", params={"date_from": "2026-11-09", "date_to": "2026-11-09"}, headers=admin_headers
    ).json()
    assert D(lg["opening_balance"]) == D("28960.00")
    assert [e["kind"] for e in lg["entries"]] == ["delivery", "payment"]
    assert [D(e["balance"]) for e in lg["entries"]] == [D("34160.00"), D("29160.00")]
    assert D(lg["closing_balance"]) == D("29160.00")
    assert D(lg["total_debit"]) == D("5200.00") and D(lg["total_credit"]) == D("5000.00")


def test_message_and_pdf(client, admin_headers):
    cid = _setup(client, admin_headers)
    d = _deliver(client, admin_headers, cid).json()
    dd = _deliver(client, admin_headers, cid, discount_per_kg="10").json()
    md = client.get(f"{API}/deliveries/{dd['id']}/message", headers=admin_headers).json()["text"]
    assert "Discount (Rs 10/KG): -Rs 855" in md and "After discount: Rs 43,605" in md
    m = client.get(f"{API}/deliveries/{d['id']}/message", headers=admin_headers).json()
    assert "M Ishaq Poultry Services" in m["text"]
    assert "Previous balance: Rs 24,500" in m["text"]
    assert "*Remaining balance: Rs 28,960*" in m["text"]
    assert "🐔" in m["text"] and "🐔" not in m["sms_text"] and "*" not in m["sms_text"]
    assert "Remaining balance: Rs 28,960" in m["sms_text"]
    assert m["whatsapp"] == "0300-1112223"
    pdf = client.get(f"{API}/deliveries/{d['id']}/pdf", headers=admin_headers)
    assert pdf.status_code == 200
    assert pdf.headers["content-type"] == "application/pdf"
    assert pdf.content[:4] == b"%PDF"
