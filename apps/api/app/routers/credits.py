from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps import get_current_user
from app.models import User
from app.schemas.credit import CreditBalanceResponse
from app.services.credits import get_wallet_balance

router = APIRouter(prefix="/me", tags=["credits"])


@router.get("/credits", response_model=CreditBalanceResponse)
def my_credits(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> CreditBalanceResponse:
    balance = get_wallet_balance(db, current_user)
    db.commit()
    return CreditBalanceResponse(balance=balance)
