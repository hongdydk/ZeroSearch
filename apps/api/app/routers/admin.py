import logging
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session, joinedload

from app.config import get_settings
from app.database import get_db
from app.deps import require_admin
from app.models import Seller, User
from app.schemas.admin import (
    AdminCreditGrantRequest,
    AdminCreditGrantResponse,
    AdminSellerItem,
    AdminSellerListResponse,
    AdminStatsResponse,
    AdminUserItem,
    AdminUserListResponse,
    DbResetRequest,
    DbResetResponse,
)
from app.schemas.seller import (
    AdminOrderItemListResponse,
    AdminOrderItemResponse,
    SellerOrderItemStatusUpdate,
)
from app.schemas.catalog_product import (
    CatalogImportJobResponse,
    CatalogImportResponse,
    CatalogImportTextRequest,
)
from app.services.admin_db import RESET_CONFIRM, get_admin_stats, run_db_reset
from app.services.catalog_import import import_catalog_csv
from app.services.catalog_import_jobs import get_job, start_import_job
from app.services.credits import grant_credits
from app.services.seller_orders import (
    list_admin_order_items,
    update_admin_order_item_status,
)
from app.services.sellers import approve_seller, suspend_seller

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
) -> AdminUserListResponse:
    total = db.scalar(select(func.count()).select_from(User)) or 0
    users = db.scalars(
        select(User).order_by(User.created_at.desc()).offset(offset).limit(limit)
    ).all()

    return AdminUserListResponse(
        items=[
            AdminUserItem(
                id=str(user.id),
                email=user.email,
                display_name=user.display_name,
                is_admin=user.is_admin,
                created_at=user.created_at,
            )
            for user in users
        ],
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

    return AdminUserItem(
        id=str(user.id),
        email=user.email,
        display_name=user.display_name,
        is_admin=user.is_admin,
        created_at=user.created_at,
    )


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
    query = select(Seller).options(joinedload(Seller.user))
    if status_filter:
        query = query.where(Seller.status == status_filter)
    sellers = db.scalars(query.order_by(Seller.created_at.desc())).unique().all()
    items = [
        AdminSellerItem(
            id=str(seller.id),
            user_id=str(seller.user_id),
            user_email=seller.user.email,
            shop_name=seller.shop_name,
            slug=seller.slug,
            status=seller.status,  # type: ignore[arg-type]
            seller_type=seller.seller_type,  # type: ignore[arg-type]
            created_at=seller.created_at,
        )
        for seller in sellers
    ]
    return AdminSellerListResponse(items=items, total=len(items))


@router.post("/sellers/{seller_id}/approve", response_model=AdminSellerItem)
def approve_seller_endpoint(
    seller_id: UUID,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
) -> AdminSellerItem:
    seller = approve_seller(db, seller_id)
    db.commit()
    db.refresh(seller)
    user = db.get(User, seller.user_id)
    logger.warning("Admin %s approved seller %s", admin.email, seller.shop_name)
    return AdminSellerItem(
        id=str(seller.id),
        user_id=str(seller.user_id),
        user_email=user.email if user else "",
        shop_name=seller.shop_name,
        slug=seller.slug,
        status=seller.status,  # type: ignore[arg-type]
        seller_type=seller.seller_type,  # type: ignore[arg-type]
        created_at=seller.created_at,
    )


@router.post("/sellers/{seller_id}/suspend", response_model=AdminSellerItem)
def suspend_seller_endpoint(
    seller_id: UUID,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
) -> AdminSellerItem:
    seller = suspend_seller(db, seller_id)
    db.commit()
    db.refresh(seller)
    user = db.get(User, seller.user_id)
    logger.warning("Admin %s suspended seller %s", admin.email, seller.shop_name)
    return AdminSellerItem(
        id=str(seller.id),
        user_id=str(seller.user_id),
        user_email=user.email if user else "",
        shop_name=seller.shop_name,
        slug=seller.slug,
        status=seller.status,  # type: ignore[arg-type]
        seller_type=seller.seller_type,  # type: ignore[arg-type]
        created_at=seller.created_at,
    )


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
