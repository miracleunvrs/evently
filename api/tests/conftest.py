import os

TEST_URL = os.environ.get(
    "DATABASE_URL", "postgresql+psycopg://evently:evently@127.0.0.1:5544/evently_test"
)
os.environ["DATABASE_URL"] = TEST_URL

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.db import Base, get_db
from app.main import app

engine = create_engine(os.environ["DATABASE_URL"])
TestingSession = sessionmaker(bind=engine)


def ensure_test_db() -> None:
    """Создаём тестовую БД, если её нет (устойчивость к чистому тому)."""
    import psycopg
    from sqlalchemy.engine import make_url

    u = make_url(TEST_URL)
    admin = psycopg.connect(
        f"dbname=postgres user={u.username} password={u.password} host={u.host} port={u.port}",
        connect_timeout=5,
        autocommit=True,
    )
    try:
        exists = admin.execute("SELECT 1 FROM pg_database WHERE datname=%s", (u.database,)).fetchone()
        if not exists:
            admin.execute(f'CREATE DATABASE "{u.database}"')
    finally:
        admin.close()


ensure_test_db()


@pytest.fixture()
def db():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    s = TestingSession()
    try:
        yield s
    finally:
        s.close()


@pytest.fixture()
def client(db):
    def override():
        yield db

    app.dependency_overrides[get_db] = override
    with TestClient(app, raise_server_exceptions=True) as c:
        yield c
    app.dependency_overrides.clear()


def signup(client, name="Ann", email="ann@example.com", password="secret1"):
    r = client.post("/auth/register", json={"name": name, "email": email, "password": password})
    assert r.status_code == 201, r.text
    return r.json()


def make_organizer(client, db, email="orga@example.com"):
    signup(client, name="Orga", email=email)
    from app import models

    user = db.query(models.User).filter_by(email=email).first()
    user.role = "organizer"
    db.commit()
    # перевыпускаем токены с ролью organizer
    r = client.post("/auth/login", json={"email": email, "password": "secret1"})
    return r.json()


def authz(tokens):
    return {"Authorization": f"Bearer {tokens['access_token']}"}
