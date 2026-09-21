from datetime import datetime, timedelta, timezone

import jwt

from .conftest import authz, signup


def test_register_login_me(client):
    tokens = signup(client)
    r = client.get("/auth/me", headers=authz(tokens))
    assert r.status_code == 200
    assert r.json()["email"] == "ann@example.com"


def test_register_duplicate_email(client):
    signup(client)
    r = client.post("/auth/register", json={"name": "Ann2", "email": "ann@example.com", "password": "secret1"})
    assert r.status_code == 409


def test_login_bad_password(client):
    signup(client)
    r = client.post("/auth/login", json={"email": "ann@example.com", "password": "wrongpass"})
    assert r.status_code == 401


def test_refresh_flow(client):
    tokens = signup(client)
    r = client.post("/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert r.status_code == 200
    me = client.get("/auth/me", headers={"Authorization": f"Bearer {r.json()['access_token']}"})
    assert me.status_code == 200


def test_expired_access_rejected(client):
    payload = {"sub": "1", "role": "visitor", "type": "access",
               "exp": datetime.now(timezone.utc) - timedelta(minutes=1)}
    token = jwt.encode(payload, "dev-secret-change-me", algorithm="HS256")
    r = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 401


def test_no_token_rejected(client):
    assert client.get("/auth/me").status_code == 401
