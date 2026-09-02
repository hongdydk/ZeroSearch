"""Pure mapping tests for DummyJSON catalog import (no network)."""

from unittest.mock import MagicMock, patch

import pytest

from scripts.import_dummyjson_catalog import (
    import_dummyjson_catalog,
    map_dummyjson_category,
    map_dummyjson_product,
    merchant_price_variation,
    price_to_credits,
    should_add_merchant_offer,
    title_to_search_keywords,
)


SAMPLE_ITEM = {
    "id": 1,
    "title": "iPhone 9",
    "description": "An apple mobile which is nothing like apple",
    "price": 549,
    "stock": 94,
    "category": "smartphones",
    "thumbnail": "https://cdn.dummyjson.com/product-images/smartphones/1/thumbnail.webp",
}


def test_map_dummyjson_category_known_and_fallback():
    assert map_dummyjson_category("smartphones") == "electronics"
    assert map_dummyjson_category("womens-dresses") == "fashion"
    assert map_dummyjson_category("Unknown Category") == "unknown-category"


def test_price_to_credits():
    assert price_to_credits(9.99) == 100
    assert price_to_credits(549) == 5490
    assert price_to_credits(0) == 1


def test_title_to_search_keywords():
    keywords = title_to_search_keywords("Essence Mascara Lash Princess")
    assert "essence" in keywords
    assert "mascara" in keywords
    assert "lash" in keywords


def test_should_add_merchant_offer_ratio():
    ids = list(range(1, 101))
    merchant_count = sum(1 for i in ids if should_add_merchant_offer(i))
    assert 25 <= merchant_count <= 35


def test_merchant_price_variation_within_band():
    base = 1000
    for seed in ("1:iPhone", "2:MacBook", "3:Perfume"):
        varied = merchant_price_variation(base, seed)
        assert 850 <= varied <= 1150


def test_map_dummyjson_product():
    mapped = map_dummyjson_product(SAMPLE_ITEM)
    assert mapped["catalog"]["title"] == "iPhone 9"
    assert mapped["catalog"]["category"] == "electronics"
    assert mapped["catalog"]["image_url"] == SAMPLE_ITEM["thumbnail"]
    assert mapped["catalog"]["price_unit"] == "each"
    assert mapped["platform_offer"]["price_credits"] == 5490
    assert mapped["platform_offer"]["stock"] == 94
    assert mapped["add_merchant"] is True


def test_import_dummyjson_catalog_idempotent_skip():
    db = MagicMock()
    db.scalar.return_value = "existing-id"  # catalog already present

    platform = MagicMock()
    merchant = MagicMock()
    stats = import_dummyjson_catalog(
        db,
        products=[SAMPLE_ITEM],
        platform_seller=platform,
        merchant_seller=merchant,
    )

    assert stats["skipped_existing"] == 1
    assert stats["catalogs_created"] == 0
    db.add.assert_not_called()


def test_import_dummyjson_catalog_creates_offers():
    db = MagicMock()
    db.scalar.return_value = None

    def flush_side_effect():
        if not hasattr(flush_side_effect, "catalog"):
            flush_side_effect.catalog = MagicMock(id="cat-1", title="iPhone 9")
            db.add.call_args_list[-1][0][0]  # last added catalog
        return None

    db.flush = MagicMock(side_effect=flush_side_effect)

    platform = MagicMock(id="platform-1")
    merchant = MagicMock(id="merchant-1")

    stats = import_dummyjson_catalog(
        db,
        products=[SAMPLE_ITEM],
        platform_seller=platform,
        merchant_seller=merchant,
    )

    assert stats["catalogs_created"] == 1
    assert stats["platform_offers_created"] == 1
    assert stats["merchant_offers_created"] == 1
    assert stats["skipped_existing"] == 0
    assert db.add.call_count == 3  # catalog + platform + merchant


@patch("scripts.import_dummyjson_catalog.fetch_dummyjson_products")
def test_run_import_commits(mock_fetch):
    from scripts.import_dummyjson_catalog import run_import

    mock_fetch.return_value = [SAMPLE_ITEM]

    mock_db = MagicMock()
    mock_admin = MagicMock()
    mock_platform = MagicMock(id="p1")
    mock_merchant = MagicMock(id="m1")

    with (
        patch("scripts.import_dummyjson_catalog.SessionLocal", return_value=mock_db),
        patch("scripts.import_dummyjson_catalog.ensure_admin_user", return_value=mock_admin),
        patch("scripts.import_dummyjson_catalog.ensure_platform_seller", return_value=mock_platform),
        patch("scripts.import_dummyjson_catalog.ensure_merchant_seller", return_value=mock_merchant),
        patch(
            "scripts.import_dummyjson_catalog.import_dummyjson_catalog",
            return_value={
                "fetched": 1,
                "catalogs_created": 1,
                "platform_offers_created": 1,
                "merchant_offers_created": 1,
                "skipped_existing": 0,
            },
        ),
    ):
        stats = run_import(limit=1)

    mock_db.commit.assert_called_once()
    assert stats["total_catalogs"] == mock_db.scalar.return_value
