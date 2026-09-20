from typing import Annotated

from uuid import UUID



from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from fastapi.responses import Response

from sqlalchemy.orm import Session



from app.config import get_settings
from app.database import get_db

from app.deps import get_current_user, require_active_seller

from app.models import Seller, User

from app.schemas.catalog_intake import (
    CatalogIntakeItem,
    CatalogIntakeListResponse,
    SellerCardDraftCreateRequest,
    SellerCardDraftUpdateRequest,
)
from app.schemas.catalog_product import CatalogImportResponse, CatalogProductListResponse
from app.schemas.product import ProductResponse, SellerProductBulkResponse, SellerProductListResponse

from app.schemas.seller import (

    SellerApplyRequest,

    SellerOfferFilter,

    SellerOfferSort,

    SellerOrderItemListResponse,

    SellerOrderItemResponse,

    SellerOrderItemStatusUpdate,

    SellerProductBulkRequest,

    SellerProductCreateRequest,

    SellerProductUpdateRequest,
    SellerStorefrontUpdateRequest,
    SellerStorefrontLayoutRequest,

    SellerImageUploadResponse,

    SellerResponse,
    SalesStatsResponse,

)
from app.schemas.admin import SellerModerationEventListResponse

from app.services.catalog_intake import (
    card_draft_to_item,
    create_card_draft,
    list_seller_card_drafts,
    update_card_draft,
)
from app.services.uploads import save_seller_image
from app.services.catalog_products import search_seller_catalog_products
from app.services.products import (

    delete_seller_product,

    bulk_update_seller_products,

    create_seller_product,

    get_seller_product,

    list_seller_products,

    product_to_response,

    update_seller_product,
    update_seller_storefront_layout,

)

from app.services.seller_orders import (

    list_seller_order_items,

    update_seller_order_item_status,

)

from app.services.seller_orders import _seller_order_item_response

from app.services.sellers import apply_for_seller, get_seller_for_user, list_moderation_events, moderation_event_item
from app.services.sales_stats import get_sales_stats
from app.services.storefront_product_import import (
    export_storefront_product_csv,
    import_storefront_product_csv,
    storefront_product_template_csv,
)



router = APIRouter(prefix="/seller", tags=["seller"])

_MAX_STOREFRONT_CSV_BYTES = 4 * 1024 * 1024


@router.get("/stats", response_model=SalesStatsResponse)
def seller_stats(
    db: Annotated[Session, Depends(get_db)],
    seller: Annotated[Seller, Depends(require_active_seller)],
) -> SalesStatsResponse:
    return SalesStatsResponse(**get_sales_stats(db, seller_id=seller.id))





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


@router.patch("/storefront", response_model=SellerResponse)
def update_seller_storefront(
    payload: SellerStorefrontUpdateRequest,
    db: Annotated[Session, Depends(get_db)],
    seller: Annotated[Seller, Depends(require_active_seller)],
) -> SellerResponse:
    seller.store_description = (payload.store_description or "").strip() or None
    seller.store_logo_url = (payload.store_logo_url or "").strip() or None
    seller.store_banner_url = (payload.store_banner_url or "").strip() or None
    db.commit()
    db.refresh(seller)
    return SellerResponse.model_validate(seller)


@router.post("/storefront/products/import", response_model=CatalogImportResponse)
async def import_seller_storefront_products(
    file: Annotated[UploadFile, File()],
    db: Annotated[Session, Depends(get_db)],
    seller: Annotated[Seller, Depends(require_active_seller)],
) -> CatalogImportResponse:
    if not (file.filename or "").lower().endswith(".csv"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="CSV 파일만 올릴 수 있습니다.")
    content = await file.read()
    if not content:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="빈 파일입니다.")
    if len(content) > _MAX_STOREFRONT_CSV_BYTES:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="파일이 너무 큽니다. 4MB 이하 CSV를 올리세요.")
    result = import_storefront_product_csv(db, seller, content)
    db.commit()
    return CatalogImportResponse(**result)


@router.get("/storefront/products/export", response_class=Response)
def export_seller_storefront_products(
    db: Annotated[Session, Depends(get_db)],
    seller: Annotated[Seller, Depends(require_active_seller)],
) -> Response:
    return Response(content=export_storefront_product_csv(db, seller), media_type="text/csv; charset=utf-8", headers={"Content-Disposition": 'attachment; filename="my-storefront-products.csv"'})


@router.get("/storefront/products/export/template", response_class=Response)
def export_seller_storefront_products_template(
    _: Annotated[Seller, Depends(require_active_seller)],
) -> Response:
    return Response(content=storefront_product_template_csv(), media_type="text/csv; charset=utf-8", headers={"Content-Disposition": 'attachment; filename="my-storefront-products-template.csv"'})


@router.put("/storefront/products", status_code=status.HTTP_204_NO_CONTENT)
def update_seller_storefront_products(
    payload: SellerStorefrontLayoutRequest,
    db: Annotated[Session, Depends(get_db)],
    seller: Annotated[Seller, Depends(require_active_seller)],
) -> None:
    update_seller_storefront_layout(
        db,
        seller,
        product_ids=payload.product_ids,
        featured_product_ids=payload.featured_product_ids,
    )
    db.commit()


@router.get("/moderation-events", response_model=SellerModerationEventListResponse)
def seller_moderation_events(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> SellerModerationEventListResponse:
    seller = get_seller_for_user(db, current_user)
    if seller is None:
        return SellerModerationEventListResponse(items=[], total=0)
    events = list_moderation_events(db, seller.id)
    items = [moderation_event_item(event) for event in events]
    return SellerModerationEventListResponse(items=items, total=len(items))





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





@router.get("/products", response_model=SellerProductListResponse)

def seller_list_products(

    db: Annotated[Session, Depends(get_db)],

    seller: Annotated[Seller, Depends(require_active_seller)],

    q: Annotated[str | None, Query()] = None,

    offer_filter: Annotated[SellerOfferFilter, Query(alias="filter")] = "all",

    sort: Annotated[SellerOfferSort, Query()] = "newest",

    offset: Annotated[int, Query(ge=0)] = 0,

    limit: Annotated[int, Query(ge=1, le=100)] = 20,

) -> SellerProductListResponse:

    products, total, counts = list_seller_products(

        db,

        seller,

        q=q,

        offer_filter=offer_filter,

        sort=sort,

        offset=offset,

        limit=limit,

    )

    return SellerProductListResponse(

        items=[product_to_response(p) for p in products],

        total=total,

        counts=counts,

    )


@router.post("/products/bulk", response_model=SellerProductBulkResponse)
def seller_bulk_update_products(
    payload: SellerProductBulkRequest,
    db: Annotated[Session, Depends(get_db)],
    seller: Annotated[Seller, Depends(require_active_seller)],
) -> SellerProductBulkResponse:
    updated, failed = bulk_update_seller_products(db, seller, payload)
    db.commit()
    return SellerProductBulkResponse(
        updated=[product_to_response(p) for p in updated],
        failed=failed,
        success_count=len(updated),
        fail_count=len(failed),
    )


@router.get("/products/{product_id}", response_model=ProductResponse)
def seller_get_product(
    product_id: UUID,
    db: Annotated[Session, Depends(get_db)],
    seller: Annotated[Seller, Depends(require_active_seller)],
) -> ProductResponse:
    product = get_seller_product(db, seller, product_id)
    return product_to_response(product)





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

    delete_seller_product(db, seller, product_id)

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


@router.get("/card-drafts", response_model=CatalogIntakeListResponse)
def seller_list_card_drafts(
    db: Annotated[Session, Depends(get_db)],
    seller: Annotated[Seller, Depends(require_active_seller)],
) -> CatalogIntakeListResponse:
    drafts = list_seller_card_drafts(db, seller)
    return CatalogIntakeListResponse(items=[card_draft_to_item(d) for d in drafts], total=len(drafts))


@router.post("/card-drafts", response_model=CatalogIntakeItem, status_code=status.HTTP_201_CREATED)
def seller_create_card_draft(
    payload: SellerCardDraftCreateRequest,
    db: Annotated[Session, Depends(get_db)],
    seller: Annotated[Seller, Depends(require_active_seller)],
) -> CatalogIntakeItem:
    draft = create_card_draft(db, seller, payload)
    db.commit()
    return card_draft_to_item(draft)


@router.patch("/card-drafts/{draft_id}", response_model=CatalogIntakeItem)
def seller_update_card_draft(
    draft_id: UUID,
    payload: SellerCardDraftUpdateRequest,
    db: Annotated[Session, Depends(get_db)],
    seller: Annotated[Seller, Depends(require_active_seller)],
) -> CatalogIntakeItem:
    draft = update_card_draft(db, seller, draft_id, payload)
    db.commit()
    return card_draft_to_item(draft)


@router.post("/uploads/image", response_model=SellerImageUploadResponse, status_code=status.HTTP_201_CREATED)
def seller_upload_image(
    seller: Annotated[Seller, Depends(require_active_seller)],
    file: Annotated[UploadFile, File()],
) -> SellerImageUploadResponse:
    image_url = save_seller_image(file, get_settings())
    return SellerImageUploadResponse(image_url=image_url)


