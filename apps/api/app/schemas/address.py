from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field, field_validator


def _digits_only(value: str) -> str:
    return "".join(ch for ch in value if ch.isdigit())


class ShippingSnapshot(BaseModel):
    recipient_name: str = Field(alias="recipientName")
    phone: str
    zonecode: str
    address: str
    detail_address: str = Field(alias="detailAddress")

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class ShippingAddressResponse(ShippingSnapshot):
    id: str
    is_default: bool = Field(alias="isDefault")
    created_at: datetime | None = Field(default=None, alias="createdAt")

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class ShippingAddressListResponse(BaseModel):
    items: list[ShippingAddressResponse]

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class ShippingAddressCreateRequest(BaseModel):
    recipient_name: str = Field(alias="recipientName", min_length=1, max_length=50)
    phone: str = Field(min_length=8, max_length=20)
    zonecode: str = Field(min_length=4, max_length=10)
    address: str = Field(min_length=1, max_length=200)
    detail_address: str = Field(alias="detailAddress", min_length=1, max_length=100)
    is_default: bool = Field(default=False, alias="isDefault")

    model_config = {"populate_by_name": True}

    @field_validator("phone")
    @classmethod
    def phone_digits(cls, value: str) -> str:
        digits = _digits_only(value)
        if not 8 <= len(digits) <= 15:
            raise ValueError("휴대폰 번호는 숫자 8~15자리여야 합니다.")
        return digits

    @field_validator("zonecode")
    @classmethod
    def zonecode_digits(cls, value: str) -> str:
        digits = _digits_only(value)
        if not 4 <= len(digits) <= 10:
            raise ValueError("우편번호가 올바르지 않습니다.")
        return digits

    @field_validator("recipient_name", "address", "detail_address")
    @classmethod
    def strip_text(cls, value: str) -> str:
        text = value.strip()
        if not text:
            raise ValueError("필수 항목입니다.")
        return text


class ShippingAddressUpdateRequest(BaseModel):
    recipient_name: str | None = Field(default=None, alias="recipientName", min_length=1, max_length=50)
    phone: str | None = Field(default=None, min_length=8, max_length=20)
    zonecode: str | None = Field(default=None, min_length=4, max_length=10)
    address: str | None = Field(default=None, min_length=1, max_length=200)
    detail_address: str | None = Field(default=None, alias="detailAddress", min_length=1, max_length=100)
    is_default: bool | None = Field(default=None, alias="isDefault")

    model_config = {"populate_by_name": True}

    @field_validator("phone")
    @classmethod
    def phone_digits(cls, value: str | None) -> str | None:
        if value is None:
            return None
        return ShippingAddressCreateRequest.phone_digits(value)

    @field_validator("zonecode")
    @classmethod
    def zonecode_digits(cls, value: str | None) -> str | None:
        if value is None:
            return None
        return ShippingAddressCreateRequest.zonecode_digits(value)

    @field_validator("recipient_name", "address", "detail_address")
    @classmethod
    def strip_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        return ShippingAddressCreateRequest.strip_text(value)


class TossPrepareRequest(BaseModel):
    address_id: UUID = Field(alias="addressId")

    model_config = {"populate_by_name": True}
