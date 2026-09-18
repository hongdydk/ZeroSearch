import logging
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from sqlalchemy.orm import Session

from app.config import get_settings
from app.database import get_db
from app.deps import require_admin
from app.models import User
from app.schemas.admin import (
    AdminCatalogCreateRequest,
    AdminCatalogProductItem,
    AdminCatalogProductListResponse,
    AdminCreditGrantRequest,
    AdminCreditGrantResponse,
    AdminSellerItem,
    AdminSellerListResponse,
    AdminSellerModerationRequest,
    AdminStatsResponse,
    AdminUserItem,
    AdminUserListResponse,
    AdminUserUpdate,
    DbResetRequest,
    DbResetResponse,
    SellerModerationEventListResponse,
)
from app.schemas.seller import (
    AdminOrderItemListResponse,
    AdminOrderItemResponse,
    SellerOrderItemStatusUpdate,
)
from app.schemas.catalog_intake import (
    AdminAttachDraftRequest,
    AdminPromoteDraftRequest,
    CatalogIntakeItem,
    CatalogIntakeListResponse,
)
from app.schemas.catalog_product import (
    CatalogImportJobResponse,
    CatalogImportResponse,
    CatalogImportTextRequest,
)
from app.services.admin_catalog import (
    create_admin_catalog_product,
    list_admin_catalog_products,
    retire_catalog_product,
)
from app.services.admin_db import RESET_CONFIRM, get_admin_stats, run_db_reset
from app.services.admin_users import (
    admin_user_item,
    count_admins,
    delete_user_account,
    list_admin_users,
    update_admin_user,
)
from app.services.catalog_import import import_catalog_csv
from app.services.catalog_import_jobs import get_job, start_import_job
from app.services.catalog_intake import attach_intake_draft, list_admin_intake_queue, promote_card_draft
from app.services.credits import grant_credits
from app.services.seller_orders import (
    list_admin_order_items,
    update_admin_order_item_status,
)
from app.services.sellers import (
    admin_seller_item,
    approve_seller,
    list_admin_sellers,
    list_moderation_events,
    moderation_event_item,
    _moderation_summaries,
    remove_seller,
    suspend_seller,
    unsuspend_seller,
    warn_seller,
)

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/stats", response_model=AdminStatsResponse)
def admin_stats(
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
) -> AdminStatsResponse:
    stats = get_admin_stats(db)
    return AdminStatsResponse(**stats)


_MAX_CATALOG_CSV_BYTES = 4 * 1024 * 1024


@router.post("/catalog/import", response_model=CatalogImportResponse)
async def import_catalog(
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
    file: Annotated[UploadFile, File()],
) -> CatalogImportResponse:
    if not (file.filename or "").lower().endswith(".csv"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="CSV 파일만 올릴 수 있습니다.")
    content = await file.read()
    if not content:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="빈 파일입니다.")
    if len(content) > _MAX_CATALOG_CSV_BYTES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="파일이 너무 큽니다. data/aihub-catalog.csv만 올리세요.",
        )
    result = import_catalog_csv(db, content)
    db.commit()
    return CatalogImportResponse(**result)


@router.post("/catalog/import-text", response_model=CatalogImportResponse)
def import_catalog_text(
    payload: CatalogImportTextRequest,
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
) -> CatalogImportResponse:
    result = import_catalog_csv(db, payload.csv.encode("utf-8"))
    db.commit()
    return CatalogImportResponse(**result)


@router.post("/catalog/import-jobs", response_model=CatalogImportJobResponse)
def create_catalog_import_job(
    payload: CatalogImportTextRequest,
    _: Annotated[User, Depends(require_admin)],
) -> CatalogImportJobResponse:
    return CatalogImportJobResponse(**start_import_job(payload.csv))


@router.get("/catalog/import-jobs/{job_id}", response_model=CatalogImportJobResponse)
def read_catalog_import_job(
    job_id: UUID,
    _: Annotated[User, Depends(require_admin)],
) -> CatalogImportJobResponse:
    job = get_job(str(job_id))
    if job is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="가져오기 작업을 찾을 수 없습니다.")
    return CatalogImportJobResponse(**job)


@router.get("/users", response_model=AdminUserListResponse)
def list_users(
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    q: Annotated[str | None, Query(max_length=100)] = None,
) -> AdminUserListResponse:
    users, total = list_admin_users(db, offset=offset, limit=limit, q=q)
    return AdminUserListResponse(
        items=[admin_user_item(user) for user in users],
        total=total,
        offset=offset,
        limit=limit,
    )


@router.post("/users/{user_id}/promote", response_model=AdminUserItem)
def promote_user(
    user_id: UUID,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
) -> AdminUserItem:
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="사용자를 찾을 수 없습니다.")

    if user.is_admin:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="이미 관리자입니다.")

    user.is_admin = True
    db.commit()
    db.refresh(user)
    logger.warning("Admin %s promoted user %s to admin", admin.email, user.email)

    return admin_user_item(user)


@router.patch("/users/{user_id}", response_model=AdminUserItem)
def update_user(
    user_id: UUID,
    payload: AdminUserUpdate,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
) -> AdminUserItem:
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="사용자를 찾을 수 없습니다.")
    update_admin_user(db, user, admin, payload)
    db.commit()
    db.refresh(user)
    logger.warning(
        "Admin %s updated user %s is_admin=%s is_buyer=%s is_seller=%s",
        admin.email,
        user.email,
        user.is_admin,
        getattr(user, "is_buyer", True),
        getattr(getattr(user, "seller", None), "status", None),
    )
    return admin_user_item(user)


@router.delete("/users/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_user(
    user_id: UUID,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
) -> None:
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="사용자를 찾을 수 없습니다.")
    if user.id == admin.id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="자기 자신은 삭제할 수 없습니다.")
    if user.is_admin and count_admins(db) <= 1:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="마지막 관리자는 삭제할 수 없습니다.",
        )
    delete_user_account(db, user)
    db.commit()
    logger.warning("Admin %s deleted user %s", admin.email, user.email)


@router.post("/users/{user_id}/credits", response_model=AdminCreditGrantResponse)
def grant_user_credits(
    user_id: UUID,
    payload: AdminCreditGrantRequest,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
) -> AdminCreditGrantResponse:
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="사용자를 찾을 수 없습니다.")

    wallet = grant_credits(db, user, payload.amount, note=payload.note)
    db.commit()
    logger.info("Admin %s granted %s credits to user %s", admin.email, payload.amount, user.email)

    return AdminCreditGrantResponse(
        user_id=str(user.id),
        balance=wallet.balance,
        granted=payload.amount,
    )


@router.post("/db/reset", response_model=DbResetResponse)
def reset_database(
    payload: DbResetRequest,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
) -> DbResetResponse:
    settings = get_settings()

    if payload.confirm != RESET_CONFIRM:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='확인 문자열이 올바르지 않습니다. "RESET"을 입력하세요.',
        )

    if not settings.allow_db_reset:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="DB 초기화가 비활성화되어 있습니다. ALLOW_DB_RESET=true 로 설정하세요.",
        )

    logger.warning("Admin %s requested db reset mode=%s", admin.email, payload.mode)
    message = run_db_reset(db, payload.mode)
    logger.warning("Admin %s completed db reset mode=%s", admin.email, payload.mode)

    return DbResetResponse(mode=payload.mode, message=message)


@router.get("/sellers", response_model=AdminSellerListResponse)
def list_sellers(
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
    status_filter: Annotated[str | None, Query(alias="status")] = None,
) -> AdminSellerListResponse:
    rows = list_admin_sellers(db, status_filter)
    summaries = _moderation_summaries(db, [seller.id for seller, _ in rows])
    items = [
        admin_seller_item(seller, user, summaries.get(seller.id))
        for seller, user in rows
    ]
    return AdminSellerListResponse(items=items, total=len(items))


def _seller_item_after_action(db: Session, seller) -> AdminSellerItem:
    user = db.get(User, seller.user_id)
    summaries = _moderation_summaries(db, [seller.id])
    return admin_seller_item(seller, user, summaries.get(seller.id))


@router.post("/sellers/{seller_id}/approve", response_model=AdminSellerItem)
def approve_seller_endpoint(
    seller_id: UUID,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
) -> AdminSellerItem:
    seller = approve_seller(db, seller_id)
    db.commit()
    db.refresh(seller)
    logger.warning("Admin %s approved seller %s", admin.email, seller.shop_name)
    return _seller_item_after_action(db, seller)


@router.post("/sellers/{seller_id}/warn", response_model=AdminSellerItem)
def warn_seller_endpoint(
    seller_id: UUID,
    payload: AdminSellerModerationRequest,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
) -> AdminSellerItem:
    seller = warn_seller(db, seller_id, admin, payload.reason)
    db.commit()
    db.refresh(seller)
    logger.warning("Admin %s warned seller %s", admin.email, seller.shop_name)
    return _seller_item_after_action(db, seller)


@router.post("/sellers/{seller_id}/suspend", response_model=AdminSellerItem)
def suspend_seller_endpoint(
    seller_id: UUID,
    payload: AdminSellerModerationRequest,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
) -> AdminSellerItem:
    seller = suspend_seller(db, seller_id, admin, payload.reason)
    db.commit()
    db.refresh(seller)
    logger.warning("Admin %s suspended seller %s", admin.email, seller.shop_name)
    return _seller_item_after_action(db, seller)


@router.post("/sellers/{seller_id}/unsuspend", response_model=AdminSellerItem)
def unsuspend_seller_endpoint(
    seller_id: UUID,
    payload: AdminSellerModerationRequest,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
) -> AdminSellerItem:
    seller = unsuspend_seller(db, seller_id, admin, payload.reason)
    db.commit()
    db.refresh(seller)
    logger.warning("Admin %s unsuspended seller %s", admin.email, seller.shop_name)
    return _seller_item_after_action(db, seller)


@router.post("/sellers/{seller_id}/remove", response_model=AdminSellerItem)
def remove_seller_endpoint(
    seller_id: UUID,
    payload: AdminSellerModerationRequest,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
) -> AdminSellerItem:
    seller = remove_seller(db, seller_id, admin, payload.reason)
    db.commit()
    db.refresh(seller)
    logger.warning("Admin %s removed seller %s", admin.email, seller.shop_name)
    return _seller_item_after_action(db, seller)


@router.get("/sellers/{seller_id}/moderation", response_model=SellerModerationEventListResponse)
def list_seller_moderation(
    seller_id: UUID,
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
) -> SellerModerationEventListResponse:
    events = list_moderation_events(db, seller_id)
    admin_ids = {event.admin_user_id for event in events if event.admin_user_id}
    emails = {}
    for admin_id in admin_ids:
        user = db.get(User, admin_id)
        if user is not None:
            emails[admin_id] = user.email
    items = [
        moderation_event_item(event, emails.get(event.admin_user_id) if event.admin_user_id else None)
        for event in events
    ]
    return SellerModerationEventListResponse(items=items, total=len(items))


def _admin_order_item_response(item) -> AdminOrderItemResponse:
    return AdminOrderItemResponse(
        id=str(item.id),
        order_id=str(item.order_id),
        product_id=str(item.product_id),
        product_title=item.product_title,
        qty=item.qty,
        unit_price_credits=item.unit_price_credits,
        line_total_credits=item.unit_price_credits * item.qty,
        fulfillment_status=item.fulfillment_status,  # type: ignore[arg-type]
        created_at=item.order.created_at if item.order else None,
        shop_name=item.seller.shop_name if item.seller else "",
        seller_type=item.seller.seller_type if item.seller else "merchant",  # type: ignore[arg-type]
    )


@router.get("/catalog/drafts", response_model=CatalogIntakeListResponse)
def list_catalog_drafts(
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
) -> CatalogIntakeListResponse:
    items, total = list_admin_intake_queue(db, offset=offset, limit=limit)
    return CatalogIntakeListResponse(items=items, total=total)


@router.post("/catalog/drafts/{draft_id}/attach", response_model=CatalogIntakeItem)
def attach_catalog_draft(
    draft_id: UUID,
    payload: AdminAttachDraftRequest,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
) -> CatalogIntakeItem:
    item = attach_intake_draft(db, draft_id, payload, admin)
    db.commit()
    logger.info("Admin %s attached catalog draft %s kind=%s", admin.email, draft_id, payload.kind)
    return item


@router.post("/catalog/drafts/{draft_id}/promote", response_model=CatalogIntakeItem)
def promote_catalog_draft(
    draft_id: UUID,
    payload: AdminPromoteDraftRequest,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
) -> CatalogIntakeItem:
    item = promote_card_draft(db, draft_id, payload, admin)
    db.commit()
    logger.info("Admin %s promoted catalog draft %s", admin.email, draft_id)
    return item


@router.get("/catalog/products", response_model=AdminCatalogProductListResponse)
def list_admin_catalog(
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
    q: Annotated[str | None, Query(max_length=100)] = None,
    include_retired: Annotated[bool, Query(alias="includeRetired")] = False,
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
) -> AdminCatalogProductListResponse:
    items, total = list_admin_catalog_products(
        db, q=q, include_retired=include_retired, offset=offset, limit=limit
    )
    return AdminCatalogProductListResponse(items=items, total=total)


@router.post("/catalog/products", response_model=AdminCatalogProductItem, status_code=status.HTTP_201_CREATED)
def create_admin_catalog(
    payload: AdminCatalogCreateRequest,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
) -> AdminCatalogProductItem:
    item = create_admin_catalog_product(db, payload)
    db.commit()
    logger.info("Admin %s created catalog %s / %s", admin.email, payload.manufacturer, payload.title)
    return item


@router.delete("/catalog/products/{catalog_id}", response_model=AdminCatalogProductItem)
def delete_admin_catalog(
    catalog_id: UUID,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
) -> AdminCatalogProductItem:
    item = retire_catalog_product(db, catalog_id)
    db.commit()
    logger.warning("Admin %s retired catalog %s", admin.email, catalog_id)
    return item


@router.get("/orders", response_model=AdminOrderItemListResponse)
def list_admin_orders(
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
) -> AdminOrderItemListResponse:
    items, total = list_admin_order_items(db, offset=offset, limit=limit)
    return AdminOrderItemListResponse(
        items=[_admin_order_item_response(item) for item in items],
        total=total,
    )


@router.patch("/orders/items/{item_id}/status", response_model=AdminOrderItemResponse)
def admin_update_order_item_status(
    item_id: UUID,
    payload: SellerOrderItemStatusUpdate,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
) -> AdminOrderItemResponse:
    item = update_admin_order_item_status(db, item_id, payload)
    db.commit()
    logger.info(
        "Admin %s updated order item %s to %s",
        admin.email,
        item_id,
        payload.fulfillment_status,
    )
    return _admin_order_item_response(item)
