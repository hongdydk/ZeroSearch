from types import SimpleNamespace
from datetime import UTC, datetime, timedelta
from unittest.mock import MagicMock, patch
from uuid import uuid4

from app.schemas.membership import SubscriptionResponse
from tests.factories import make_user, override_current_user, override_db


def test_list_membership_plans(client):
    override_db(MagicMock())

    plans = [
        SimpleNamespace(id=uuid4(), slug="free", name="Free", price_credits=0, interval="month"),
        SimpleNamespace(id=uuid4(), slug="basic", name="Basic", price_credits=30, interval="month"),
        SimpleNamespace(id=uuid4(), slug="pro", name="Pro", price_credits=80, interval="month"),
    ]

    with patch("app.routers.membership.list_plans", return_value=plans):
        response = client.get("/membership/plans")

    assert response.status_code == 200
    assert len(response.json()["items"]) == 3
    assert response.json()["items"][0]["slug"] == "free"


def test_subscribe_membership(client):
    user = make_user()
    override_current_user(user)
    override_db(MagicMock())

    sub = SubscriptionResponse(
        id=str(uuid4()),
        plan_slug="basic",
        plan_name="Basic",
        status="active",
        current_period_end=datetime.now(UTC) + timedelta(days=30),
        created_at=datetime.now(UTC),
    )

    with patch("app.routers.membership.subscribe", return_value=sub):
        response = client.post(
            "/me/membership/subscribe",
            json={"planSlug": "basic"},
            headers={"Authorization": "Bearer fake"},
        )

    assert response.status_code == 201
    assert response.json()["planSlug"] == "basic"
    assert response.json()["status"] == "active"


def test_get_membership_none(client):
    user = make_user()
    override_current_user(user)
    override_db(MagicMock())

    with patch("app.routers.membership.get_active_subscription", return_value=None):
        response = client.get("/me/membership", headers={"Authorization": "Bearer fake"})

    assert response.status_code == 200
    assert response.json()["subscription"] is None


def test_get_membership_active(client):
    user = make_user()
    override_current_user(user)
    override_db(MagicMock())

    mock_sub = MagicMock()
    mock_sub.id = uuid4()
    mock_sub.plan.slug = "pro"
    mock_sub.plan.name = "Pro"
    mock_sub.status = "active"
    mock_sub.current_period_end = datetime.now(UTC) + timedelta(days=30)
    mock_sub.created_at = datetime.now(UTC)

    with patch("app.routers.membership.get_active_subscription", return_value=mock_sub):
        response = client.get("/me/membership", headers={"Authorization": "Bearer fake"})

    assert response.status_code == 200
    assert response.json()["subscription"]["planSlug"] == "pro"
