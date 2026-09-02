from pydantic import BaseModel, Field


class CreditBalanceResponse(BaseModel):
    balance: int

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class AdminCreditGrantRequest(BaseModel):
    amount: int
    note: str | None = None

    model_config = {"populate_by_name": True}


class AdminCreditGrantResponse(BaseModel):
    user_id: str = Field(alias="userId")
    balance: int
    granted: int

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}
