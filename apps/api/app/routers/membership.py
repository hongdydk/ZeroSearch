from typing import Annotated

from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps import get_current_user
from app.models import User
from app.schemas.membership import (
    MembershipPlanListResponse,
    MembershipPlanResponse,
    MembershipResponse,
    SubscribeRequest,
    SubscriptionResponse,
)
from app.services.membership import get_active_subscription, list_plans, subscribe

router = APIRouter(tags=["membership"])


@router.get("/membership/plans", response_model=MembershipPlanListResponse)
def get_membership_plans(
    db: Annotated[Session, Depends(get_db)],
) -> MembershipPlanListResponse:
    plans = list_plans(db)
    return MembershipPlanListResponse(
        items=[MembershipPlanResponse.model_validate(p) for p in plans],
    )


@router.post("/me/membership/subscribe", response_model=SubscriptionResponse, status_code=status.HTTP_201_CREATED)
def subscribe_membership(
    payload: SubscribeRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> SubscriptionResponse:
    sub = subscribe(db, current_user, payload.plan_slug)
    db.commit()
    return sub


@router.get("/me/membership", response_model=MembershipResponse)
def read_membership(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> MembershipResponse:
    from app.services.membership import _subscription_response

    sub = get_active_subscription(db, current_user)
    if sub is None:
        return MembershipResponse(subscription=None)
    return MembershipResponse(subscription=_subscription_response(sub))
