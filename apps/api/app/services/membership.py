from datetime import UTC, datetime, timedelta

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session, joinedload

from app.models import MembershipPlan, Subscription, User
from app.schemas.membership import MembershipPlanResponse, SubscriptionResponse
from app.services.credits import debit_credits


def list_plans(db: Session) -> list[MembershipPlan]:
    return list(db.scalars(select(MembershipPlan).order_by(MembershipPlan.price_credits)).all())


def get_active_subscription(db: Session, user: User) -> Subscription | None:
    now = datetime.now(UTC)
    return db.scalar(
        select(Subscription)
        .where(
            Subscription.user_id == user.id,
            Subscription.status == "active",
            Subscription.current_period_end > now,
        )
        .options(joinedload(Subscription.plan))
        .order_by(Subscription.current_period_end.desc())
    )


def _subscription_response(sub: Subscription) -> SubscriptionResponse:
    return SubscriptionResponse(
        id=str(sub.id),
        plan_slug=sub.plan.slug,
        plan_name=sub.plan.name,
        status=sub.status,  # type: ignore[arg-type]
        current_period_end=sub.current_period_end,
        created_at=sub.created_at,
    )


def subscribe(db: Session, user: User, plan_slug: str) -> SubscriptionResponse:
    plan = db.scalar(select(MembershipPlan).where(MembershipPlan.slug == plan_slug))
    if plan is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="멤버십 플랜을 찾을 수 없습니다.")

    existing = get_active_subscription(db, user)
    if existing is not None and existing.plan_id == plan.id:
        return _subscription_response(existing)

    period_end = datetime.now(UTC) + timedelta(days=30)

    if plan.price_credits > 0:
        sub = Subscription(
            user_id=user.id,
            plan_id=plan.id,
            status="active",
            current_period_end=period_end,
        )
        db.add(sub)
        db.flush()
        debit_credits(
            db,
            user,
            plan.price_credits,
            ref_type="subscription",
            ref_id=sub.id,
            note=f"멤버십 구독: {plan.name}",
        )
    else:
        sub = Subscription(
            user_id=user.id,
            plan_id=plan.id,
            status="active",
            current_period_end=period_end,
        )
        db.add(sub)
        db.flush()

    if existing is not None:
        existing.status = "cancelled"

    db.refresh(sub)
    sub = db.scalar(
        select(Subscription)
        .where(Subscription.id == sub.id)
        .options(joinedload(Subscription.plan))
    )
    assert sub is not None
    return _subscription_response(sub)
