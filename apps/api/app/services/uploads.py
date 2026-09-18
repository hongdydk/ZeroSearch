from __future__ import annotations

import uuid
from pathlib import Path

from fastapi import HTTPException, UploadFile, status

from app.config import Settings

_ALLOWED_TYPES = {
    "image/jpeg": ".jpg",
    "image/jpg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/gif": ".gif",
}
_MAGIC = {
    b"\xff\xd8\xff": ".jpg",
    b"\x89PNG": ".png",
    b"RIFF": ".webp",
    b"GIF87a": ".gif",
    b"GIF89a": ".gif",
}


def _extension_for(content_type: str | None, header: bytes) -> str:
    for magic, ext in _MAGIC.items():
        if header.startswith(magic):
            if ext == ".webp" and b"WEBP" not in header[:16]:
                continue
            return ext
    ext = _ALLOWED_TYPES.get((content_type or "").lower())
    if ext:
        return ext
    raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="JPEG·PNG·WebP·GIF만 올릴 수 있습니다.")


def save_seller_image(file: UploadFile, settings: Settings) -> str:
    max_bytes = settings.upload_max_bytes
    raw = file.file.read(max_bytes + 1)
    if not raw:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="빈 파일입니다.")
    if len(raw) > max_bytes:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="파일이 너무 큽니다. 5MB 이하로 올려 주세요.")
    ext = _extension_for(file.content_type, raw[:16])
    folder = Path(settings.upload_dir)
    folder.mkdir(parents=True, exist_ok=True)
    name = f"{uuid.uuid4().hex}{ext}"
    dest = folder / name
    dest.write_bytes(raw)
    return f"/uploads/{name}"
