from pydantic import BaseModel, Field, field_validator

from app.schemas.seller import OfferUnit


class CatalogVariantCreateRequest(BaseModel):
    name: str = Field(default="기본", min_length=1, max_length=100)
    unit_amount: float = Field(alias="unitAmount", gt=0)
    unit: OfferUnit
    pack_count: int = Field(default=1, alias="packCount", ge=1)
    image_url: str | None = Field(default=None, alias="imageUrl", max_length=500)

    model_config = {"populate_by_name": True}

    @field_validator("name")
    @classmethod
    def strip_name(cls, value: str) -> str:
        result = value.strip()
        if not result:
            raise ValueError("옵션명을 입력하세요.")
        return result


class CatalogVariantItem(BaseModel):
    id: str
    name: str
    option_label: str = Field(alias="optionLabel")
    unit_amount: float = Field(alias="unitAmount")
    unit: str
    pack_count: int = Field(alias="packCount")
    image_url: str | None = Field(default=None, alias="imageUrl")

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class CatalogVariantsCreateRequest(BaseModel):
    variants: list[CatalogVariantCreateRequest] = Field(min_length=1, max_length=30)
