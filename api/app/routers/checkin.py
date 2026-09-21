from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from .. import models, schemas
from ..db import get_db
from ..deps import current_user

router = APIRouter(tags=["check-in"])


@router.post("/check-in")
def check_in(
    body: schemas.CheckInIn,
    db: Session = Depends(get_db),
    user: models.User = Depends(current_user),
):
    code = body.code.strip().upper()
    row = (
        db.query(models.Ticket, models.Registration, models.Event)
        .join(models.Registration, models.Ticket.registration_id == models.Registration.id)
        .join(models.Event, models.Registration.event_id == models.Event.id)
        .filter(models.Ticket.code == code)
        .first()
    )
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "ticket not found")
    ticket, _reg, event = row
    if user.role != "admin" and event.organizer_id != user.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "not your event")
    # Атомарное гашение: только active → used. Повтор пишет duplicate (SPEC.md §10).
    updated = (
        db.query(models.Ticket)
        .filter(models.Ticket.id == ticket.id, models.Ticket.status == "active")
        .update({"status": "used"}, synchronize_session=False)
    )
    result = "ok" if updated else "duplicate"
    db.add(models.CheckIn(ticket_id=ticket.id, event_id=event.id, checked_by=user.id, result=result))
    db.commit()
    if result == "duplicate":
        raise HTTPException(status.HTTP_409_CONFLICT, "already used")
    return {"result": "ok", "event_id": event.id, "event_title": event.title}
