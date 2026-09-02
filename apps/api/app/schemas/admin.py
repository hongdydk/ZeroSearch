from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class AdminStatsResponse(BaseModel):
    user_count: int = Field(alias="userCount")
    product_count: int = Field(alias="productCount")
    order_count: int = Field(alias="orderCount")
    seller_count: int = Field(alias="sellerCount")
    pending_seller_count: int = Field(alias="pendingSellerCount")

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class AdminUserItem(BaseModel):
    id: str
    email: str
    display_name: str | None = Field(default=None, alias="displayName")
    is_admin: bool = Field(alias="isAdmin")
    created_at: datetime = Field(alias="createdAt")

    model_config = {"populate_by_name": True, "from_attributes": True, "ser_json_by_alias": True}


class AdminUserListResponse(BaseModel):
    items: list[AdminUserItem]
    total: int
    offset: int
    limit: int

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


DbResetMode = Literal["seed", "truncate_all", "truncate_except_users"]


class DbResetRequest(BaseModel):
    mode: DbResetMode = "seed"
    confirm: str

    model_config = {"populate_by_name": True}


class DbResetResponse(BaseModel):
    mode: DbResetMode
    message: str

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class AdminCreditGrantRequest(BaseModel):
    amount: int = Field(gt=0)
    note: str | None = None

    model_config = {"populate_by_name": True}


class AdminCreditGrantResponse(BaseModel):
    user_id: str = Field(alias="userId")
    balance: int
    granted: int

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class AdminSellerItem(BaseModel):
    id: str
    user_id: str = Field(alias="userId")
    user_email: str = Field(alias="userEmail")
    shop_name: str = Field(alias="shopName")
    slug: str
    status: str
    seller_type: str = Field(alias="sellerType")
    created_at: datetime = Field(alias="createdAt")

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class AdminSellerListResponse(BaseModel):
    items: list[AdminSellerItem]
    total: int

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}
