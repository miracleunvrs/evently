import secrets

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .. import models, schemas
from ..db import get_db
from ..deps import admin_only, current_user, organizer_or_admin

router = APIRouter(tags=["events"])

ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


def gen_code(event_id: int) -> str:
    suffix = "".join(secrets.choice(ALPHABET) for _ in range(8))
    return f"EVT-{event_id}-{suffix}"


def issue_ticket(db: Session, registration_id: int, event_id: int) -> models.Ticket:
    """Create one collision-resistant ticket without aborting the outer transaction."""
    for _ in range(5):
        ticket = models.Ticket(registration_id=registration_id, code=gen_code(event_id))
        try:
            with db.begin_nested():
                db.add(ticket)
                db.flush()
            return ticket
        except IntegrityError:
            continue
    raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, "code collision")


def occupied(db: Session, event_id: int) -> int:
    return db.query(models.Registration).filter_by(event_id=event_id, status="confirmed").count()


def to_out(db: Session, e: models.Event) -> schemas.EventOut:
    cat = db.get(models.Category, e.category_id) if e.category_id else None
    return schemas.EventOut(
        id=e.id,
        organizer_id=e.organizer_id,
        title=e.title,
        description=e.description,
        city=e.city,
        place=e.place,
        starts_at=e.starts_at,
        category=cat.title if cat else None,
        capacity=e.capacity,
        occupied=occupied(db, e.id),
        price=e.price,
        status=e.status,
        cover_url=e.cover_url,
    )


def visible_query(db: Session, user: models.User | None):
    q = db.query(models.Event)
    if user is None or user.role == "visitor":
        return q.filter(models.Event.status == "published")
    if user.role == "organizer":
        return q.filter((models.Event.status == "published") | (models.Event.organizer_id == user.id))
    return q


@router.get("/events", response_model=list[schemas.EventOut])
def list_events(
    q: str = Query(default=""),
    category: str = Query(default=""),
    city: str = Query(default=""),
    db: Session = Depends(get_db),
):
    # Публичный каталог — только published (SPEC.md §10, правило 5).
    query = db.query(models.Event).filter(models.Event.status == "published")
    if q:
        like = f"%{q}%"
        query = query.filter(
            (models.Event.title.ilike(like)) | (models.Event.city.ilike(like)) | (models.Event.place.ilike(like))
        )
    if city:
        query = query.filter(models.Event.city.ilike(f"%{city}%"))
    if category:
        cat = db.query(models.Category).filter_by(title=category).first()
        if cat is None:
            return []
        query = query.filter(models.Event.category_id == cat.id)
    return [to_out(db, e) for e in query.order_by(models.Event.id.desc()).limit(100).all()]


@router.get("/events/{event_id}", response_model=schemas.EventOut)
def get_event(event_id: int, db: Session = Depends(get_db)):
    e = db.get(models.Event, event_id)
    if e is None or e.status != "published":
        raise HTTPException(status.HTTP_404_NOT_FOUND, "event not found")
    return to_out(db, e)


@router.post("/events", response_model=schemas.EventOut, status_code=201)
def create_event(
    body: schemas.EventIn,
    db: Session = Depends(get_db),
    user: models.User = Depends(organizer_or_admin),
):
    if body.status not in ("draft", "published", "hidden"):
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "bad status")
    e = models.Event(organizer_id=user.id, **body.model_dump())
    db.add(e)
    db.commit()
    db.refresh(e)
    return to_out(db, e)


@router.patch("/events/{event_id}", response_model=schemas.EventOut)
def patch_event(
    event_id: int,
    body: schemas.EventPatch,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    e = db.get(models.Event, event_id)
    if e is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "event not found")
    if user.role != "admin" and e.organizer_id != user.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "not your event")
    data = body.model_dump(exclude_unset=True)
    if "status" in data and data["status"] not in ("draft", "published", "hidden"):
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "bad status")
    if "capacity" in data and data["capacity"] < occupied(db, event_id):
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "capacity below occupied")
    for k, v in data.items():
        setattr(e, k, v)
    db.commit()
    db.refresh(e)
    return to_out(db, e)


@router.post("/events/{event_id}/register", response_model=schemas.TicketOut, status_code=201)
def register(
    event_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    # Блокируем строку события: capacity проверяем атомарно (SPEC.md §10, правило 1).
    e = db.query(models.Event).filter_by(id=event_id).with_for_update().first()
    if e is None or e.status != "published":
        raise HTTPException(status.HTTP_404_NOT_FOUND, "event not found")
    if occupied(db, event_id) >= e.capacity:
        raise HTTPException(status.HTTP_409_CONFLICT, "sold out")
    reg = models.Registration(event_id=event_id, user_id=user.id)
    db.add(reg)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT, "already registered") from None
    ticket = issue_ticket(db, reg.id, event_id)
    db.commit()
    return schemas.TicketOut(code=ticket.code, status=ticket.status, event_id=e.id, event_title=e.title, registration_id=reg.id)


@router.post("/events/{event_id}/waitlist", response_model=schemas.WaitlistOut, status_code=201)
def join_waitlist(
    event_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    """Join a FIFO waitlist only when every seat is occupied."""
    event = db.query(models.Event).filter_by(id=event_id).with_for_update().first()
    if event is None or event.status != "published":
        raise HTTPException(status.HTTP_404_NOT_FOUND, "event not found")
    existing = db.query(models.Registration).filter_by(event_id=event_id, user_id=user.id).first()
    if existing is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "already registered or waitlisted")
    if occupied(db, event_id) < event.capacity:
        raise HTTPException(status.HTTP_409_CONFLICT, "seats available")
    reg = models.Registration(event_id=event_id, user_id=user.id, status="waitlisted")
    db.add(reg)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT, "already registered or waitlisted") from None
    position = (
        db.query(models.Registration)
        .filter_by(event_id=event_id, status="waitlisted")
        .filter(models.Registration.id <= reg.id)
        .count()
    )
    db.commit()
    return schemas.WaitlistOut(
        registration_id=reg.id,
        event_id=event.id,
        event_title=event.title,
        position=position,
    )


@router.delete("/registrations/{reg_id}", status_code=204)
def cancel_registration(
    reg_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    reg = db.get(models.Registration, reg_id)
    if reg is None or (reg.user_id != user.id and user.role != "admin"):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "registration not found")
    event = db.query(models.Event).filter_by(id=reg.event_id).with_for_update().first()
    ticket = db.query(models.Ticket).filter_by(registration_id=reg.id).first()
    # Использованный билет отменить нельзя (SPEC.md §10, правило 2).
    if ticket is not None and ticket.status == "used":
        raise HTTPException(status.HTTP_409_CONFLICT, "ticket already used")
    seat_released = reg.status == "confirmed"
    if ticket is not None:
        db.delete(ticket)
        db.flush()
    db.delete(reg)
    db.flush()
    if seat_released and event is not None:
        next_reg = (
            db.query(models.Registration)
            .filter_by(event_id=event.id, status="waitlisted")
            .order_by(models.Registration.created_at.asc(), models.Registration.id.asc())
            .with_for_update()
            .first()
        )
        if next_reg is not None:
            next_reg.status = "confirmed"
            db.flush()
            issue_ticket(db, next_reg.id, event.id)
    db.commit()


@router.get("/me/tickets", response_model=list[schemas.TicketOut])
def my_tickets(db: Session = Depends(get_db), user: models.User = Depends(current_user)):
    rows = (
        db.query(models.Ticket, models.Registration, models.Event)
        .join(models.Registration, models.Ticket.registration_id == models.Registration.id)
        .join(models.Event, models.Registration.event_id == models.Event.id)
        .filter(models.Registration.user_id == user.id)
        .all()
    )
    return [
        schemas.TicketOut(code=t.code, status=t.status, event_id=e.id, event_title=e.title, registration_id=r.id)
        for t, r, e in rows
    ]


@router.get("/me/waitlist", response_model=list[schemas.WaitlistOut])
def my_waitlist(db: Session = Depends(get_db), user: models.User = Depends(current_user)):
    rows = (
        db.query(models.Registration, models.Event)
        .join(models.Event, models.Registration.event_id == models.Event.id)
        .filter(models.Registration.user_id == user.id, models.Registration.status == "waitlisted")
        .order_by(models.Registration.created_at.asc(), models.Registration.id.asc())
        .all()
    )
    result = []
    for reg, event in rows:
        position = (
            db.query(models.Registration)
            .filter_by(event_id=event.id, status="waitlisted")
            .filter(models.Registration.id <= reg.id)
            .count()
        )
        result.append(
            schemas.WaitlistOut(
                registration_id=reg.id,
                event_id=event.id,
                event_title=event.title,
                position=position,
            )
        )
    return result


@router.get("/me/favorites", response_model=list[int])
def my_favorites(db: Session = Depends(get_db), user: models.User = Depends(current_user)):
    return [f.event_id for f in db.query(models.Favorite).filter_by(user_id=user.id).all()]


@router.post("/me/favorites", status_code=201)
def add_favorite(
    body: schemas.FavoriteIn,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    db.add(models.Favorite(user_id=user.id, event_id=body.event_id))
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
    return {"ok": True}


@router.delete("/me/favorites/{event_id}", status_code=204)
def remove_favorite(
    event_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    db.query(models.Favorite).filter_by(user_id=user.id, event_id=event_id).delete()
    db.commit()


@router.get("/events/{event_id}/guests")
def guests(
    event_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    e = db.get(models.Event, event_id)
    if e is None or (user.role != "admin" and e.organizer_id != user.id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "event not found")
    rows = (
        db.query(models.Registration, models.User)
        .join(models.User, models.Registration.user_id == models.User.id)
        .filter(models.Registration.event_id == event_id)
        .all()
    )
    return [
        {"name": u.name, "email": u.email, "status": r.status, "registered_at": r.created_at} for r, u in rows
    ]


@router.get("/events/{event_id}/stats")
def stats(
    event_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    e = db.get(models.Event, event_id)
    if e is None or (user.role != "admin" and e.organizer_id != user.id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "event not found")
    regs = occupied(db, event_id)
    visits = (
        db.query(models.Ticket)
        .join(models.Registration, models.Ticket.registration_id == models.Registration.id)
        .filter(models.Registration.event_id == event_id, models.Ticket.status == "used")
        .count()
    )
    return {"registrations": regs, "visits": visits, "capacity": e.capacity}


@router.get("/categories")
def categories(db: Session = Depends(get_db)):
    return [{"id": c.id, "slug": c.slug, "title": c.title} for c in db.query(models.Category).all()]


@router.get("/admin/overview")
def overview(db: Session = Depends(get_db), user: models.User = Depends(admin_only)):
    return {
        "events": db.query(models.Event).count(),
        "users": db.query(models.User).count(),
        "registrations": db.query(models.Registration).count(),
        "visits": db.query(models.Ticket).filter_by(status="used").count(),
    }
