"""공식 판매자 기동 시드가 이미 있는 행에서 UniqueViolation으로 죽지 않는지."""

from __future__ import annotations

import os
import uuid
from unittest.mock import MagicMock

import pytest
from sqlalchemy import create_engine, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from app.deps import hash_password
from app.models import Seller, User
from app.services.sellers import (
    PLATFORM_SHOP_NAME,
    PLATFORM_SLUG,
    ensure_platform_seller,
)
from seed import ensure_catalog_seed
from tests.factories import make_user


def _merchant_for(admin: User, **kwargs) -> Seller:
    seller = Seller(
        id=uuid.uuid4(),
        user_id=admin.id,
        shop_name="기존 가게",
        slug="existing-shop",
        status="active",
        seller_type="merchant",
    )
    for key, value in kwargs.items():
        setattr(seller, key, value)
    return seller


def test_ensure_platform_seller_adopts_existing_user_row_and_is_idempotent():
    admin = make_user(is_admin=True)
    existing = _merchant_for(admin)
    db = MagicMock()
    db.scalar.side_effect = [existing, None]

    first = ensure_platform_seller(db, admin)

    assert first is existing
    db.add.assert_not_called()
    assert existing.seller_type == "platform"
    assert existing.slug == PLATFORM_SLUG
    assert existing.shop_name == PLATFORM_SHOP_NAME
    assert existing.status == "active"

    db.scalar.side_effect = [existing]
    db.add.reset_mock()
    second = ensure_platform_seller(db, admin)
    assert second is existing
    db.add.assert_not_called()


def test_ensure_platform_seller_adopts_official_slug_row():
    admin = make_user(is_admin=True)
    existing = _merchant_for(admin, slug=PLATFORM_SLUG, shop_name=PLATFORM_SHOP_NAME)
    db = MagicMock()
    db.scalar.return_value = existing

    result = ensure_platform_seller(db, admin)

    assert result is existing
    db.add.assert_not_called()
    assert existing.seller_type == "platform"


def test_ensure_platform_seller_recovers_from_unique_violation_on_insert():
    admin = make_user(is_admin=True)
    existing = _merchant_for(admin)
    db = MagicMock()
    nested = MagicMock()
    nested.__enter__.return_value = nested
    nested.__exit__.return_value = False
    db.begin_nested.return_value = nested

    lookups = iter([None, existing, None])
    db.scalar.side_effect = lambda _stmt: next(lookups, None)

    flush_count = {"n": 0}

    def flush():
        flush_count["n"] += 1
        if flush_count["n"] == 1:
            raise IntegrityError("INSERT INTO sellers", {}, Exception("duplicate"))

    db.flush.side_effect = flush

    result = ensure_platform_seller(db, admin)

    assert result is existing
    assert existing.seller_type == "platform"
    assert existing.slug == PLATFORM_SLUG
    db.add.assert_called_once()


def _pg_session() -> tuple[Session, object]:
    database_url = os.environ.get("DATABASE_URL")
    if not database_url or "postgresql" not in database_url:
        pytest.skip("DATABASE_URL(postgresql) 필요")
    engine = create_engine(database_url, pool_pre_ping=True)
    SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    return SessionLocal(), engine


def test_pg_ensure_platform_seller_when_user_already_has_seller():
    db, engine = _pg_session()
    try:
        # 동시성 테스트가 커밋한 platform 행이 여러 개여도 재호출이 같은 행을 고른다.
        for _ in range(2):
            other = User(
                email=f"plat-left-{uuid.uuid4().hex[:10]}@test.local",
                password_hash=hash_password("pw"),
                display_name="Other",
            )
            db.add(other)
            db.flush()
            db.add(
                Seller(
                    user_id=other.id,
                    shop_name=f"leftover-{uuid.uuid4().hex[:6]}",
                    slug=f"leftover-{uuid.uuid4().hex[:8]}",
                    status="active",
                    seller_type="platform",
                )
            )
            db.flush()

        admin = User(
            email=f"official-seed-{uuid.uuid4().hex[:10]}@test.local",
            password_hash=hash_password("pw"),
            display_name="Admin",
            is_admin=True,
        )
        db.add(admin)
        db.flush()
        seeded = Seller(
            user_id=admin.id,
            shop_name="기존 가게",
            slug=f"existing-{uuid.uuid4().hex[:8]}",
            status="active",
            seller_type="merchant",
        )
        db.add(seeded)
        db.flush()

        first = ensure_platform_seller(db, admin)
        second = ensure_platform_seller(db, admin)

        assert first.id == second.id
        seller_count = db.scalar(select(func.count()).select_from(Seller).where(Seller.user_id == admin.id))
        assert seller_count == 1
        db.rollback()
    finally:
        db.close()
        engine.dispose()


def test_pg_ensure_catalog_seed_rerun_does_not_raise():
    db, engine = _pg_session()
    try:
        admin = User(
            email=f"catalog-seed-{uuid.uuid4().hex[:10]}@test.local",
            password_hash=hash_password("pw"),
            display_name="Admin",
            is_admin=True,
        )
        db.add(admin)
        db.flush()
        db.add(
            Seller(
                user_id=admin.id,
                shop_name="기존 가게",
                slug=f"existing-{uuid.uuid4().hex[:8]}",
                status="active",
                seller_type="merchant",
            )
        )
        db.flush()

        ensure_catalog_seed(db)
        ensure_catalog_seed(db)

        seller_count = db.scalar(select(func.count()).select_from(Seller).where(Seller.user_id == admin.id))
        assert seller_count == 1
        db.rollback()
    finally:
        db.close()
        engine.dispose()
