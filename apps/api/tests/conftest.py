"""Shared pytest fixtures — SSOT for API TestClient."""

from __future__ import annotations

from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient

from main import app

# Model factories: tests.factories (make_user, make_bot, override_db, ...)


@pytest.fixture
def client() -> Iterator[TestClient]:
    app.dependency_overrides.clear()
    yield TestClient(app)
    app.dependency_overrides.clear()
