from .conftest import authz, make_organizer, signup
from .test_capacity import make_event


def test_my_tickets_and_stats(client, db):
    org = make_organizer(client, db)
    event = make_event(client, org, capacity=10)
    a = signup(client, email="a@example.com")
    code = client.post(f"/events/{event['id']}/register", headers=authz(a)).json()["code"]
    tickets = client.get("/me/tickets", headers=authz(a)).json()
    assert [t["code"] for t in tickets] == [code]
    assert tickets[0]["status"] == "active"
    client.post("/check-in", json={"code": code}, headers=authz(org))
    stats = client.get(f"/events/{event['id']}/stats", headers=authz(org)).json()
    assert stats == {"registrations": 1, "visits": 1, "capacity": 10}
    guests = client.get(f"/events/{event['id']}/guests", headers=authz(org)).json()
    assert [g["email"] for g in guests] == ["a@example.com"]


def test_favorites_roundtrip(client, db):
    org = make_organizer(client, db)
    event = make_event(client, org, capacity=10)
    a = signup(client, email="a@example.com")
    assert client.post("/me/favorites", json={"event_id": event["id"]}, headers=authz(a)).status_code == 201
    assert client.get("/me/favorites", headers=authz(a)).json() == [event["id"]]
    assert client.delete(f"/me/favorites/{event['id']}", headers=authz(a)).status_code == 204
    assert client.get("/me/favorites", headers=authz(a)).json() == []


def test_categories_and_catalog(client, db):
    from app import models

    db.add(models.Category(slug="music", title="Музыка"))
    db.commit()
    org = make_organizer(client, db)
    e1 = make_event(client, org, capacity=10)
    music_id = client.get("/categories").json()[0]["id"]
    e2 = client.post(
        "/events",
        json={"title": "Jazz Night", "city": "Алматы", "capacity": 50, "category_id": music_id},
        headers=authz(org),
    ).json()
    assert client.get("/categories").json()[0]["slug"] == "music"
    assert any(e["id"] == e1["id"] for e in client.get("/events").json())
    assert any(e["id"] == e1["id"] for e in client.get("/events", params={"q": "Meet"}).json())
    assert [e["id"] for e in client.get("/events", params={"category": "Музыка"}).json()] == [e2["id"]]
    assert client.get("/events", params={"category": "НетТакой"}).json() == []


def test_admin_overview_forbidden_for_visitor(client, db):
    a = signup(client, email="a@example.com")
    assert client.get("/admin/overview", headers=authz(a)).status_code == 403
