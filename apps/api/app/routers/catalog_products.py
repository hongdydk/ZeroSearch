from typing import Annotated, Any
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from pydantic import BeforeValidator
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.catalog_product import (
    CatalogOfferBrowseListResponse,
    CatalogProductDetailResponse,
    CatalogProductListResponse,
    GuestL1FacetsResponse,
    GuestL1Item,
    GuestL1ListResponse,
)
from app.services.catalog_l1 import list_l1_facets
from app.services.catalog_products import (
    get_catalog_product,
    list_catalog_offers,
    list_catalog_products,
)
from app.services.guest_l1 import GUEST_L1_TAGS, default_axis_for

router = APIRouter(prefix="/catalog-products", tags=["catalog-products"])


def _optional_non_negative_int(value: Any) -> int | None:
    if value is None or value == "":
        return None
    parsed = int(value)
    if parsed < 0:
        raise ValueError("Input should be greater than or equal to 0")
    return parsed


OptionalVolumeMlMin = Annotated[
    int | None,
    BeforeValidator(_optional_non_negative_int),
    Query(alias="volumeMlMin"),
]
OptionalVolumeMlMax = Annotated[
    int | None,
    BeforeValidator(_optional_non_negative_int),
    Query(alias="volumeMlMax"),
]


@router.get("/guest-l1", response_model=GuestL1ListResponse)
def get_guest_l1_categories() -> GuestL1ListResponse:
    return GuestL1ListResponse(
        items=[GuestL1Item(name=name, default_axis=default_axis_for(name)) for name in GUEST_L1_TAGS]
    )


@router.get("/guest-l1/facets", response_model=GuestL1FacetsResponse)
def get_guest_l1_facets(
    db: Annotated[Session, Depends(get_db)],
    l1_tag: Annotated[str | None, Query(alias="l1Tag")] = None,
    q: str | None = None,
    storage: str | None = None,
) -> GuestL1FacetsResponse:
    payload = list_l1_facets(db, l1_tag=l1_tag, q=q, storage=storage)
    return GuestL1FacetsResponse.model_validate(payload)


@router.get("/offers", response_model=CatalogOfferBrowseListResponse)
def get_catalog_offers(
    db: Annotated[Session, Depends(get_db)],
    q: str | None = None,
    category: str | None = None,
    category_major: Annotated[str | None, Query(alias="categoryMajor")] = None,
    category_mid: Annotated[str | None, Query(alias="categoryMid")] = None,
    l1_tag: Annotated[str | None, Query(alias="l1Tag")] = None,
    storage: str | None = None,
    brand: str | None = None,
    menu: str | None = None,
    flavor: str | None = None,
    volume_ml_min: OptionalVolumeMlMin = None,
    volume_ml_max: OptionalVolumeMlMax = None,
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
) -> CatalogOfferBrowseListResponse:
    result = list_catalog_offers(
        db,
        q=q,
        category=category,
        category_major=category_major,
        category_mid=category_mid,
        l1_tag=l1_tag,
        storage=storage,
        brand=brand,
        menu=menu,
        flavor=flavor,
        volume_ml_min=volume_ml_min,
        volume_ml_max=volume_ml_max,
        offset=offset,
        limit=limit,
    )
    return CatalogOfferBrowseListResponse(items=result.items, total=result.total)


@router.get("", response_model=CatalogProductListResponse)
def get_catalog_products(
    db: Annotated[Session, Depends(get_db)],
    q: str | None = None,
    category: str | None = None,
    category_major: Annotated[str | None, Query(alias="categoryMajor")] = None,
    category_mid: Annotated[str | None, Query(alias="categoryMid")] = None,
    l1_tag: Annotated[str | None, Query(alias="l1Tag")] = None,
    storage: str | None = None,
    brand: str | None = None,
    menu: str | None = None,
    flavor: str | None = None,
    volume_ml_min: OptionalVolumeMlMin = None,
    volume_ml_max: OptionalVolumeMlMax = None,
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
) -> CatalogProductListResponse:
    result = list_catalog_products(
        db,
        q=q,
        category=category,
        category_major=category_major,
        category_mid=category_mid,
        l1_tag=l1_tag,
        storage=storage,
        brand=brand,
        menu=menu,
        flavor=flavor,
        volume_ml_min=volume_ml_min,
        volume_ml_max=volume_ml_max,
        offset=offset,
        limit=limit,
    )
    return CatalogProductListResponse(
        items=result.items,
        total=result.total,
        available_flavors=result.available_flavors,
        has_volume_min_2000=result.has_volume_min_2000,
    )


@router.get("/{catalog_id}", response_model=CatalogProductDetailResponse)
def get_catalog_product_by_id(
    catalog_id: UUID,
    db: Annotated[Session, Depends(get_db)],
    flavor: str | None = None,
    volume_ml_min: OptionalVolumeMlMin = None,
    volume_ml_max: OptionalVolumeMlMax = None,
) -> CatalogProductDetailResponse:
    return get_catalog_product(
        db,
        catalog_id,
        flavor=flavor,
        volume_ml_min=volume_ml_min,
        volume_ml_max=volume_ml_max,
    )
