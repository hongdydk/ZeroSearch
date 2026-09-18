from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Literal

from fastapi import HTTPException, status

OfferUnit = Literal["ml", "L", "g", "kg", "팩"]
OFFER_UNITS: tuple[str, ...] = ("ml", "L", "g", "kg", "팩")

_LABEL_RE = re.compile(
    r"^\s*(\d+(?:\.\d+)?)\s*(ml|l|g|kg|팩)\s*(?:[×xX*]\s*(\d+))?\s*$",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class ResolvedOfferUnits:
    option_label: str
    unit_amount: float | None
    unit: str | None
    pack_count: int
    volume_ml: int | None


def format_amount(amount: float) -> str:
    if abs(amount - round(amount)) < 1e-9:
        return str(int(round(amount)))
    text = f"{amount:.3f}".rstrip("0").rstrip(".")
    return text or "0"


def format_option_label(amount: float, unit: str, pack_count: int) -> str:
    base = f"{format_amount(amount)}{unit}"
    if pack_count <= 1:
        return base
    return f"{base} × {pack_count}"


def canonicalize_unit(raw: str) -> str | None:
    token = (raw or "").strip()
    if token in OFFER_UNITS:
        return token
    lowered = token.lower()
    if lowered == "ml":
        return "ml"
    if lowered == "l":
        return "L"
    if lowered == "g":
        return "g"
    if lowered == "kg":
        return "kg"
    if token == "팩":
        return "팩"
    return None


def derive_volume_ml(amount: float, unit: str) -> int | None:
    if unit == "ml":
        return int(round(amount))
    if unit == "L":
        return int(round(amount * 1000))
    return None


def parse_option_label(label: str | None) -> ResolvedOfferUnits | None:
    text = (label or "").strip()
    if not text:
        return None
    match = _LABEL_RE.match(text)
    if match is None:
        return None
    amount = float(match.group(1))
    unit = canonicalize_unit(match.group(2))
    if unit is None:
        return None
    pack = int(match.group(3) or "1")
    if pack < 1:
        return None
    return ResolvedOfferUnits(
        option_label=format_option_label(amount, unit, pack),
        unit_amount=amount,
        unit=unit,
        pack_count=pack,
        volume_ml=derive_volume_ml(amount, unit),
    )


def resolve_offer_units(
    *,
    option_label: str | None = None,
    unit_amount: float | None = None,
    unit: str | None = None,
    pack_count: int | None = None,
    volume_ml: int | None = None,
    required: bool = True,
) -> ResolvedOfferUnits:
    amount = unit_amount
    resolved_unit = canonicalize_unit(unit) if unit else None
    packs = pack_count if pack_count is not None else 1
    if packs < 1:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="들이 개수는 1개 이상이어야 합니다.")

    if amount is not None and resolved_unit:
        if amount <= 0:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="용량을 확인하세요.")
        label = format_option_label(amount, resolved_unit, packs)
        return ResolvedOfferUnits(
            option_label=label,
            unit_amount=amount,
            unit=resolved_unit,
            pack_count=packs,
            volume_ml=derive_volume_ml(amount, resolved_unit),
        )

    parsed = parse_option_label(option_label)
    if parsed is not None:
        if pack_count is not None:
            parsed = ResolvedOfferUnits(
                option_label=format_option_label(parsed.unit_amount or 0, parsed.unit or "", packs),
                unit_amount=parsed.unit_amount,
                unit=parsed.unit,
                pack_count=packs,
                volume_ml=parsed.volume_ml,
            )
        return parsed

    label = (option_label or "").strip()
    if label:
        return ResolvedOfferUnits(
            option_label=label,
            unit_amount=None,
            unit=None,
            pack_count=packs,
            volume_ml=volume_ml,
        )

    if required:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="용량을 고르거나 들이·단위·묶음 수를 입력하세요.",
        )
    return ResolvedOfferUnits(
        option_label="",
        unit_amount=None,
        unit=None,
        pack_count=packs,
        volume_ml=volume_ml,
    )
