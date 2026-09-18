"""Guest L1 browse: brand/menu lists stay inside the selected 1차 tag."""

from __future__ import annotations

import os
import uuid
from datetime import UTC, datetime

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.models import CatalogProduct
from app.services.catalog_l1 import apply_auto_l1_tags, list_l1_facets
from app.services.catalog_products import list_catalog_products
from app.services.guest_l1 import TAG_WATER


def _catalog(**kwargs) -> CatalogProduct:
    catalog = CatalogProduct(
        id=uuid.uuid4(),
        title="샘플",
        manufacturer="그린에이드",
        category=f"cat-{uuid.uuid4().hex[:8]}",
        volume_options=[],
        reference_variants=[],
        l1_tags=[],
        price_unit="ml",
    )
    catalog.created_at = datetime.now(UTC)
    for key, value in kwargs.items():
        setattr(catalog, key, value)
    return catalog


def test_force_retag_clears_false_water_tag_on_greenaid_housewares():
    catalog = _catalog(title="커피필터", l1_tags=[TAG_WATER])
    assert apply_auto_l1_tags(catalog, only_if_empty=True) is False
    assert TAG_WATER in catalog.l1_tags
    assert apply_auto_l1_tags(catalog, only_if_empty=False) is True
    assert TAG_WATER not in (catalog.l1_tags or [])


def _pg_session() -> tuple[Session, object]:
    database_url = os.environ.get("DATABASE_URL")
    if not database_url or "postgresql" not in database_url:
        pytest.skip("DATABASE_URL(postgresql) 필요")
    engine = create_engine(database_url, pool_pre_ping=True)
    session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    return session_factory(), engine


def test_pg_l1_brand_returns_only_tagged_cards_not_housewares():
    db, engine = _pg_session()
    try:
        stamp = uuid.uuid4().hex[:8]
        drink = _catalog(
            title=f"레몬에이드-{stamp}",
            l1_tags=[TAG_WATER],
            category="에이드음료",
        )
        housewares = [
            _catalog(title=f"커피필터-{stamp}", l1_tags=[], category="필터"),
            _catalog(title=f"실리콘 퍼프-{stamp}", l1_tags=[], category="퍼프"),
            _catalog(title=f"국물팩-{stamp}", l1_tags=[], category="국물팩"),
            _catalog(title=f"캔들-{stamp}", l1_tags=[], category="캔들"),
            _catalog(title=f"쓰레기통-{stamp}", l1_tags=[], category="휴지통"),
        ]
        db.add_all([drink, *housewares])
        db.flush()
        house_ids = {str(row.id) for row in housewares}
        drink_id = str(drink.id)

        scoped = list_catalog_products(db, l1_tag=TAG_WATER, brand="그린에이드")
        scoped_ids = {item.id for item in scoped.items}
        assert drink_id in scoped_ids
        assert scoped_ids.isdisjoint(house_ids)

        truncated = list_catalog_products(db, l1_tag="생수", brand="그린에이드")
        assert truncated.items == []
        assert truncated.total == 0

        facets = list_l1_facets(db, l1_tag=TAG_WATER)
        assert "그린에이드" in [row["name"] for row in facets["brands"]]
        menu_names = [row["name"] for row in facets["menus"]]
        assert drink.title in menu_names
        assert housewares[0].title not in menu_names
    finally:
        db.rollback()
        db.close()
        engine.dispose()


def test_pg_l1_facets_omit_brand_with_no_tagged_cards():
    db, engine = _pg_session()
    try:
        brand = f"하우스브랜드-{uuid.uuid4().hex[:8]}"
        menu = f"커피필터-{uuid.uuid4().hex[:8]}"
        db.add(_catalog(title=menu, manufacturer=brand, l1_tags=[], category="필터"))
        db.flush()

        facets = list_l1_facets(db, l1_tag=TAG_WATER)
        assert brand not in [row["name"] for row in facets["brands"]]
        assert menu not in [row["name"] for row in facets["menus"]]

        empty = list_catalog_products(db, l1_tag=TAG_WATER, brand=brand)
        assert empty.items == []
        assert empty.total == 0

        menu_empty = list_catalog_products(db, l1_tag=TAG_WATER, menu=menu)
        assert menu_empty.items == []
        assert menu_empty.total == 0
    finally:
        db.rollback()
        db.close()
        engine.dispose()
