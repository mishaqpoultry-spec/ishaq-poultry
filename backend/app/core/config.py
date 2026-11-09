from functools import lru_cache

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = "M Ishaq Poultry Services API"
    database_url: str = "postgresql+psycopg://postgres:postgres@localhost:5432/shahzad_poultry"

    jwt_secret: str = "change-me-in-env"
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 60 * 12

    cors_origins: str = "*"

    # Off = supply is unlimited (no stock receiving needed before invoicing).
    enforce_stock: bool = False

    # Business details (used on invoices / PDFs)
    company_name: str = "M Ishaq Poultry Services"
    company_phone: str = "0300-6388084"
    company_address: str = ""

    # Hosting without a shell (Render): if no user exists yet, create this admin at startup.
    admin_username: str = ""
    admin_password: str = ""
    admin_full_name: str = "Owner"

    @field_validator("database_url")
    @classmethod
    def _sqlalchemy_url(cls, v: str) -> str:
        """Accept URLs as Neon/Render give them (postgres:// or postgresql://)."""
        for prefix in ("postgres://", "postgresql://"):
            if v.startswith(prefix):
                return "postgresql+psycopg://" + v[len(prefix):]
        return v


@lru_cache
def get_settings() -> Settings:
    return Settings()
