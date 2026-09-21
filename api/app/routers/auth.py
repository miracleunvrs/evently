from fastapi import APIRouter, Depends, HTTPException, status
from jwt import ExpiredSignatureError, InvalidTokenError
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .. import models, schemas, security
from ..db import get_db
from ..deps import current_user

router = APIRouter(prefix="/auth", tags=["auth"])


def _tokens(user: models.User) -> schemas.TokensOut:
    return schemas.TokensOut(
        access_token=security.make_access(user.id, user.role),
        refresh_token=security.make_refresh(user.id),
        user=schemas.UserOut(id=user.id, name=user.name, email=user.email, role=user.role),
    )


@router.post("/register", response_model=schemas.TokensOut, status_code=201)
def register(body: schemas.RegisterIn, db: Session = Depends(get_db)):
    user = models.User(name=body.name.strip(), email=body.email.lower(), password_hash=security.hash_password(body.password))
    db.add(user)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT, "email taken") from None
    db.refresh(user)
    return _tokens(user)


@router.post("/login", response_model=schemas.TokensOut)
def login(body: schemas.LoginIn, db: Session = Depends(get_db)):
    user = db.query(models.User).filter_by(email=body.email.lower()).first()
    if user is None or not security.verify_password(body.password, user.password_hash):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "bad credentials")
    return _tokens(user)


@router.post("/refresh", response_model=schemas.TokensOut)
def refresh(body: schemas.RefreshIn, db: Session = Depends(get_db)):
    try:
        payload = security.decode(body.refresh_token)
    except ExpiredSignatureError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "refresh expired") from None
    except InvalidTokenError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid refresh") from None
    if payload.get("type") != "refresh":
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "wrong token type")
    user = db.get(models.User, int(payload["sub"]))
    if user is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "unknown user")
    return _tokens(user)


@router.get("/me", response_model=schemas.UserOut)
def me(user: models.User = Depends(current_user)):
    return schemas.UserOut(id=user.id, name=user.name, email=user.email, role=user.role)
