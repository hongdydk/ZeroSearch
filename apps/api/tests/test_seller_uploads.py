import io
from unittest.mock import MagicMock, patch

from app.config import Settings
from app.deps import require_active_seller
from app.services.uploads import save_seller_image
from tests.factories import make_user, override_current_user, override_db


class _Upload:
    def __init__(self, content: bytes, content_type: str, filename: str = "photo.png"):
        self.file = io.BytesIO(content)
        self.content_type = content_type
        self.filename = filename


def test_save_seller_image_writes_png(tmp_path):
    png = b"\x89PNG\r\n\x1a\n" + b"\x00" * 32
    settings = Settings(upload_dir=str(tmp_path))
    url = save_seller_image(_Upload(png, "image/png"), settings)
    assert url.startswith("/uploads/")
    assert url.endswith(".png")
    saved = tmp_path / url.rsplit("/", 1)[-1]
    assert saved.read_bytes() == png


def test_seller_upload_image_route(client):
    user = make_user()
    seller = MagicMock()
    override_current_user(user)
    override_db(MagicMock())
    from main import app

    app.dependency_overrides[require_active_seller] = lambda: seller
    png = b"\x89PNG\r\n\x1a\n" + b"\x00" * 32
    try:
        with patch("app.routers.seller.save_seller_image", return_value="/uploads/demo.png") as mock_save:
            response = client.post(
                "/seller/uploads/image",
                files={"file": ("photo.png", png, "image/png")},
                headers={"Authorization": "Bearer fake"},
            )
    finally:
        app.dependency_overrides.pop(require_active_seller, None)

    assert response.status_code == 201
    assert response.json()["imageUrl"] == "/uploads/demo.png"
    mock_save.assert_called_once()
