from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator

from app.schemas.seller import SellerSummary

PriceUnit = Literal["ml", "credits"]


class CatalogProductListItem(BaseModel):
    id: str
    title: str
    manufacturer: str = ""
    category: str
    category_major: str | None = Field(default=None, alias="categoryMajor")
    category_mid: str | None = Field(default=None, alias="categoryMid")
    description: str | None = None
    image_url: str | None = Field(default=None, alias="imageUrl")
    volume_options: list[str] = Field(default_factory=list, alias="volumeOptions")
    offer_count: int = Field(alias="offerCount")
    median_unit_price: float | None = Field(default=None, alias="medianUnitPrice")
    median_price_credits: int | None = Field(default=None, alias="medianPriceCredits")
    price_unit: PriceUnit = Field(alias="priceUnit")
    display_price_label: str = Field(alias="displayPriceLabel")

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}

    @field_validator("id", mode="before")
    @classmethod
    def coerce_id(cls, value: UUID | str) -> str:
        return str(value)


class CatalogProductListResponse(BaseModel):
    items: list[CatalogProductListItem]
    total: int

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class CatalogOfferItem(BaseModel):
    id: str
    option_label: str | None = Field(default=None, alias="optionLabel")
    flavor: str | None = None
    volume_ml: int | None = Field(default=None, alias="volumeMl")
    price_credits: int = Field(alias="priceCredits")
    stock: int
    seller: SellerSummary

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}

    @field_validator("id", mode="before")
    @classmethod
    def coerce_id(cls, value: UUID | str) -> str:
        return str(value)


class CatalogProductDetailResponse(BaseModel):
    id: str
    title: str
    manufacturer: str = ""
    category: str
    category_major: str | None = Field(default=None, alias="categoryMajor")
    category_mid: str | None = Field(default=None, alias="categoryMid")
    description: str | None = None
    image_url: str | None = Field(default=None, alias="imageUrl")
    volume_options: list[str] = Field(default_factory=list, alias="volumeOptions")
    offer_count: int = Field(alias="offerCount")
    offers: list[CatalogOfferItem]
    created_at: datetime | None = Field(default=None, alias="createdAt")

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}

    @field_validator("id", mode="before")
    @classmethod
    def coerce_id(cls, value: UUID | str) -> str:
        return str(value)


class CatalogImportResponse(BaseModel):
    source_rows: int = Field(alias="sourceRows")
    upserted: int

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}
