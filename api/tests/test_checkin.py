from .conftest import authz, make_organizer, signup
from .test_capacity import make_event


def test_checkin_ok_then_duplicate(client, db):
    org = make_organizer(client, db)
    event = make_event(client, org, capacity=10)
    a = signup(client, email="a@example.com")
    code = client.post(f"/events/{event['id']}/register", headers=authz(a)).json()["code"]
    r = client.post("/check-in", json={"code": code}, headers=authz(org))
    assert r.status_code == 200
    assert r.json()["result"] == "ok"
    r = client.post("/check-in", json={"code": code}, headers=authz(org))
    assert r.status_code == 409  # duplicate
    from app import models

    results = sorted(x.result for x in db.query(models.CheckIn).all())
    assert results == ["duplicate", "ok"]


def test_checkin_unknown_code(client, db):
    org = make_organizer(client, db)
    r = client.post("/check-in", json={"code": "EVT-9-ZZZZ"}, headers=authz(org))
    assert r.status_code == 404


def test_cancel_used_ticket_blocked(client, db):
    org = make_organizer(client, db)
    event = make_event(client, org, capacity=10)
    a = signup(client, email="a@example.com")
    code = client.post(f"/events/{event['id']}/register", headers=authz(a)).json()["code"]
    client.post("/check-in", json={"code": code}, headers=authz(org))
    from app import models

    reg = db.query(models.Registration).filter_by(event_id=event["id"]).first()
    r = client.delete(f"/registrations/{reg.id}", headers=authz(a))
    assert r.status_code == 409
