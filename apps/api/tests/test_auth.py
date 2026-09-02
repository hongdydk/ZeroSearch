from unittest.mock import MagicMock, patch

from tests.factories import make_user, override_current_user, override_db


def test_register_returns_token(client):
    mock_db = MagicMock()
    override_db(mock_db)

    with patch("app.routers.auth.select") as mock_select, patch(
        "app.routers.auth.get_or_create_wallet"
    ), patch("app.routers.auth.create_access_token", return_value="test-token"):
        mock_db.scalar.return_value = None
        mock_db.add = MagicMock()
        mock_db.flush = MagicMock()
        mock_db.commit = MagicMock()
        mock_db.refresh = MagicMock()

        response = client.post(
            "/auth/register",
            json={"email": "buyer@mall.local", "password": "secret12", "displayName": "Buyer"},
        )

    assert response.status_code == 201
    assert response.json()["accessToken"] == "test-token"


def test_register_conflict_when_email_exists(client):
    mock_db = MagicMock()
    override_db(mock_db)
    mock_db.scalar.return_value = make_user(email="buyer@mall.local")

    response = client.post(
        "/auth/register",
        json={"email": "buyer@mall.local", "password": "secret12"},
    )

    assert response.status_code == 409
    assert "이미 등록" in response.json()["detail"]


def test_login_invalid_credentials(client):
    mock_db = MagicMock()
    override_db(mock_db)
    mock_db.scalar.return_value = None

    response = client.post(
        "/auth/login",
        json={"email": "buyer@mall.local", "password": "wrongpass"},
    )

    assert response.status_code == 401


def test_me_requires_auth(client):
    response = client.get("/auth/me")
    assert response.status_code == 401


def test_me_returns_user(client):
    user = make_user(email="buyer@mall.local", display_name="Buyer")
    override_current_user(user)

    response = client.get("/auth/me", headers={"Authorization": "Bearer fake"})

    assert response.status_code == 200
    body = response.json()
    assert body["email"] == "buyer@mall.local"
    assert body["displayName"] == "Buyer"
    assert "episodeLanguage" not in body
