from unittest.mock import MagicMock
from uuid import uuid4

from app.models import CatalogProduct
from app.services.catalog_cleanup import catalog_image_is_displayable, purge_catalogs_without_display_image


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
