"""Test model factories and dependency override helpers (pytest SSOT)."""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import UTC, datetime
from unittest.mock import MagicMock

from app.deps import get_current_user, get_db, get_optional_current_user
from app.models import User
from main import app


def make_user(
    *,
    user_id: uuid.UUID | None = None,
    email: str = "user@test.local",
    display_name: str = "Test",
    is_admin: bool = False,
    password_hash: str = "hash",
) -> User:
    user = MagicMock(spec=User)
    user.id = user_id or uuid.uuid4()
    user.email = email
    user.display_name = display_name
    user.is_admin = is_admin
    user.created_at = datetime.now(UTC)
    user.password_hash = password_hash
    return user


def override_db(mock_db: MagicMock) -> None:
    def _override() -> Iterator[MagicMock]:
        yield mock_db

    app.dependency_overrides[get_db] = _override


def override_current_user(user: User) -> None:
    app.dependency_overrides[get_current_user] = lambda: user


def override_optional_user(user: User | None) -> None:
    app.dependency_overrides[get_optional_current_user] = lambda: user
