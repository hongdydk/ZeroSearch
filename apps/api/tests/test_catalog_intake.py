import uuid
from datetime import UTC, datetime
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.deps import require_active_seller
from app.models import CatalogIntakeDraft, CatalogProduct, Product, Seller
from app.schemas.catalog_intake import (
    AdminAttachDraftRequest,
    AdminPromoteDraftRequest,
    SellerCardDraftCreateRequest,
    SellerCardDraftUpdateRequest,
)
from app.schemas.seller import SellerProductCreateRequest, SellerProductUpdateRequest
from app.services.catalog_intake import (
    attach_intake_draft,
    card_draft_to_item,
    create_card_draft,
    promote_card_draft,
    update_card_draft,
)
from app.services.catalog_products import _public_offer_filters
from app.services.products import create_seller_product, update_seller_product
from tests.factories import make_user, override_current_user, override_db


def _seller(**kwargs) -> Seller:
    seller = Seller(
        id=uuid.uuid4(),
        user_id=uuid.uuid4(),
        shop_name="입점마트",
        slug="merchant-shop",
        status="active",
        seller_type="merchant",
    )
    seller.created_at = datetime.now(UTC)
    for key, value in kwargs.items():
        setattr(seller, key, value)
    return seller


def _catalog(**kwargs) -> CatalogProduct:
    catalog = CatalogProduct(
        id=uuid.uuid4(),
        title="백산수",
        manufacturer="농심",
        category="생수",
        volume_options=["2L"],
        reference_variants=[],
        price_unit="ml",
    )
    catalog.created_at = datetime.now(UTC)
    for key, value in kwargs.items():
        setattr(catalog, key, value)
    return catalog


def _draft(seller: Seller, **kwargs) -> CatalogIntakeDraft:
    draft = CatalogIntakeDraft(
        id=uuid.uuid4(),
        seller_id=seller.id,
        status="pending",
        manufacturer="매일",
        title="떡갈비",
        category="축산가공",
        option_label="500g",
        volume_ml=500,
        price_credits=4800,
        stock=12,
        visibility="public",
        image_url="https://img.example/tteok.jpg",
    )
    draft.created_at = datetime.now(UTC)
    draft.seller = seller
    for key, value in kwargs.items():
        setattr(draft, key, value)
    return draft


def test_create_seller_product_requires_catalog_id():
    seller = _seller()
    payload = SellerProductCreateRequest(
        title="제목만으로 만들기",
        priceCredits=1000,
        stock=3,
        category="생수",
        status="published",
    )
    with pytest.raises(HTTPException) as exc:
        create_seller_product(MagicMock(), seller, payload)
    assert exc.value.status_code == 400
    assert "대표 상품" in exc.value.detail


def test_create_seller_product_forces_draft_not_public():
    seller = _seller()
    catalog = _catalog()
    payload = SellerProductCreateRequest(
        title="판매자 제목",
        priceCredits=1500,
        stock=4,
        category="판매자분류",
        status="published",
        catalogProductId=str(catalog.id),
        optionLabel="2L",
        imageUrl="https://img.example/offer.jpg",
    )
    added: list[Product] = []
    db = MagicMock()
    db.add.side_effect = lambda obj: added.append(obj)

    published_like = Product(
        id=uuid.uuid4(),
        seller_id=seller.id,
        catalog_product_id=catalog.id,
        title=catalog.title,
        price_credits=1500,
        stock=4,
        category=catalog.category,
        status="draft",
    )
    published_like.seller = seller

    with (
        patch("app.services.products.resolve_catalog_product", return_value=catalog),
        patch("app.services.products.get_seller_product", return_value=published_like),
    ):
        create_seller_product(db, seller, payload)

    assert len(added) == 1
    offer = added[0]
    assert offer.status == "draft"
    assert offer.title == "백산수"
    assert offer.category == "생수"
    assert offer.catalog_product_id == catalog.id
    assert offer.image_url == "https://img.example/offer.jpg"


def test_create_seller_product_without_price_stays_draft():
    seller = _seller()
    catalog = _catalog()
    payload = SellerProductCreateRequest(
        title="백산수",
        category="생수",
        catalogProductId=str(catalog.id),
        unitAmount=2,
        unit="L",
        packCount=12,
    )
    added: list[Product] = []
    db = MagicMock()
    db.add.side_effect = lambda obj: added.append(obj)
    created = Product(
        id=uuid.uuid4(),
        seller_id=seller.id,
        catalog_product_id=catalog.id,
        title=catalog.title,
        price_credits=0,
        stock=0,
        category=catalog.category,
        status="draft",
    )
    created.seller = seller
    with (
        patch("app.services.products.resolve_catalog_product", return_value=catalog),
        patch("app.services.products.get_seller_product", return_value=created),
    ):
        create_seller_product(db, seller, payload)
    offer = added[0]
    assert offer.status == "draft"
    assert offer.price_credits == 0
    assert offer.stock == 0
    assert offer.option_label == "2L × 12"
    assert offer.volume_ml == 2000
    assert offer.pack_count == 12
    assert offer.unit == "L"
    assert float(offer.unit_amount) == 2


def test_create_seller_product_allows_option_outside_volume_list():
    seller = _seller()
    catalog = _catalog(volume_options=["2L"])
    payload = SellerProductCreateRequest(
        title="백산수",
        category="생수",
        catalogProductId=str(catalog.id),
        optionLabel="1.5L × 8",
    )
    added: list[Product] = []
    db = MagicMock()
    db.add.side_effect = lambda obj: added.append(obj)
    created = Product(
        id=uuid.uuid4(),
        seller_id=seller.id,
        catalog_product_id=catalog.id,
        title=catalog.title,
        price_credits=0,
        stock=0,
        category=catalog.category,
        status="draft",
    )
    created.seller = seller
    with (
        patch("app.services.products.resolve_catalog_product", return_value=catalog),
        patch("app.services.products.get_seller_product", return_value=created),
    ):
        create_seller_product(db, seller, payload)
    offer = added[0]
    assert offer.option_label == "1.5L × 8"
    assert offer.volume_ml == 1500
    assert offer.pack_count == 8


def test_seller_cannot_publish_own_draft():
    seller = _seller()
    product = Product(
        id=uuid.uuid4(),
        seller_id=seller.id,
        catalog_product_id=uuid.uuid4(),
        title="백산수",
        price_credits=1000,
        stock=2,
        category="생수",
        status="draft",
    )
    product.seller = seller
    with patch("app.services.products.get_seller_product", return_value=product):
        with pytest.raises(HTTPException) as exc:
            update_seller_product(
                MagicMock(),
                seller,
                product.id,
                SellerProductUpdateRequest(status="published"),
            )
    assert exc.value.status_code == 400
    assert "검수" in exc.value.detail
    assert product.status == "draft"


def test_create_card_draft_does_not_insert_catalog_product():
    seller = _seller()
    payload = SellerCardDraftCreateRequest(
        manufacturer="매일",
        title="떡갈비",
        category="축산가공",
        optionLabel="500g",
        priceCredits=4800,
        stock=8,
        imageUrl="https://img.example/tteok.jpg",
        flavor="오리지널",
    )
    added: list[object] = []
    db = MagicMock()
    db.add.side_effect = lambda obj: added.append(obj)
    created = _draft(seller)
    db.scalar.return_value = created

    result = create_card_draft(db, seller, payload)

    assert result is created
    assert len(added) == 1
    assert isinstance(added[0], CatalogIntakeDraft)
    assert not any(isinstance(obj, CatalogProduct) for obj in added)
    assert not any(isinstance(obj, Product) for obj in added)
    assert added[0].status == "pending"
    assert added[0].title == "떡갈비"
    assert added[0].visibility == "public"


def test_create_card_draft_hidden_stays_pending():
    seller = _seller()
    payload = SellerCardDraftCreateRequest(
        manufacturer="매일",
        title="떡갈비",
        category="축산가공",
        optionLabel="500g",
        visibility="hidden",
    )
    added: list[object] = []
    db = MagicMock()
    db.add.side_effect = lambda obj: added.append(obj)
    created = _draft(seller, visibility="hidden")
    db.scalar.return_value = created

    result = create_card_draft(db, seller, payload)

    assert result is created
    draft = added[0]
    assert isinstance(draft, CatalogIntakeDraft)
    assert draft.status == "pending"
    assert draft.visibility == "hidden"
    assert not any(isinstance(obj, CatalogProduct) for obj in added)
    assert not any(isinstance(obj, Product) for obj in added)


def test_create_card_draft_without_price_keeps_units():
    seller = _seller()
    payload = SellerCardDraftCreateRequest(
        manufacturer="매일",
        title="떡갈비",
        category="축산가공",
        unitAmount=500,
        unit="g",
        packCount=2,
    )
    added: list[object] = []
    db = MagicMock()
    db.add.side_effect = lambda obj: added.append(obj)
    created = _draft(seller, price_credits=0, stock=0, option_label="500g × 2")
    db.scalar.return_value = created

    result = create_card_draft(db, seller, payload)

    assert result is created
    draft = added[0]
    assert isinstance(draft, CatalogIntakeDraft)
    assert draft.price_credits == 0
    assert draft.stock == 0
    assert draft.option_label == "500g × 2"
    assert draft.volume_ml is None
    assert draft.pack_count == 2


def test_update_card_draft_attaches_price():
    seller = _seller()
    draft = _draft(seller, price_credits=0, stock=0)
    db = MagicMock()
    db.scalar.return_value = draft
    updated = update_card_draft(
        db,
        seller,
        draft.id,
        SellerCardDraftUpdateRequest(priceCredits=4800, stock=8),
    )
    assert updated.price_credits == 4800
    assert updated.stock == 8
    assert updated.status == "pending"


def test_update_card_draft_visibility():
    seller = _seller()
    draft = _draft(seller)
    db = MagicMock()
    db.scalar.return_value = draft
    updated = update_card_draft(
        db,
        seller,
        draft.id,
        SellerCardDraftUpdateRequest(visibility="hidden"),
    )
    assert updated.visibility == "hidden"
    assert updated.status == "pending"


def test_create_card_draft_requires_pack():
    seller = _seller()
    payload = SellerCardDraftCreateRequest(
        manufacturer="매일",
        title="떡갈비",
        category="축산가공",
    )
    with pytest.raises(HTTPException) as exc:
        create_card_draft(MagicMock(), seller, payload)
    assert exc.value.status_code == 400


def test_attach_offer_draft_publishes_on_existing_card():
    seller = _seller()
    catalog = _catalog()
    product = Product(
        id=uuid.uuid4(),
        seller_id=seller.id,
        catalog_product_id=catalog.id,
        title=catalog.title,
        price_credits=1200,
        stock=5,
        category=catalog.category,
        status="draft",
        option_label="2L",
    )
    product.seller = seller
    product.catalog_product = catalog
    db = MagicMock()
    db.scalar.side_effect = [product, product]
    reviewer = make_user(is_admin=True)

    with patch("app.services.catalog_intake.resolve_catalog_product", return_value=catalog):
        item = attach_intake_draft(
            db,
            product.id,
            AdminAttachDraftRequest(kind="offer"),
            reviewer,
        )

    assert product.status == "published"
    assert item.kind == "offer"
    assert item.status == "attached"
    assert not any(isinstance(call.args[0], CatalogProduct) for call in db.add.call_args_list)


def test_attach_card_draft_creates_published_offer_not_new_catalog():
    seller = _seller()
    catalog = _catalog(title="농심 떡갈비", manufacturer="농심", category="축산가공", volume_options=[])
    draft = _draft(seller)
    db = MagicMock()
    db.scalar.return_value = draft
    added: list[object] = []

    def _add(obj: object) -> None:
        added.append(obj)
        if isinstance(obj, Product) and getattr(obj, "id", None) is None:
            obj.id = uuid.uuid4()

    db.add.side_effect = _add
    reviewer = make_user(is_admin=True)

    with patch("app.services.catalog_intake.resolve_catalog_product", return_value=catalog):
        item = attach_intake_draft(
            db,
            draft.id,
            AdminAttachDraftRequest(kind="card", catalogProductId=str(catalog.id)),
            reviewer,
        )

    products = [obj for obj in added if isinstance(obj, Product)]
    catalogs = [obj for obj in added if isinstance(obj, CatalogProduct)]
    assert catalogs == []
    assert len(products) == 1
    assert products[0].status == "published"
    assert products[0].catalog_product_id == catalog.id
    assert products[0].title == catalog.title
    assert draft.status == "attached"
    assert item.status == "attached"
    assert "500g" in (catalog.volume_options or [])


def test_attach_hidden_card_draft_creates_archived_offer():
    seller = _seller()
    catalog = _catalog(title="농심 떡갈비", manufacturer="농심", category="축산가공", volume_options=[])
    draft = _draft(seller, visibility="hidden")
    db = MagicMock()
    db.scalar.return_value = draft
    added: list[object] = []

    def _add(obj: object) -> None:
        added.append(obj)
        if isinstance(obj, Product) and getattr(obj, "id", None) is None:
            obj.id = uuid.uuid4()

    db.add.side_effect = _add
    reviewer = make_user(is_admin=True)

    with patch("app.services.catalog_intake.resolve_catalog_product", return_value=catalog):
        item = attach_intake_draft(
            db,
            draft.id,
            AdminAttachDraftRequest(kind="card", catalogProductId=str(catalog.id)),
            reviewer,
        )

    products = [obj for obj in added if isinstance(obj, Product)]
    catalogs = [obj for obj in added if isinstance(obj, CatalogProduct)]
    assert catalogs == []
    assert len(products) == 1
    assert products[0].status == "archived"
    assert draft.status == "attached"
    assert item.status == "attached"
    assert item.visibility == "hidden"


def test_promote_card_draft_creates_catalog_and_published_offer():
    seller = _seller()
    draft = _draft(seller)
    db = MagicMock()
    db.scalar.side_effect = [draft, 0]
    added: list[object] = []

    def _add(obj: object) -> None:
        added.append(obj)
        if getattr(obj, "id", None) is None:
            obj.id = uuid.uuid4()

    db.add.side_effect = _add
    reviewer = make_user(is_admin=True)

    item = promote_card_draft(
        db,
        draft.id,
        AdminPromoteDraftRequest(category="떡갈비", manufacturer="매일", title="떡갈비"),
        reviewer,
    )

    catalogs = [obj for obj in added if isinstance(obj, CatalogProduct)]
    products = [obj for obj in added if isinstance(obj, Product)]
    assert len(catalogs) == 1
    assert len(products) == 1
    assert catalogs[0].manufacturer == "매일"
    assert catalogs[0].category == "떡갈비"
    assert catalogs[0].title == "떡갈비"
    assert products[0].status == "published"
    assert products[0].catalog_product_id == catalogs[0].id
    assert draft.status == "promoted"
    assert item.status == "promoted"


def test_promote_hidden_card_draft_creates_archived_offer():
    seller = _seller()
    draft = _draft(seller, visibility="hidden")
    db = MagicMock()
    db.scalar.side_effect = [draft, 0]
    added: list[object] = []

    def _add(obj: object) -> None:
        added.append(obj)
        if getattr(obj, "id", None) is None:
            obj.id = uuid.uuid4()

    db.add.side_effect = _add
    reviewer = make_user(is_admin=True)

    item = promote_card_draft(
        db,
        draft.id,
        AdminPromoteDraftRequest(category="떡갈비", manufacturer="매일", title="떡갈비"),
        reviewer,
    )

    catalogs = [obj for obj in added if isinstance(obj, CatalogProduct)]
    products = [obj for obj in added if isinstance(obj, Product)]
    assert len(catalogs) == 1
    assert len(products) == 1
    assert products[0].status == "archived"
    assert draft.status == "promoted"
    assert item.status == "promoted"
    assert item.visibility == "hidden"


def test_promote_doenjang_jjigae_auto_tags_soup_not_sauce():
    seller = _seller()
    draft = _draft(seller, title="된장찌개 레토르트", manufacturer="오뚜기", category="즉석국/찌개")
    db = MagicMock()
    db.scalar.side_effect = [draft, 0]
    added: list[object] = []

    def _add(obj: object) -> None:
        added.append(obj)
        if getattr(obj, "id", None) is None:
            obj.id = uuid.uuid4()

    db.add.side_effect = _add
    reviewer = make_user(is_admin=True)

    promote_card_draft(
        db,
        draft.id,
        AdminPromoteDraftRequest(
            category="즉석국/찌개",
            manufacturer="오뚜기",
            title="된장찌개 레토르트",
        ),
        reviewer,
    )

    catalogs = [obj for obj in added if isinstance(obj, CatalogProduct)]
    assert catalogs[0].l1_tags is not None
    assert "국/탕/찌개" in catalogs[0].l1_tags
    assert "장류/소스" not in catalogs[0].l1_tags


def test_promote_card_draft_conflict_when_card_exists():
    seller = _seller()
    draft = _draft(seller)
    db = MagicMock()
    db.scalar.side_effect = [draft, 1]
    reviewer = make_user(is_admin=True)

    with pytest.raises(HTTPException) as exc:
        promote_card_draft(
            db,
            draft.id,
            AdminPromoteDraftRequest(category="축산가공"),
            reviewer,
        )
    assert exc.value.status_code == 409
    assert db.add.call_count == 0


def test_public_offer_filters_only_published():
    sql = " ".join(
        str(clause.compile(compile_kwargs={"literal_binds": True})) for clause in _public_offer_filters()
    )
    assert "products.status = 'published'" in sql
    assert "draft" not in sql


def test_seller_create_card_draft_route(client):
    user = make_user()
    seller = _seller(user_id=user.id)
    override_current_user(user)
    override_db(MagicMock())
    from main import app

    draft = _draft(seller)
    app.dependency_overrides[require_active_seller] = lambda: seller
    try:
        with patch("app.routers.seller.create_card_draft", return_value=draft):
            response = client.post(
                "/seller/card-drafts",
            json={
                "manufacturer": "매일",
                "title": "떡갈비",
                "category": "축산가공",
                "optionLabel": "500g",
            },
                headers={"Authorization": "Bearer fake"},
            )
    finally:
        app.dependency_overrides.pop(require_active_seller, None)

    assert response.status_code == 201
    assert response.json()["kind"] == "card"
    assert response.json()["status"] == "pending"
    assert response.json()["title"] == "떡갈비"
    assert response.json()["visibility"] == "public"


def test_seller_create_product_router_stays_gated(client):
    user = make_user()
    seller = _seller(user_id=user.id)
    override_current_user(user)
    override_db(MagicMock())
    from main import app

    app.dependency_overrides[require_active_seller] = lambda: seller
    try:
        response = client.post(
            "/seller/products",
            json={
                "title": "제목만 넣기",
                "priceCredits": 1000,
                "stock": 1,
                "category": "생수",
                "status": "published",
            },
            headers={"Authorization": "Bearer fake"},
        )
    finally:
        app.dependency_overrides.pop(require_active_seller, None)

    assert response.status_code == 400
    assert "대표 상품" in response.json()["detail"]


def test_admin_intake_queue_ok(client):
    admin = make_user(is_admin=True)
    override_current_user(admin)
    override_db(MagicMock())
    seller = _seller()
    draft = _draft(seller)
    with patch(
        "app.routers.admin.list_admin_intake_queue",
        return_value=([card_draft_to_item(draft)], 1),
    ):
        response = client.get("/admin/catalog/drafts", headers={"Authorization": "Bearer fake"})

    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["kind"] == "card"
    assert body["items"][0]["title"] == "떡갈비"


def test_admin_promote_and_attach_routes(client):
    admin = make_user(is_admin=True)
    override_current_user(admin)
    override_db(MagicMock())
    seller = _seller()
    draft = _draft(seller, status="attached")
    item = card_draft_to_item(draft)
    with patch("app.routers.admin.attach_intake_draft", return_value=item) as mock_attach:
        attach = client.post(
            f"/admin/catalog/drafts/{draft.id}/attach",
            json={"kind": "card", "catalogProductId": str(uuid.uuid4())},
            headers={"Authorization": "Bearer fake"},
        )
    assert attach.status_code == 200
    mock_attach.assert_called_once()

    draft.status = "promoted"
    promoted = card_draft_to_item(draft)
    with patch("app.routers.admin.promote_card_draft", return_value=promoted) as mock_promote:
        promote = client.post(
            f"/admin/catalog/drafts/{draft.id}/promote",
            json={"category": "떡갈비"},
            headers={"Authorization": "Bearer fake"},
        )
    assert promote.status_code == 200
    mock_promote.assert_called_once()


def test_admin_intake_forbidden_for_non_admin(client):
    override_current_user(make_user(is_admin=False))
    response = client.get("/admin/catalog/drafts", headers={"Authorization": "Bearer fake"})
    assert response.status_code == 403
