from typing import Annotated

from uuid import UUID



from fastapi import APIRouter, Depends, Query, status

from sqlalchemy.orm import Session



from app.database import get_db

from app.deps import get_current_user, require_active_seller

from app.models import Seller, User

from app.schemas.catalog_product import CatalogProductListResponse
from app.schemas.product import ProductResponse

from app.schemas.seller import (

    SellerApplyRequest,

    SellerOrderItemListResponse,

    SellerOrderItemResponse,

    SellerOrderItemStatusUpdate,

    SellerProductCreateRequest,

    SellerProductUpdateRequest,

    SellerResponse,

)

from app.services.catalog_products import search_seller_catalog_products
from app.services.products import (

    archive_seller_product,

    create_seller_product,

    list_seller_products,

    product_to_response,

    update_seller_product,

)

from app.services.seller_orders import (

    list_seller_order_items,

    update_seller_order_item_status,

)

from app.services.seller_orders import _seller_order_item_response

from app.services.sellers import apply_for_seller, get_seller_for_user



router = APIRouter(prefix="/seller", tags=["seller"])





@router.post("/apply", response_model=SellerResponse, status_code=status.HTTP_201_CREATED)

def seller_apply(

    payload: SellerApplyRequest,

    db: Annotated[Session, Depends(get_db)],

    current_user: Annotated[User, Depends(get_current_user)],

) -> SellerResponse:

    seller = apply_for_seller(db, current_user, payload.shop_name)

    db.commit()

    db.refresh(seller)

    return SellerResponse.model_validate(seller)





@router.get("/me", response_model=SellerResponse | None)

def seller_me(

    db: Annotated[Session, Depends(get_db)],

    current_user: Annotated[User, Depends(get_current_user)],

) -> SellerResponse | None:

    seller = get_seller_for_user(db, current_user)

    if seller is None:

        return None

    return SellerResponse.model_validate(seller)





@router.get("/catalog-products", response_model=CatalogProductListResponse)

def seller_search_catalog_products(

    db: Annotated[Session, Depends(get_db)],

    seller: Annotated[Seller, Depends(require_active_seller)],

    q: Annotated[str | None, Query()] = None,

    category: Annotated[str | None, Query()] = None,

    offset: Annotated[int, Query(ge=0)] = 0,

    limit: Annotated[int, Query(ge=1, le=50)] = 30,

) -> CatalogProductListResponse:

    if not (q or "").strip() and not (category or "").strip():

        return CatalogProductListResponse(items=[], total=0)

    items, total = search_seller_catalog_products(

        db, q=q, category=category, offset=offset, limit=limit

    )

    return CatalogProductListResponse(items=items, total=total)





@router.get("/products", response_model=list[ProductResponse])

def seller_list_products(

    db: Annotated[Session, Depends(get_db)],

    seller: Annotated[Seller, Depends(require_active_seller)],

) -> list[ProductResponse]:

    products = list_seller_products(db, seller)

    return [product_to_response(p) for p in products]





@router.post("/products", response_model=ProductResponse, status_code=status.HTTP_201_CREATED)

def seller_create_product(

    payload: SellerProductCreateRequest,

    db: Annotated[Session, Depends(get_db)],

    seller: Annotated[Seller, Depends(require_active_seller)],

) -> ProductResponse:

    product = create_seller_product(db, seller, payload)

    db.commit()

    return product_to_response(product)





@router.patch("/products/{product_id}", response_model=ProductResponse)

def seller_update_product(

    product_id: UUID,

    payload: SellerProductUpdateRequest,

    db: Annotated[Session, Depends(get_db)],

    seller: Annotated[Seller, Depends(require_active_seller)],

) -> ProductResponse:

    product = update_seller_product(db, seller, product_id, payload)

    db.commit()

    return product_to_response(product)





@router.delete("/products/{product_id}", status_code=status.HTTP_204_NO_CONTENT)

def seller_delete_product(

    product_id: UUID,

    db: Annotated[Session, Depends(get_db)],

    seller: Annotated[Seller, Depends(require_active_seller)],

) -> None:

    archive_seller_product(db, seller, product_id)

    db.commit()





@router.get("/orders", response_model=SellerOrderItemListResponse)

def seller_list_orders(

    db: Annotated[Session, Depends(get_db)],

    seller: Annotated[Seller, Depends(require_active_seller)],

    offset: Annotated[int, Query(ge=0)] = 0,

    limit: Annotated[int, Query(ge=1, le=100)] = 50,

) -> SellerOrderItemListResponse:

    items, total = list_seller_order_items(db, seller, offset=offset, limit=limit)

    return SellerOrderItemListResponse(

        items=[_seller_order_item_response(item) for item in items],

        total=total,

    )





@router.patch("/orders/items/{item_id}/status", response_model=SellerOrderItemResponse)

def seller_update_order_item_status(

    item_id: UUID,

    payload: SellerOrderItemStatusUpdate,

    db: Annotated[Session, Depends(get_db)],

    seller: Annotated[Seller, Depends(require_active_seller)],

) -> SellerOrderItemResponse:

    item = update_seller_order_item_status(db, seller, item_id, payload)

    db.commit()

    return _seller_order_item_response(item)


