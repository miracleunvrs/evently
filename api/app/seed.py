"""Seed: категории + демо-организатор + 4 демо-события. Запуск: python -m app.seed"""
from datetime import datetime, timedelta, timezone

from . import models, security
from .db import Base, SessionLocal, engine

CATEGORIES = [
    ("design", "Дизайн"),
    ("tech", "Технологии"),
    ("networking", "Нетворкинг"),
    ("music", "Музыка"),
    ("science", "Наука"),
]

EVENTS = [
    # title, category_slug, city, place, day_offset, time, capacity
    ("Future of Work / Almaty", "tech", "Алматы", "Terrenkur Hall", 5, "18:30", 240),
    ("After Hours: Product People", "networking", "Астана", "Rooftop 18", 8, "20:00", 90),
    ("Design Systems Picnic", "design", "Алматы", "Ботанический сад", 15, "12:00", 320),
    ("Зимний Jazz / Almaty", "music", "Алматы", "Rooftop 18", -6, "19:00", 120),
]


def main() -> None:
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        for slug, title in CATEGORIES:
            if db.query(models.Category).filter_by(slug=slug).first() is None:
                db.add(models.Category(slug=slug, title=title))
        db.flush()
        orga = db.query(models.User).filter_by(email="orga@example.com").first()
        if orga is None:
            orga = models.User(
                name="Органайзер",
                email="orga@example.com",
                role="organizer",
                password_hash=security.hash_password("orga123"),
            )
            db.add(orga)
            db.flush()
        for title, slug, city, place, offset, time, capacity in EVENTS:
            if db.query(models.Event).filter_by(title=title).first() is None:
                cat = db.query(models.Category).filter_by(slug=slug).first()
                day = datetime.now(timezone.utc) + timedelta(days=offset)
                db.add(
                    models.Event(
                        organizer_id=orga.id,
                        category_id=cat.id if cat else None,
                        title=title,
                        description="Демо-событие Evently.",
                        city=city,
                        place=place,
                        starts_at=day.strftime(f"%Y-%m-%dT{time}:00"),
                        capacity=capacity,
                    )
                )
        db.commit()
    finally:
        db.close()
    print("seed ok")


if __name__ == "__main__":
    main()
