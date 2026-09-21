"""Модели — 1:1 со схемой SPEC.md §6 и db/schema.ts (D1)."""
from sqlalchemy import (
    Column,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
    func,
)

from .db import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True)
    email = Column(String(255), nullable=False, unique=True, index=True)
    name = Column(String(255), nullable=False, default="")
    role = Column(String(16), nullable=False, default="visitor", index=True)
    password_hash = Column(String(255), nullable=False, default="")
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())


class Category(Base):
    __tablename__ = "categories"

    id = Column(Integer, primary_key=True)
    slug = Column(String(64), nullable=False, unique=True)
    title = Column(String(128), nullable=False, unique=True)


class Event(Base):
    __tablename__ = "events"

    id = Column(Integer, primary_key=True)
    organizer_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    category_id = Column(Integer, ForeignKey("categories.id"), nullable=True, index=True)
    title = Column(String(255), nullable=False)
    description = Column(String(2000), nullable=False, default="")
    city = Column(String(128), nullable=False, default="")
    place = Column(String(255), nullable=False, default="")
    starts_at = Column(String(64), nullable=False, default="")
    capacity = Column(Integer, nullable=False, default=100)
    price = Column(Integer, nullable=False, default=0)
    status = Column(String(16), nullable=False, default="published", index=True)
    # Токен шаблона (gen:...), путь или dataURL своей обложки (S3 — позже).
    cover_url = Column(String(), nullable=False, default="")
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())


class EventImage(Base):
    __tablename__ = "event_images"

    id = Column(Integer, primary_key=True)
    event_id = Column(Integer, ForeignKey("events.id"), nullable=False, index=True)
    url = Column(String(512), nullable=False)
    sort = Column(Integer, nullable=False, default=0)


class Registration(Base):
    __tablename__ = "registrations"
    __table_args__ = (UniqueConstraint("event_id", "user_id", name="registrations_event_user_unique"),)

    id = Column(Integer, primary_key=True)
    event_id = Column(Integer, ForeignKey("events.id"), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    status = Column(String(16), nullable=False, default="confirmed")
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())


Index("registrations_event_status_created_idx", Registration.event_id, Registration.status, Registration.created_at)


class Ticket(Base):
    __tablename__ = "tickets"

    id = Column(Integer, primary_key=True)
    registration_id = Column(Integer, ForeignKey("registrations.id"), nullable=False, unique=True)
    code = Column(String(32), nullable=False, unique=True, index=True)
    status = Column(String(16), nullable=False, default="active", index=True)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())


class Favorite(Base):
    __tablename__ = "favorites"
    __table_args__ = (UniqueConstraint("user_id", "event_id", name="favorites_user_event_unique"),)

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    event_id = Column(Integer, ForeignKey("events.id"), nullable=False, index=True)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())


class CheckIn(Base):
    __tablename__ = "check_ins"

    id = Column(Integer, primary_key=True)
    ticket_id = Column(Integer, ForeignKey("tickets.id"), nullable=False, index=True)
    event_id = Column(Integer, ForeignKey("events.id"), nullable=False, index=True)
    checked_by = Column(Integer, ForeignKey("users.id"), nullable=True)
    result = Column(String(16), nullable=False, default="ok")
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())


Index("events_status_idx", Event.status)
