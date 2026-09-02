from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import get_settings
from app.models import CreditTransaction, CreditWallet, User

settings = get_settings()


def get_or_create_wallet(db: Session, user_id: UUID) -> CreditWallet:
    wallet = db.scalar(select(CreditWallet).where(CreditWallet.user_id == user_id))
    if wallet is None:
        wallet = CreditWallet(user_id=user_id, balance=settings.signup_credit_bonus)
        db.add(wallet)
        db.flush()
        if settings.signup_credit_bonus > 0:
            db.add(
                CreditTransaction(
                    wallet_id=wallet.id,
                    type="grant",
                    amount=settings.signup_credit_bonus,
                    balance_after=settings.signup_credit_bonus,
                    ref_type="signup_bonus",
                    note="가입 보너스",
                )
            )
    return wallet


def get_wallet_balance(db: Session, user: User) -> int:
    wallet = get_or_create_wallet(db, user.id)
    return wallet.balance


def grant_credits(
    db: Session,
    user: User,
    amount: int,
    *,
    note: str | None = None,
    ref_type: str = "admin_grant",
    ref_id: UUID | None = None,
) -> CreditWallet:
    if amount <= 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="충전 금액은 1 이상이어야 합니다.")

    wallet = get_or_create_wallet(db, user.id)
    wallet.balance += amount
    db.add(
        CreditTransaction(
            wallet_id=wallet.id,
            type="grant",
            amount=amount,
            balance_after=wallet.balance,
            ref_type=ref_type,
            ref_id=ref_id,
            note=note,
        )
    )
    db.flush()
    return wallet


def debit_credits(
    db: Session,
    user: User,
    amount: int,
    *,
    ref_type: str,
    ref_id: UUID,
    note: str | None = None,
) -> CreditWallet:
    if amount <= 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="차감 금액이 올바르지 않습니다.")

    wallet = get_or_create_wallet(db, user.id)
    if wallet.balance < amount:
        raise HTTPException(
            status_code=status.HTTP_402_PAYMENT_REQUIRED,
            detail=f"크레딧이 부족합니다. 필요: {amount}, 보유: {wallet.balance}",
        )

    wallet.balance -= amount
    db.add(
        CreditTransaction(
            wallet_id=wallet.id,
            type="debit",
            amount=amount,
            balance_after=wallet.balance,
            ref_type=ref_type,
            ref_id=ref_id,
            note=note,
        )
    )
    db.flush()
    return wallet


def refund_credits(
    db: Session,
    user: User,
    amount: int,
    *,
    ref_type: str,
    ref_id: UUID,
    note: str | None = None,
) -> CreditWallet:
    if amount <= 0:
        return get_or_create_wallet(db, user.id)

    wallet = get_or_create_wallet(db, user.id)
    wallet.balance += amount
    db.add(
        CreditTransaction(
            wallet_id=wallet.id,
            type="refund",
            amount=amount,
            balance_after=wallet.balance,
            ref_type=ref_type,
            ref_id=ref_id,
            note=note,
        )
    )
    db.flush()
    return wallet
