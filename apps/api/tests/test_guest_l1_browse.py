"""Guest L1 browse: brand/menu lists stay inside the selected 1차 tag."""

from __future__ import annotations

import os
import uuid
from datetime import UTC, datetime

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.models import CatalogProduct, Product, Seller, User
from app.services.catalog_l1 import apply_auto_l1_tags, list_l1_facets
from app.services.catalog_products import list_catalog_offers, list_catalog_products
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

        drink.l2_tags = ["기타음료"]
        db.flush()
        l2_scoped = list_catalog_products(db, l1_tag=TAG_WATER, l2_tag="기타음료", brand="그린에이드")
        assert str(drink.id) in {item.id for item in l2_scoped.items}
        empty_l2 = list_catalog_products(db, l1_tag=TAG_WATER, l2_tag="생수", brand="그린에이드")
        assert empty_l2.items == []
        wrong_l2 = list_catalog_products(db, l1_tag=TAG_WATER, l2_tag="봉지라면")
        assert wrong_l2.items == []
    finally:
        db.rollback()
        db.close()
        engine.dispose()


def test_pg_l2_saengsu_excludes_juice_coffee_and_keeps_water():
    db, engine = _pg_session()
    try:
        stamp = uuid.uuid4().hex[:8]
        water = _catalog(
            title=f"제주삼다수-{stamp}",
            manufacturer=f"삼다수브랜드-{stamp}",
            category="일반생수",
            category_major="음료",
            category_mid="생수",
        )
        juice = _catalog(
            title=f"델몬트수박주스-{stamp}",
            manufacturer=f"주스브랜드-{stamp}",
            category="일반생수",
            category_major="음료",
            category_mid="생수",
        )
        coffee = _catalog(
            title=f"칸타타아이스블랙커피-{stamp}",
            manufacturer=f"커피브랜드-{stamp}",
            category="일반생수",
            category_major="음료",
            category_mid="생수",
        )
        cheese = _catalog(
            title=f"서울우유체다치즈-{stamp}",
            manufacturer="서울우유",
            category="체다치즈",
            category_major="유제품",
            category_mid="치즈",
        )
        db.add_all([water, juice, coffee, cheese])
        db.flush()
        for row in (water, juice, coffee, cheese):
            apply_auto_l1_tags(row, only_if_empty=False)
        db.flush()

        assert "생수" in (water.l2_tags or [])
        assert "생수" not in (juice.l2_tags or [])
        assert "생수" not in (coffee.l2_tags or [])
        assert "우유" not in (cheese.l2_tags or [])
        assert "요거트·치즈·버터" in (cheese.l2_tags or [])

        scoped = list_catalog_products(db, l1_tag=TAG_WATER, l2_tag="생수")
        ids = {item.id for item in scoped.items}
        assert str(water.id) in ids
        assert str(juice.id) not in ids
        assert str(coffee.id) not in ids

        facets = list_l1_facets(db, l1_tag=TAG_WATER, l2_tag="생수")
        brands = [row["name"] for row in facets["brands"]]
        assert water.manufacturer in brands
        assert juice.manufacturer not in brands
        assert coffee.manufacturer not in brands

        dairy = list_catalog_products(db, l1_tag="유제품/아이스크림", l2_tag="우유")
        assert str(cheese.id) not in {item.id for item in dairy.items}
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


def _pg_user_seller(db: Session, *, shop_name: str, seller_type: str = "merchant") -> Seller:
    user = User(
        id=uuid.uuid4(),
        email=f"offer-axis-{uuid.uuid4().hex[:10]}@example.com",
        password_hash="x",
        display_name=shop_name,
    )
    db.add(user)
    db.flush()
    seller = Seller(
        id=uuid.uuid4(),
        user_id=user.id,
        shop_name=shop_name,
        slug=f"offer-axis-{uuid.uuid4().hex[:10]}",
        status="active",
        seller_type=seller_type,
    )
    db.add(seller)
    db.flush()
    return seller


def _pg_offer(catalog: CatalogProduct, seller: Seller, *, price_credits: int) -> Product:
    offer = Product(
        id=uuid.uuid4(),
        seller_id=seller.id,
        catalog_product_id=catalog.id,
        title=catalog.title,
        price_credits=price_credits,
        stock=8,
        category=catalog.category,
        status="published",
    )
    offer.created_at = datetime.now(UTC)
    return offer


def test_pg_seller_axis_lists_one_card_per_offer_and_stays_l1_scoped():
    db, engine = _pg_session()
    try:
        stamp = uuid.uuid4().hex[:8]
        drink = _catalog(
            title=f"레몬에이드-{stamp}",
            l1_tags=[TAG_WATER],
            category="에이드음료",
        )
        housewares = _catalog(title=f"커피필터-{stamp}", l1_tags=[], category="필터")
        official = _pg_user_seller(db, shop_name=f"공식-{stamp}", seller_type="platform")
        mart = _pg_user_seller(db, shop_name=f"청정마트-{stamp}")
        house_seller = _pg_user_seller(db, shop_name=f"생활용품-{stamp}")
        db.add_all([drink, housewares])
        db.flush()
        drink_a = _pg_offer(drink, official, price_credits=1500)
        drink_b = _pg_offer(drink, mart, price_credits=1800)
        house_offer = _pg_offer(housewares, house_seller, price_credits=9900)
        db.add_all([drink_a, drink_b, house_offer])
        db.flush()

        collapsed = list_catalog_products(db, l1_tag=TAG_WATER)
        collapsed_ids = {item.id for item in collapsed.items}
        assert str(drink.id) in collapsed_ids
        assert str(housewares.id) not in collapsed_ids

        offers = list_catalog_offers(db, l1_tag=TAG_WATER)
        offer_ids = {item.id for item in offers.items}
        assert str(drink_a.id) in offer_ids
        assert str(drink_b.id) in offer_ids
        assert str(house_offer.id) not in offer_ids
        assert offers.total >= 2
        drink_rows = [item for item in offers.items if item.catalog_product_id == str(drink.id)]
        assert len(drink_rows) == 2
        assert {item.seller.shop_name for item in drink_rows} == {official.shop_name, mart.shop_name}
        assert {item.price_credits for item in drink_rows} == {1500, 1800}

        truncated = list_catalog_offers(db, l1_tag="생수")
        assert truncated.items == []
        assert truncated.total == 0
    finally:
        db.rollback()
        db.close()
        engine.dispose()
