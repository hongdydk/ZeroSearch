from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session, joinedload

from app.models import Product, Seller
from app.schemas.product import ProductResponse
from app.schemas.seller import SellerProductCreateRequest, SellerProductUpdateRequest, SellerSummary


def _product_response(product: Product) -> ProductResponse:
    return ProductResponse(
        id=str(product.id),
        title=product.title,
        description=product.description,
        price_credits=product.price_credits,
        stock=product.stock,
        category=product.category,
        image_url=product.image_url,
        status=product.status,  # type: ignore[arg-type]
        seller=SellerSummary(
            id=str(product.seller.id),
            shop_name=product.seller.shop_name,
            seller_type=product.seller.seller_type,  # type: ignore[arg-type]
        ),
        created_at=product.created_at,
    )


def list_public_products(db: Session, *, offset: int = 0, limit: int = 50) -> tuple[list[Product], int]:
    filters = (Product.status == "published", Seller.status == "active")
    total = (
        db.scalar(
            select(func.count())
            .select_from(Product)
            .join(Seller, Product.seller_id == Seller.id)
            .where(*filters)
        )
        or 0
    )
    products = db.scalars(
        select(Product)
        .join(Seller, Product.seller_id == Seller.id)
        .where(*filters)
        .options(joinedload(Product.seller))
        .order_by(Product.created_at.desc())
        .offset(offset)
        .limit(limit)
    ).unique().all()
    return list(products), total


def get_public_product(db: Session, product_id: UUID) -> Product:
    product = db.scalar(
        select(Product)
        .join(Seller, Product.seller_id == Seller.id)
        .where(
            Product.id == product_id,
            Product.status == "published",
            Seller.status == "active",
        )
        .options(joinedload(Product.seller))
    )
    if product is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="상품을 찾을 수 없습니다.")
    return product


def list_seller_products(db: Session, seller: Seller) -> list[Product]:
    return list(
        db.scalars(
            select(Product)
            .where(Product.seller_id == seller.id, Product.status != "archived")
            .options(joinedload(Product.seller))
            .order_by(Product.created_at.desc())
        ).all()
    )


def get_seller_product(db: Session, seller: Seller, product_id: UUID) -> Product:
    product = db.scalar(
        select(Product)
        .where(Product.id == product_id, Product.seller_id == seller.id)
        .options(joinedload(Product.seller))
    )
    if product is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="상품을 찾을 수 없습니다.")
    return product


def create_seller_product(db: Session, seller: Seller, payload: SellerProductCreateRequest) -> Product:
    product = Product(
        seller_id=seller.id,
        title=payload.title,
        description=payload.description,
        price_credits=payload.price_credits,
        stock=payload.stock,
        category=payload.category,
        image_url=payload.image_url,
        status=payload.status,
    )
    db.add(product)
    db.flush()
    product = get_seller_product(db, seller, product.id)
    return product


def update_seller_product(
    db: Session, seller: Seller, product_id: UUID, payload: SellerProductUpdateRequest
) -> Product:
    product = get_seller_product(db, seller, product_id)
    if payload.title is not None:
        product.title = payload.title
    if payload.description is not None:
        product.description = payload.description
    if payload.price_credits is not None:
        product.price_credits = payload.price_credits
    if payload.stock is not None:
        product.stock = payload.stock
    if payload.category is not None:
        product.category = payload.category
    if payload.image_url is not None:
        product.image_url = payload.image_url
    if payload.status is not None:
        product.status = payload.status
    db.flush()
    return product


def archive_seller_product(db: Session, seller: Seller, product_id: UUID) -> None:
    product = get_seller_product(db, seller, product_id)
    product.status = "archived"
    db.flush()


def product_to_response(product: Product) -> ProductResponse:
    return _product_response(product)
