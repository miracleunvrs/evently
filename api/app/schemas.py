from pydantic import BaseModel, EmailStr, Field


class RegisterIn(BaseModel):
    name: str = Field(min_length=2, max_length=255)
    email: EmailStr
    password: str = Field(min_length=6, max_length=128)


class LoginIn(BaseModel):
    email: EmailStr
    password: str


class RefreshIn(BaseModel):
    refresh_token: str


class UserOut(BaseModel):
    id: int
    name: str
    email: str
    role: str


class TokensOut(BaseModel):
    access_token: str
    refresh_token: str
    user: UserOut


class EventIn(BaseModel):
    title: str = Field(min_length=1, max_length=255)
    description: str = ""
    city: str = ""
    place: str = ""
    starts_at: str = ""
    category_id: int | None = None
    capacity: int = Field(default=100, ge=1, le=5000)
    price: int = Field(default=0, ge=0)
    cover_url: str = ""
    status: str = "published"


class EventPatch(BaseModel):
    title: str | None = None
    description: str | None = None
    city: str | None = None
    place: str | None = None
    starts_at: str | None = None
    category_id: int | None = None
    capacity: int | None = Field(default=None, ge=1, le=5000)
    price: int | None = Field(default=None, ge=0)
    cover_url: str | None = None
    status: str | None = None


class EventOut(BaseModel):
    id: int
    organizer_id: int
    title: str
    description: str
    city: str
    place: str
    starts_at: str
    category: str | None = None
    capacity: int
    occupied: int
    price: int
    status: str
    cover_url: str = ""


class TicketOut(BaseModel):
    code: str
    status: str
    event_id: int
    event_title: str
    registration_id: int


class WaitlistOut(BaseModel):
    registration_id: int
    event_id: int
    event_title: str
    status: str = "waitlisted"
    position: int


class CheckInIn(BaseModel):
    code: str


class FavoriteIn(BaseModel):
    event_id: int
