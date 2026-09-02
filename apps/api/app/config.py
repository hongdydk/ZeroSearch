from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    database_url: str = "postgresql+psycopg://mall:mall@localhost:5434/mall"
    jwt_secret: str = "dev-secret-change-in-production"
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60 * 24 * 7
    admin_email: str | None = None
    admin_password: str | None = None
    allow_db_reset: bool = False
    cors_origins: str = (
        "http://localhost:8080,"
        "http://127.0.0.1:8080"
    )
    signup_credit_bonus: int = 100
    log_level: str = "INFO"
    log_format: str = "text"
    log_file: str | None = None


@lru_cache
def get_settings() -> Settings:
    return Settings()
