"""JWT (access/refresh) + bcrypt. Токены хранит клиент в localStorage (решение по грилю)."""
from datetime import datetime, timedelta, timezone

import bcrypt
import jwt

from .config import settings

ALGO = "HS256"


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode(), password_hash.encode())
    except ValueError:
        return False


def _encode(payload: dict) -> str:
    return jwt.encode(payload, settings.jwt_secret, algorithm=ALGO)


def make_access(user_id: int, role: str) -> str:
    exp = datetime.now(timezone.utc) + timedelta(minutes=settings.access_ttl_min)
    return _encode({"sub": str(user_id), "role": role, "type": "access", "exp": exp})


def make_refresh(user_id: int) -> str:
    exp = datetime.now(timezone.utc) + timedelta(days=settings.refresh_ttl_days)
    return _encode({"sub": str(user_id), "type": "refresh", "exp": exp})


def decode(token: str) -> dict:
    return jwt.decode(token, settings.jwt_secret, algorithms=[ALGO])
