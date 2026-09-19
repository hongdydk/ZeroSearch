import inspect
from unittest.mock import MagicMock
from uuid import uuid4

from app.models import CatalogProduct
from app.services.catalog_cleanup import (
    PR36_DEMO_CATALOG_KEYS,
    catalog_image_is_displayable,
    purge_catalogs_without_display_image,
    purge_pr36_demo_catalog_cards,
)
from seed import ensure_catalog_seed


def test_catalog_image_is_displayable():
    assert catalog_image_is_displayable("https://cdn.example.com/a.webp") is True
    assert catalog_image_is_displayable("http://cdn.example.com/a.webp") is True
    assert catalog_image_is_displayable("/images/foo.png") is False
    assert catalog_image_is_displayable("") is False
    assert catalog_image_is_displayable(None) is False


def test_purge_catalogs_without_display_image_removes_relative_paths():
    keep = CatalogProduct(
        id=uuid4(),
        title="iPhone",
        category="electronics",
        image_url="https://cdn.dummyjson.com/x.webp",
    )
    mfds = CatalogProduct(
        id=uuid4(),
        title="배추김치",
        category="김치",
        image_url=None,
    )
    drop = CatalogProduct(
        id=uuid4(),
        title="Water",
        category="beverage",
        image_url="/images/baisansu.png",
    )
    db = MagicMock()
    db.scalars.return_value.all.side_effect = [
        [keep, mfds, drop],
        [],
    ]

    removed = purge_catalogs_without_display_image(db)

    assert removed == 1
    assert db.delete.call_count == 1
    assert db.delete.call_args.args[0] is drop


def test_pr36_demo_keys_are_manufacturer_and_title_only():
    assert PR36_DEMO_CATALOG_KEYS == (
        ("제주특별자치도개발공사", "제주삼다수"),
        ("롯데칠성음료", "레쓰비"),
    )


def test_catalog_seed_does_not_reseed_pr36_demo_cards():
    import seed

    assert not hasattr(seed, "SIMPLE_DEMO_CATALOGS")
    module_source = inspect.getsource(seed)
    assert "_ensure_simple_demo" not in module_source
    assert "_ensure_demo_offer" not in module_source
    seed_fn = inspect.getsource(ensure_catalog_seed)
    assert "레쓰비" not in seed_fn
    assert "제주삼다수" not in seed_fn
    assert "SIMPLE_DEMO" not in seed_fn


def test_purge_pr36_demo_catalog_cards_deletes_matching_row():
    demo = CatalogProduct(
        id=uuid4(),
        title="제주삼다수",
        manufacturer="제주특별자치도개발공사",
        category="일반생수",
    )
    db = MagicMock()
    db.scalars.return_value.all.side_effect = [
        [demo],
        [],
        [],
    ]
    db.scalar.return_value = None

    result = purge_pr36_demo_catalog_cards(db)

    assert result == {
        "removed_catalogs": 1,
        "removed_offers": 0,
        "skipped_with_orders": 0,
    }
    db.delete.assert_called_once()
    assert db.delete.call_args.args[0] is demo


def test_purge_pr36_demo_catalog_cards_skips_rows_with_orders():
    demo = CatalogProduct(
        id=uuid4(),
        title="레쓰비",
        manufacturer="롯데칠성음료",
        category="커피음료",
    )
    db = MagicMock()
    db.scalars.return_value.all.side_effect = [
        [demo],
        [uuid4()],
    ]
    db.scalar.return_value = uuid4()

    result = purge_pr36_demo_catalog_cards(db)

    assert result["removed_catalogs"] == 0
    assert result["skipped_with_orders"] == 1
    db.delete.assert_not_called()
