from pydantic import BaseModel, Field, field_validator
from uuid import UUID

from app.schemas.product import ProductResponse
from app.schemas.seller import SellerType


class StorefrontItem(BaseModel):
    id: str
    shop_name: str = Field(alias="shopName")
    slug: str
    seller_type: SellerType = Field(alias="sellerType")
    product_count: int = Field(alias="productCount")
    store_description: str | None = Field(default=None, alias="storeDescription")
    store_logo_url: str | None = Field(default=None, alias="storeLogoUrl")
    store_banner_url: str | None = Field(default=None, alias="storeBannerUrl")

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}

    @field_validator("id", mode="before")
    @classmethod
    def coerce_id(cls, value: UUID | str) -> str:
        return str(value)


class StorefrontListResponse(BaseModel):
    items: list[StorefrontItem]
    total: int

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class StorefrontDetailResponse(StorefrontItem):
    products: list[ProductResponse] = Field(default_factory=list)
