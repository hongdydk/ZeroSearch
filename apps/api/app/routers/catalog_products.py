from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.catalog_product import CatalogProductDetailResponse, CatalogProductListResponse
from app.services.catalog_products import get_catalog_product, list_catalog_products

router = APIRouter(prefix="/catalog-products", tags=["catalog-products"])


@router.get("", response_model=CatalogProductListResponse)
def get_catalog_products(
    db: Annotated[Session, Depends(get_db)],
    q: str | None = None,
    category: str | None = None,
    flavor: str | None = None,
    volume_ml_min: Annotated[int | None, Query(alias="volumeMlMin", ge=0)] = None,
    volume_ml_max: Annotated[int | None, Query(alias="volumeMlMax", ge=0)] = None,
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
) -> CatalogProductListResponse:
    items, total = list_catalog_products(
        db,
        q=q,
        category=category,
        flavor=flavor,
        volume_ml_min=volume_ml_min,
        volume_ml_max=volume_ml_max,
        offset=offset,
        limit=limit,
    )
    return CatalogProductListResponse(items=items, total=total)


@router.get("/{catalog_id}", response_model=CatalogProductDetailResponse)
def get_catalog_product_by_id(
    catalog_id: UUID,
    db: Annotated[Session, Depends(get_db)],
    flavor: str | None = None,
    volume_ml_min: Annotated[int | None, Query(alias="volumeMlMin", ge=0)] = None,
    volume_ml_max: Annotated[int | None, Query(alias="volumeMlMax", ge=0)] = None,
) -> CatalogProductDetailResponse:
    return get_catalog_product(
        db,
        catalog_id,
        flavor=flavor,
        volume_ml_min=volume_ml_min,
        volume_ml_max=volume_ml_max,
    )
