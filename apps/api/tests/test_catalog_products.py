import uuid
from datetime import UTC, datetime
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.dialects import postgresql

from app.models import CatalogProduct, Product, Seller
from app.schemas.catalog_product import CatalogProductListItem
from app.services.catalog_products import (
    CatalogIdentityRow,
    CatalogListResult,
    CatalogOfferListResult,
    _aggregate_offers,
    _catalog_search_filter,
    _offer_browse_item,
    get_catalog_product,
    offer_filter_facets,
    pick_identity_survivor_ids,
)
from tests.factories import override_db


def _sample_seller(*, seller_type: str = "platform") -> Seller:
    seller = Seller(
        id=uuid.uuid4(),
        user_id=uuid.uuid4(),
        shop_name="공식 스토어" if seller_type == "platform" else "청정마트",
        slug="official" if seller_type == "platform" else "clean-mart",
        status="active",
        seller_type=seller_type,
    )
    seller.created_at = datetime.now(UTC)
    return seller


def _sample_catalog(*, title: str = "백산수", category: str = "생수") -> CatalogProduct:
    catalog = CatalogProduct(
        id=uuid.uuid4(),
        title=title,
        category=category,
        description="테스트 생수",
        price_unit="ml",
    )
    catalog.created_at = datetime.now(UTC)
    return catalog


def _sample_offer(
    catalog: CatalogProduct,
    seller: Seller,
    *,
    price_credits: int,
    volume_ml: int | None = None,
    flavor: str | None = None,
    option_label: str | None = None,
) -> Product:
    offer = Product(
        id=uuid.uuid4(),
        seller_id=seller.id,
        catalog_product_id=catalog.id,
        title=catalog.title,
        price_credits=price_credits,
        stock=10,
        category=catalog.category,
        status="published",
        volume_ml=volume_ml,
        flavor=flavor,
        option_label=option_label,
    )
    offer.created_at = datetime.now(UTC)
    offer.seller = seller
    return offer


def test_aggregate_median_unit_price():
    catalog = _sample_catalog()
    seller = _sample_seller()
    offers = [
        _sample_offer(catalog, seller, price_credits=10000, volume_ml=10000),
        _sample_offer(catalog, seller, price_credits=12000, volume_ml=10000),
        _sample_offer(catalog, seller, price_credits=9000, volume_ml=10000),
    ]
    count, median_unit, median_credits, price_unit, label = _aggregate_offers(offers)
    assert count == 3
    assert median_unit == pytest.approx(1.0)
    assert median_credits is None
    assert price_unit == "ml"
    assert label == "L당"


def test_aggregate_median_credits_fallback():
    catalog = _sample_catalog(title="무선 이어폰", category="electronics")
    seller = _sample_seller()
    offers = [
        _sample_offer(catalog, seller, price_credits=40),
        _sample_offer(catalog, seller, price_credits=50),
        _sample_offer(catalog, seller, price_credits=45),
    ]
    count, median_unit, median_credits, price_unit, label = _aggregate_offers(offers)
    assert count == 3
    assert median_unit is None
    assert median_credits == 45
    assert price_unit == "credits"
    assert label == "원"


def test_aggregate_no_offers_returns_null_prices():
    count, median_unit, median_credits, price_unit, _label = _aggregate_offers([])
    assert count == 0
    assert median_unit is None
    assert median_credits is None
    assert price_unit == "credits"


def test_catalog_search_filter_compiles_for_query():
    stmt = select(CatalogProduct).where(*_catalog_search_filter("김치", None))
    sql = str(stmt.compile(dialect=postgresql.dialect()))
    assert "ILIKE" in sql.upper()
    assert "search_keywords" in sql


def test_list_catalog_products(client):
    catalog = _sample_catalog()
    seller = _sample_seller()
    items = [
        CatalogProductListItem(
            id=str(catalog.id),
            title="백산수",
            category="생수",
            offer_count=2,
            median_unit_price=0.52,
            median_price_credits=None,
            price_unit="ml",
            display_price_label="L당",
        )
    ]
    override_db(MagicMock())

    with patch(
        "app.routers.catalog_products.list_catalog_products",
        return_value=CatalogListResult(
            items=items, total=1, available_flavors=["레몬"], has_volume_min_2000=True
        ),
    ):
        response = client.get("/catalog-products?q=생수")

    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["title"] == "백산수"
    assert body["items"][0]["medianUnitPrice"] == 0.52
    assert "minPriceCredits" not in body["items"][0]
    assert body["availableFlavors"] == ["레몬"]
    assert body["hasVolumeMin2000"] is True


def test_list_catalog_products_flavor_filter(client):
    override_db(MagicMock())

    with patch(
        "app.routers.catalog_products.list_catalog_products",
        return_value=CatalogListResult(
            items=[], total=0, available_flavors=[], has_volume_min_2000=False
        ),
    ) as mock_list:
        response = client.get("/catalog-products?flavor=레몬&volumeMlMin=2000")

    assert response.status_code == 200
    mock_list.assert_called_once()
    _, kwargs = mock_list.call_args
    assert kwargs["flavor"] == "레몬"
    assert kwargs["volume_ml_min"] == 2000
    # 구매자 목록은 오퍼 없는 대표 상품도 포함 (기본 require_offers=False)
    assert kwargs.get("require_offers", False) is False


def test_list_catalog_products_includes_zero_offer_item(client):
    catalog = _sample_catalog(title="등록 전 생수")
    items = [
        CatalogProductListItem(
            id=str(catalog.id),
            title="등록 전 생수",
            category="생수",
            offer_count=0,
            median_unit_price=None,
            median_price_credits=None,
            price_unit="credits",
            display_price_label="원",
        )
    ]
    override_db(MagicMock())

    with patch(
        "app.routers.catalog_products.list_catalog_products",
        return_value=CatalogListResult(
            items=items, total=1, available_flavors=[], has_volume_min_2000=False
        ),
    ):
        response = client.get("/catalog-products?q=생수")

    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["offerCount"] == 0
    assert body["items"][0]["medianUnitPrice"] is None
    assert body["items"][0]["medianPriceCredits"] is None


def test_list_catalog_products_empty_volume_filters(client):
    override_db(MagicMock())

    with patch(
        "app.routers.catalog_products.list_catalog_products",
        return_value=CatalogListResult(
            items=[], total=0, available_flavors=[], has_volume_min_2000=False
        ),
    ) as mock_list:
        response = client.get("/catalog-products?volumeMlMin=&volumeMlMax=")

    assert response.status_code == 200
    mock_list.assert_called_once()
    _, kwargs = mock_list.call_args
    assert kwargs["volume_ml_min"] is None
    assert kwargs["volume_ml_max"] is None


def test_get_catalog_product_detail(client):
    catalog_id = uuid.uuid4()
    override_db(MagicMock())
    from app.schemas.catalog_product import CatalogProductDetailResponse

    detail = CatalogProductDetailResponse(
        id=str(catalog_id),
        title="백산수",
        category="생수",
        offer_count=1,
        offers=[],
    )

    with patch("app.routers.catalog_products.get_catalog_product", return_value=detail):
        response = client.get(f"/catalog-products/{catalog_id}")

    assert response.status_code == 200
    assert response.json()["title"] == "백산수"


def test_get_catalog_product_not_found(client):
    override_db(MagicMock())

    with patch(
        "app.routers.catalog_products.get_catalog_product",
        side_effect=HTTPException(status_code=404, detail="대표 상품을 찾을 수 없습니다."),
    ):
        response = client.get(f"/catalog-products/{uuid.uuid4()}")

    assert response.status_code == 404


def test_guest_l1_list_has_fifteen_overlapping_names(client):
    response = client.get("/catalog-products/guest-l1")
    assert response.status_code == 200
    items = response.json()["items"]
    names = [row["name"] for row in items]
    assert names == [
        "생수/음료",
        "커피/원두/차",
        "과자/초콜릿/시리얼",
        "라면/면류",
        "통조림/캔",
        "반찬/간편식/대용식",
        "국/탕/찌개",
        "즉석밥/볶음밥",
        "죽/스프",
        "분식/만두/피자",
        "짜장/카레/돈까스",
        "냉장/냉동/간편요리",
        "가루/조미료/오일",
        "장류/소스",
        "유제품/아이스크림",
    ]
    assert items[3]["defaultAxis"] == "brand"
    assert items[6]["defaultAxis"] == "menu"
    assert items[0]["l2s"] == [
        "생수",
        "탄산·이온·스포츠",
        "주스·과채",
        "전통음료",
        "병·캔 커피·차",
        "기타음료",
    ]
    assert items[3]["l2s"] == ["봉지라면", "컵·용기면", "국수·당면·파스타", "냉면·기타면"]
    for row in items:
        assert 3 <= len(row["l2s"]) <= 7


def test_list_catalog_products_l1_query(client):
    override_db(MagicMock())
    with patch(
        "app.routers.catalog_products.list_catalog_products",
        return_value=CatalogListResult(
            items=[], total=0, available_flavors=[], has_volume_min_2000=False
        ),
    ) as mock_list:
        response = client.get(
            "/catalog-products",
            params={"l1Tag": "라면/면류", "brand": "농심", "storage": "상온"},
        )
    assert response.status_code == 200
    _, kwargs = mock_list.call_args
    assert kwargs["l1_tag"] == "라면/면류"
    assert kwargs["brand"] == "농심"
    assert kwargs["storage"] == "상온"


def test_list_catalog_products_l2_query(client):
    override_db(MagicMock())
    with patch(
        "app.routers.catalog_products.list_catalog_products",
        return_value=CatalogListResult(
            items=[], total=0, available_flavors=[], has_volume_min_2000=False
        ),
    ) as mock_list:
        response = client.get(
            "/catalog-products",
            params={"l1Tag": "라면/면류", "l2Tag": "봉지라면", "brand": "농심"},
        )
    assert response.status_code == 200
    _, kwargs = mock_list.call_args
    assert kwargs["l1_tag"] == "라면/면류"
    assert kwargs["l2_tag"] == "봉지라면"
    assert kwargs["brand"] == "농심"


def test_guest_l1_facets(client):
    override_db(MagicMock())
    payload = {
        "l1_tag": "라면/면류",
        "default_axis": "brand",
        "brands": [{"name": "농심", "count": 2}],
        "menus": [{"name": "신라면", "count": 1}],
    }
    with patch("app.routers.catalog_products.list_l1_facets", return_value=payload):
        response = client.get("/catalog-products/guest-l1/facets", params={"l1Tag": "라면/면류"})
    assert response.status_code == 200
    body = response.json()
    assert body["l1Tag"] == "라면/면류"
    assert body["brands"][0]["name"] == "농심"
    assert body["menus"][0]["name"] == "신라면"


def test_guest_l1_facets_passes_l2_query(client):
    override_db(MagicMock())
    payload = {
        "l1_tag": "라면/면류",
        "l2_tag": "봉지라면",
        "l2s": ["봉지라면", "컵·용기면", "국수·당면·파스타", "냉면·기타면"],
        "default_axis": "brand",
        "brands": [{"name": "농심", "count": 2}],
        "menus": [{"name": "신라면", "count": 1}],
    }
    with patch(
        "app.routers.catalog_products.list_l1_facets", return_value=payload
    ) as mock_facets:
        response = client.get(
            "/catalog-products/guest-l1/facets",
            params={"l1Tag": "라면/면류", "l2Tag": "봉지라면"},
        )
    assert response.status_code == 200
    _, kwargs = mock_facets.call_args
    assert kwargs["l1_tag"] == "라면/면류"
    assert kwargs["l2_tag"] == "봉지라면"
    assert response.json()["l2Tag"] == "봉지라면"


def test_guest_l1_facets_accepts_search_query(client):
    override_db(MagicMock())
    payload = {
        "l1_tag": "",
        "default_axis": "brand",
        "brands": [{"name": "농심", "count": 1}],
        "menus": [{"name": "신라면", "count": 1}],
    }
    with patch(
        "app.routers.catalog_products.list_l1_facets", return_value=payload
    ) as mock_facets:
        response = client.get("/catalog-products/guest-l1/facets", params={"q": "신라면"})
    assert response.status_code == 200
    _, kwargs = mock_facets.call_args
    assert kwargs["q"] == "신라면"
    assert kwargs["l1_tag"] is None
    assert response.json()["menus"][0]["name"] == "신라면"


def test_catalog_l1_filter_compiles():
    stmt = select(CatalogProduct).where(
        *_catalog_search_filter(None, None, l1_tag="라면/면류", storage="냉동", brand="농심")
    )
    sql = str(stmt.compile(dialect=postgresql.dialect()))
    assert "l1_tags" in sql
    assert "storage" in sql
    assert "manufacturer" in sql.lower()


def test_unknown_l1_filter_is_fail_closed_not_brand_only():
    stmt = select(CatalogProduct).where(
        *_catalog_search_filter(None, None, l1_tag="생수", brand="그린에이드")
    )
    sql = str(stmt.compile(dialect=postgresql.dialect()))
    assert "false" in sql.lower()
    # 잘린 l1을 무시하면 브랜드 전 카탈로그 매칭이 된다.


def test_unknown_l2_filter_is_fail_closed():
    stmt = select(CatalogProduct).where(
        *_catalog_search_filter(None, None, l1_tag="라면/면류", l2_tag="생수")
    )
    sql = str(stmt.compile(dialect=postgresql.dialect()))
    assert "false" in sql.lower()


def test_l2_without_l1_is_fail_closed():
    stmt = select(CatalogProduct).where(
        *_catalog_search_filter(None, None, l2_tag="봉지라면", brand="농심")
    )
    sql = str(stmt.compile(dialect=postgresql.dialect()))
    assert "false" in sql.lower()


def test_pick_identity_survivors_collapses_samdasoo_like_duplicates():
    offered = uuid.uuid4()
    empty = uuid.uuid4()
    other_maker = uuid.uuid4()
    survivors = pick_identity_survivor_ids(
        [
            CatalogIdentityRow(
                id=empty,
                manufacturer="제주특별자치도개발공사",
                title="제주삼다수",
                offer_count=0,
                created_at=None,
            ),
            CatalogIdentityRow(
                id=offered,
                manufacturer="제주특별자치도개발공사",
                title="제주삼다수",
                offer_count=3,
                created_at=None,
                has_image=True,
            ),
            CatalogIdentityRow(
                id=other_maker,
                manufacturer="광동",
                title="제주삼다수",
                offer_count=0,
                created_at=None,
            ),
        ]
    )
    assert survivors == [offered, other_maker]


def test_pick_identity_collapses_gamtul_near_duplicate_titles():
    short = uuid.uuid4()
    repeated = uuid.uuid4()
    other_line = uuid.uuid4()
    survivors = pick_identity_survivor_ids(
        [
            CatalogIdentityRow(
                id=short,
                manufacturer="롯데칠성음료",
                title="롯데제주사랑감귤",
                offer_count=0,
                created_at=None,
            ),
            CatalogIdentityRow(
                id=repeated,
                manufacturer="롯데칠성음료",
                title="롯데제주사랑감귤사랑",
                offer_count=0,
                created_at=None,
            ),
            CatalogIdentityRow(
                id=other_line,
                manufacturer="롯데칠성음료",
                title="롯데쌕쌕제주감귤캔",
                offer_count=0,
                created_at=None,
            ),
        ]
    )
    assert len(survivors) == 2
    assert other_line in survivors
    assert {short, repeated} & set(survivors)
    assert not {short, repeated} <= set(survivors)


def test_pick_identity_collapses_equivalent_volume_spellings():
    liter = uuid.uuid4()
    milli = uuid.uuid4()
    other = uuid.uuid4()
    survivors = pick_identity_survivor_ids(
        [
            CatalogIdentityRow(
                id=liter,
                manufacturer="제주특별자치도개발공사",
                title="제주삼다수1리터",
                offer_count=0,
                created_at=None,
            ),
            CatalogIdentityRow(
                id=milli,
                manufacturer="제주특별자치도개발공사",
                title="제주삼다수1000ml",
                offer_count=1,
                created_at=None,
            ),
            CatalogIdentityRow(
                id=other,
                manufacturer="농심",
                title="제주삼다수1L",
                offer_count=0,
                created_at=None,
            ),
        ]
    )
    assert survivors == [milli, other]


def test_pick_identity_keeps_unique_zero_offer_card():
    only = uuid.uuid4()
    assert pick_identity_survivor_ids(
        [
            CatalogIdentityRow(
                id=only,
                manufacturer="팔도",
                title="비락식혜",
                offer_count=0,
                created_at=None,
            )
        ]
    ) == [only]


def test_offer_filter_facets_do_not_leak_water_flavors_into_sikhye():
    flavors, has_volume = offer_filter_facets(
        [None, None, ""],
        [238, 500, 1800],
    )
    assert flavors == []
    assert has_volume is False


def test_offer_filter_facets_keep_flavors_present_in_result_set():
    flavors, has_volume = offer_filter_facets(
        ["레몬", "자몽", "레몬", None],
        [500, 10000, 2000],
    )
    assert flavors == ["레몬", "자몽"]
    assert has_volume is True
    stmt = select(CatalogProduct).where(
        *_catalog_search_filter(None, None, l1_tag="라면/면류", storage="냉동", brand="농심")
    )
    sql = str(stmt.compile(dialect=postgresql.dialect()))
    assert "l1_tags" in sql


def test_offer_browse_item_keeps_seller_and_price_not_identity():
    catalog = _sample_catalog(title="신라면")
    catalog.manufacturer = "농심"
    catalog.image_url = "https://img.example/nongshim.png"
    seller = _sample_seller(seller_type="merchant")
    seller.shop_name = "면사랑마트"
    offer = _sample_offer(catalog, seller, price_credits=4200, option_label="120g")
    offer.catalog_product = catalog
    item = _offer_browse_item(offer)
    assert item.id == str(offer.id)
    assert item.catalog_product_id == str(catalog.id)
    assert item.title == "신라면"
    assert item.manufacturer == "농심"
    assert item.price_credits == 4200
    assert item.seller.shop_name == "면사랑마트"
    assert item.image_url == "https://img.example/nongshim.png"


def test_list_catalog_offers_router_passes_l1_and_shape(client):
    catalog = _sample_catalog(title="신라면")
    catalog.manufacturer = "농심"
    seller_a = _sample_seller()
    seller_a.shop_name = "공식 스토어"
    seller_b = _sample_seller(seller_type="merchant")
    seller_b.shop_name = "면사랑마트"
    offer_a = _sample_offer(catalog, seller_a, price_credits=3900)
    offer_a.catalog_product = catalog
    offer_b = _sample_offer(catalog, seller_b, price_credits=4200)
    offer_b.catalog_product = catalog
    override_db(MagicMock())
    with patch(
        "app.routers.catalog_products.list_catalog_offers",
        return_value=CatalogOfferListResult(
            items=[_offer_browse_item(offer_a), _offer_browse_item(offer_b)],
            total=2,
        ),
    ) as mock_list:
        response = client.get(
            "/catalog-products/offers",
            params={"l1Tag": "라면/면류", "storage": "상온"},
        )
    assert response.status_code == 200
    _, kwargs = mock_list.call_args
    assert kwargs["l1_tag"] == "라면/면류"
    assert kwargs["storage"] == "상온"
    body = response.json()
    assert body["total"] == 2
    assert [row["seller"]["shopName"] for row in body["items"]] == ["공식 스토어", "면사랑마트"]
    assert [row["priceCredits"] for row in body["items"]] == [3900, 4200]
    assert body["items"][0]["id"] != body["items"][1]["id"]
    assert body["items"][0]["catalogProductId"] == body["items"][1]["catalogProductId"]


def test_unknown_l1_offer_filter_is_fail_closed():
    stmt = select(Product).join(CatalogProduct).where(
        *_catalog_search_filter(None, None, l1_tag="생수", brand="그린에이드")
    )
    sql = str(stmt.compile(dialect=postgresql.dialect()))
    assert "false" in sql.lower()

