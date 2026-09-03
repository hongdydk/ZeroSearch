import re
from datetime import datetime
from typing import Annotated, Literal

from email_validator import EmailNotValidError, validate_email
from pydantic import AfterValidator, BaseModel, Field

_LOCAL_EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.local$", re.IGNORECASE)


def normalize_email(value: str) -> str:
    value = value.strip().lower()
    if _LOCAL_EMAIL.match(value):
        return value
    try:
        return validate_email(value, check_deliverability=False).normalized
    except EmailNotValidError as exc:
        raise ValueError("유효한 이메일 형식이 아닙니다.") from exc


DevEmail = Annotated[str, AfterValidator(normalize_email)]


class RegisterRequest(BaseModel):
    email: DevEmail
    password: str = Field(min_length=6, max_length=128)
    display_name: str | None = Field(default=None, alias="displayName", max_length=100)

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class LoginRequest(BaseModel):
    email: DevEmail
    password: str
    portal: Literal["buyer", "seller", "admin"] = "buyer"


class TokenResponse(BaseModel):
    access_token: str = Field(alias="accessToken")
    token_type: str = Field(default="bearer", alias="tokenType")

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class UserResponse(BaseModel):
    id: str
    email: str
    display_name: str | None = Field(default=None, alias="displayName")
    is_admin: bool = Field(default=False, alias="isAdmin")
    created_at: datetime | None = Field(default=None, alias="createdAt")

    model_config = {"populate_by_name": True, "from_attributes": True, "ser_json_by_alias": True}
