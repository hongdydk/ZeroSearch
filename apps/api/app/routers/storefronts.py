from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import and_, case, func, select
from sqlalchemy.orm import Session, joinedload

from app.database import get_db
from app.models import Product, Seller
from app.schemas.storefront import StorefrontDetailResponse, StorefrontItem, StorefrontListResponse
from app.services.products import product_to_response

router = APIRouter(prefix="/stores", tags=["storefronts"])


def _storefront_item(seller: Seller, product_count: int) -> StorefrontItem:
    return StorefrontItem(
        id=str(seller.id), shop_name=seller.shop_name, slug=seller.slug,
        seller_type=seller.seller_type, product_count=product_count,
    )


@router.get("", response_model=StorefrontListResponse)
def list_storefronts(
    db: Annotated[Session, Depends(get_db)],
) -> StorefrontListResponse:
    rows = db.execute(
        select(Seller, func.count(Product.id))
        .outerjoin(
            Product,
            and_(Product.seller_id == Seller.id, Product.status == "published"),
        )
        .where(Seller.status == "active")
        .group_by(Seller.id)
        .order_by(case((Seller.seller_type == "platform", 0), else_=1), Seller.shop_name)
    ).all()
    items = [_storefront_item(seller, int(product_count)) for seller, product_count in rows]
    return StorefrontListResponse(items=items, total=len(items))


@router.get("/{slug}", response_model=StorefrontDetailResponse)
def get_storefront(
    slug: str,
    db: Annotated[Session, Depends(get_db)],
) -> StorefrontDetailResponse:
    seller = db.scalar(select(Seller).where(Seller.slug == slug, Seller.status == "active"))
    if seller is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="판매자 사이트를 찾을 수 없습니다.")
    products = list(
        db.scalars(
            select(Product)
            .where(Product.seller_id == seller.id, Product.status == "published")
            .options(joinedload(Product.seller))
            .order_by(Product.created_at.desc())
        ).all()
    )
    return StorefrontDetailResponse(
        **_storefront_item(seller, len(products)).model_dump(),
        products=[product_to_response(product) for product in products],
    )
