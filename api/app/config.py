from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = "postgresql+psycopg://evently:evently@127.0.0.1:5544/evently"
    jwt_secret: str = "dev-secret-change-me"
    access_ttl_min: int = 30
    refresh_ttl_days: int = 7
    cors_origins: str = "http://127.0.0.1:5173,http://localhost:5173"


settings = Settings()
