from .conftest import authz, make_organizer, signup


def make_event(client, org_tokens, capacity=2):
    r = client.post(
        "/events",
        json={"title": "Meetup", "city": "Алматы", "place": "Hall", "capacity": capacity},
        headers=authz(org_tokens),
    )
    assert r.status_code == 201, r.text
    return r.json()


def test_capacity_limit(client, db):
    org = make_organizer(client, db)
    event = make_event(client, org, capacity=2)
    a = signup(client, email="a@example.com")
    b = signup(client, email="b@example.com")
    c = signup(client, email="c@example.com")
    assert client.post(f"/events/{event['id']}/register", headers=authz(a)).status_code == 201
    assert client.post(f"/events/{event['id']}/register", headers=authz(b)).status_code == 201
    r = client.post(f"/events/{event['id']}/register", headers=authz(c))
    assert r.status_code == 409  # sold out


def test_double_registration_blocked(client, db):
    org = make_organizer(client, db)
    event = make_event(client, org, capacity=10)
    a = signup(client, email="a@example.com")
    assert client.post(f"/events/{event['id']}/register", headers=authz(a)).status_code == 201
    r = client.post(f"/events/{event['id']}/register", headers=authz(a))
    assert r.status_code == 409


def test_cancel_frees_seat(client, db):
    org = make_organizer(client, db)
    event = make_event(client, org, capacity=1)
    a = signup(client, email="a@example.com")
    b = signup(client, email="b@example.com")
    assert client.post(f"/events/{event['id']}/register", headers=authz(a)).status_code == 201
    assert client.post(f"/events/{event['id']}/register", headers=authz(b)).status_code == 409
    # регистрация a — единственная; узнаём id через гостей организатора
    guests = client.get(f"/events/{event['id']}/guests", headers=authz(org)).json()
    assert len(guests) == 1
    from app import models

    reg = db.query(models.Registration).filter_by(event_id=event["id"]).first()
    assert client.delete(f"/registrations/{reg.id}", headers=authz(a)).status_code == 204
    assert client.post(f"/events/{event['id']}/register", headers=authz(b)).status_code == 201


def test_waitlist_promotes_first_guest_after_cancellation(client, db):
    org = make_organizer(client, db)
    event = make_event(client, org, capacity=1)
    first = signup(client, email="first@example.com")
    waiting = signup(client, email="waiting@example.com")

    ticket = client.post(f"/events/{event['id']}/register", headers=authz(first))
    assert ticket.status_code == 201
    queued = client.post(f"/events/{event['id']}/waitlist", headers=authz(waiting))
    assert queued.status_code == 201
    assert queued.json()["status"] == "waitlisted"
    assert queued.json()["position"] == 1

    reg_id = ticket.json()["registration_id"]
    assert client.delete(f"/registrations/{reg_id}", headers=authz(first)).status_code == 204

    promoted = client.get("/me/tickets", headers=authz(waiting))
    assert promoted.status_code == 200
    assert len(promoted.json()) == 1
    assert promoted.json()[0]["event_id"] == event["id"]
    assert promoted.json()[0]["status"] == "active"
    assert client.get("/me/waitlist", headers=authz(waiting)).json() == []


def test_waitlist_requires_a_full_event(client, db):
    org = make_organizer(client, db)
    event = make_event(client, org, capacity=2)
    waiting = signup(client, email="waiting@example.com")

    response = client.post(f"/events/{event['id']}/waitlist", headers=authz(waiting))
    assert response.status_code == 409
    assert response.json()["detail"] == "seats available"


def test_waitlist_is_unique_per_guest_and_event(client, db):
    org = make_organizer(client, db)
    event = make_event(client, org, capacity=1)
    first = signup(client, email="first@example.com")
    waiting = signup(client, email="waiting@example.com")
    assert client.post(f"/events/{event['id']}/register", headers=authz(first)).status_code == 201
    assert client.post(f"/events/{event['id']}/waitlist", headers=authz(waiting)).status_code == 201

    duplicate = client.post(f"/events/{event['id']}/waitlist", headers=authz(waiting))
    assert duplicate.status_code == 409


def test_capacity_cannot_drop_below_occupied(client, db):
    org = make_organizer(client, db)
    event = make_event(client, org, capacity=5)
    a = signup(client, email="a@example.com")
    client.post(f"/events/{event['id']}/register", headers=authz(a))
    r = client.patch(f"/events/{event['id']}", json={"capacity": 0}, headers=authz(org))
    assert r.status_code in (409, 422)


def test_foreign_event_forbidden(client, db):
    org = make_organizer(client, db, email="o1@example.com")
    org2 = make_organizer(client, db, email="o2@example.com")
    event = make_event(client, org, capacity=5)
    r = client.patch(f"/events/{event['id']}", json={"title": "Hacked"}, headers=authz(org2))
    assert r.status_code == 403
    r = client.post("/check-in", json={"code": "EVT-1-XXXX"}, headers=authz(org2))
    assert r.status_code in (403, 404)
