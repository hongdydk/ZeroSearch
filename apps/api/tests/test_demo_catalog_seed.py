"""Simple two-card demo seed: 제주삼다수 sizes + 레쓰비 flavors, idempotent."""

from __future__ import annotations

import os
import uuid
from unittest.mock import MagicMock

import pytest
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import Session, sessionmaker

from app.deps import hash_password
from app.models import CatalogProduct, Product, User
from app.services.catalog_identity import card_identity_key
from app.services.guest_l1 import TAG_WATER, infer_l1_tags
from app.services.guest_l2 import infer_l2_tags
from seed import (
    SIMPLE_DEMO_CATALOGS,
    _ensure_demo_offer,
    ensure_catalog_seed,
)


def test_simple_demo_is_exactly_two_company_item_cards():
    assert len(SIMPLE_DEMO_CATALOGS) == 2
    titles = {(row["manufacturer"], row["title"]) for row in SIMPLE_DEMO_CATALOGS}
    assert titles == {
        ("제주특별자치도개발공사", "제주삼다수"),
        ("롯데칠성음료", "레쓰비"),
    }
    keys = {
        card_identity_key(row["manufacturer"], row["title"]) for row in SIMPLE_DEMO_CATALOGS
    }
    assert len(keys) == 2


def test_samdasu_demo_keeps_sizes_on_offers_not_cards():
    water = SIMPLE_DEMO_CATALOGS[0]
    assert water["l1_tags"] == [TAG_WATER]
    assert water["l2_tags"] == ["생수"]
    labels = [offer["option_label"] for offer in water["offers"]]
    assert labels == ["500ml", "1L", "2L"]
    assert all("flavor" not in offer for offer in water["offers"])
    for size in ("500ml", "1L", "2L"):
        assert card_identity_key(water["manufacturer"], f"{water['title']}{size}") == (
            card_identity_key(water["manufacturer"], water["title"])
        )


def test_letsbe_demo_keeps_flavors_on_offers_not_cards():
    drink = SIMPLE_DEMO_CATALOGS[1]
    assert drink["l1_tags"] == [TAG_WATER]
    assert drink["l2_tags"] == ["병·캔 커피·차"]
    flavors = [offer["flavor"] for offer in drink["offers"]]
    assert flavors == ["오리지널", "마일드"]
    assert {offer["option_label"] for offer in drink["offers"]} == {"240ml"}
    assert drink["title"] == "레쓰비"
    # 제목에 맛을 붙이면 identity가 갈라지므로 맛은 오퍼 필드만 쓴다.
    assert card_identity_key(drink["manufacturer"], "레쓰비오리지널") != card_identity_key(
        drink["manufacturer"], "레쓰비"
    )


def test_letsbe_category_under_water_l1_is_rtd_can_coffee():
    drink = SIMPLE_DEMO_CATALOGS[1]
    l1 = infer_l1_tags(
        title=drink["title"],
        manufacturer=drink["manufacturer"],
        category=drink["category"],
        category_major=drink["category_major"],
        category_mid=drink["category_mid"],
    )
    # 커피음료는 자동 1차가 커피/원두/차라서 데모가 생수/음료를 직접 심는다.
    assert TAG_WATER not in l1.tags
    l2 = infer_l2_tags(
        title=drink["title"],
        manufacturer=drink["manufacturer"],
        category=drink["category"],
        category_major=drink["category_major"],
        category_mid=drink["category_mid"],
        l1_tags=[TAG_WATER],
    )
    assert l2.tags == ["병·캔 커피·차"]


def test_ensure_demo_offer_skips_when_label_and_flavor_exist():
    db = MagicMock()
    db.scalar.return_value = MagicMock()
    catalog = MagicMock()
    catalog.id = uuid.uuid4()
    seller = MagicMock()
    seller.id = uuid.uuid4()

    _ensure_demo_offer(
        db,
        catalog,
        seller,
        option_label="240ml",
        price_credits=900,
        flavor="마일드",
    )

    db.add.assert_not_called()


def test_ensure_demo_offer_creates_published_size_units():
    db = MagicMock()
    db.scalar.return_value = None
    catalog = MagicMock()
    catalog.id = uuid.uuid4()
    catalog.title = "제주삼다수"
    catalog.description = "제주삼다수 생수"
    catalog.category = "일반생수"
    catalog.image_url = "https://example.com/water.png"
    seller = MagicMock()
    seller.id = uuid.uuid4()

    _ensure_demo_offer(db, catalog, seller, option_label="1L", price_credits=1100, stock=60)

    db.add.assert_called_once()
    product = db.add.call_args.args[0]
    assert isinstance(product, Product)
    assert product.option_label == "1L"
    assert product.volume_ml == 1000
    assert product.unit == "L"
    assert product.unit_amount == 1
    assert product.pack_count == 1
    assert product.flavor is None
    assert product.status == "published"
    assert product.price_credits == 1100
    assert product.stock == 60


def _pg_session() -> tuple[Session, object]:
    database_url = os.environ.get("DATABASE_URL")
    if not database_url or "postgresql" not in database_url:
        pytest.skip("DATABASE_URL(postgresql) 필요")
    engine = create_engine(database_url, pool_pre_ping=True)
    SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    return SessionLocal(), engine


def _demo_catalogs(db: Session) -> list[CatalogProduct]:
    return list(
        db.scalars(
            select(CatalogProduct).where(
                (
                    (CatalogProduct.manufacturer == "제주특별자치도개발공사")
                    & (CatalogProduct.title == "제주삼다수")
                )
                | (
                    (CatalogProduct.manufacturer == "롯데칠성음료")
                    & (CatalogProduct.title == "레쓰비")
                )
            )
        ).all()
    )


def test_pg_simple_demo_seed_is_idempotent_and_keeps_options_on_one_card():
    db, engine = _pg_session()
    try:
        admin = User(
            email=f"demo-seed-{uuid.uuid4().hex[:10]}@test.local",
            password_hash=hash_password("pw"),
            display_name="Admin",
            is_admin=True,
        )
        db.add(admin)
        db.flush()

        ensure_catalog_seed(db)
        ensure_catalog_seed(db)

        catalogs = _demo_catalogs(db)
        by_title = {row.title: row for row in catalogs}
        assert set(by_title) == {"제주삼다수", "레쓰비"}

        water = by_title["제주삼다수"]
        assert water.l1_tags == [TAG_WATER]
        assert water.l2_tags == ["생수"]
        water_offers = list(
            db.scalars(select(Product).where(Product.catalog_product_id == water.id)).all()
        )
        size_labels = {
            offer.option_label
            for offer in water_offers
            if offer.status == "published" and offer.flavor is None
        }
        assert {"500ml", "1L", "2L"} <= size_labels
        assert (
            db.scalar(
                select(func.count())
                .select_from(Product)
                .where(
                    Product.catalog_product_id == water.id,
                    Product.option_label == "500ml",
                    Product.flavor.is_(None),
                )
            )
            == 1
        )

        drink = by_title["레쓰비"]
        assert drink.l1_tags == [TAG_WATER]
        assert drink.l2_tags == ["병·캔 커피·차"]
        drink_offers = list(
            db.scalars(select(Product).where(Product.catalog_product_id == drink.id)).all()
        )
        flavors = {offer.flavor for offer in drink_offers if offer.status == "published"}
        assert {"오리지널", "마일드"} <= flavors
        assert all(offer.option_label == "240ml" for offer in drink_offers if offer.flavor)
        assert (
            db.scalar(
                select(func.count())
                .select_from(Product)
                .where(
                    Product.catalog_product_id == drink.id,
                    Product.flavor == "마일드",
                )
            )
            == 1
        )
        db.rollback()
    finally:
        db.close()
        engine.dispose()
