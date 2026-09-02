from datetime import UTC, datetime, timedelta
from typing import Annotated
from uuid import UUID

import bcrypt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import get_settings
from app.database import get_db
from app.models import Seller, User

security = HTTPBearer(auto_error=False)
settings = get_settings()


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return bcrypt.checkpw(plain_password.encode(), hashed_password.encode())


def create_access_token(user_id: UUID) -> str:
    expire = datetime.now(UTC) + timedelta(minutes=settings.jwt_expire_minutes)
    payload = {"sub": str(user_id), "exp": expire}
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(security)],
    db: Annotated[Session, Depends(get_db)],
) -> User:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="인증이 필요합니다.")

    try:
        payload = jwt.decode(
            credentials.credentials,
            settings.jwt_secret,
            algorithms=[settings.jwt_algorithm],
        )
        user_id = payload.get("sub")
        if not user_id:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="유효하지 않은 토큰입니다.")
    except JWTError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="유효하지 않은 토큰입니다.") from exc

    user = db.get(User, UUID(user_id))
    if user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="사용자를 찾을 수 없습니다.")
    return user


def get_optional_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(security)],
    db: Annotated[Session, Depends(get_db)],
) -> User | None:
    if credentials is None or credentials.scheme.lower() != "bearer":
        return None

    try:
        payload = jwt.decode(
            credentials.credentials,
            settings.jwt_secret,
            algorithms=[settings.jwt_algorithm],
        )
        user_id = payload.get("sub")
        if not user_id:
            return None
    except JWTError:
        return None

    return db.get(User, UUID(user_id))


def require_admin(current_user: Annotated[User, Depends(get_current_user)]) -> User:
    if not current_user.is_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="관리자 권한이 필요합니다.")
    return current_user


def get_current_seller(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
) -> Seller | None:
    return db.scalar(select(Seller).where(Seller.user_id == current_user.id))


def require_active_seller(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
) -> Seller:
    seller = db.scalar(select(Seller).where(Seller.user_id == current_user.id))
    if seller is None:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="판매자 등록이 필요합니다.")
    if seller.status != "active":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="승인된 판매자만 이용할 수 있습니다.")
    return seller
