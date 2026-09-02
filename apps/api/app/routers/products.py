from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.product import ProductListResponse, ProductResponse
from app.services.products import get_public_product, list_public_products, product_to_response

router = APIRouter(prefix="/products", tags=["products"])


@router.get("", response_model=ProductListResponse)
def get_products(
    db: Annotated[Session, Depends(get_db)],
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
) -> ProductListResponse:
    products, total = list_public_products(db, offset=offset, limit=limit)
    return ProductListResponse(
        items=[product_to_response(p) for p in products],
        total=total,
    )


@router.get("/{product_id}", response_model=ProductResponse)
def get_product_by_id(
    product_id: UUID,
    db: Annotated[Session, Depends(get_db)],
) -> ProductResponse:
    product = get_public_product(db, product_id)
    return product_to_response(product)
