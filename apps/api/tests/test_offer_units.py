from fastapi import HTTPException

from app.services.offer_units import (
    format_option_label,
    parse_option_label,
    resolve_offer_units,
)


def test_format_multipack_and_single():
    assert format_option_label(2, "L", 12) == "2L × 12"
    assert format_option_label(500, "ml", 1) == "500ml"
    assert format_option_label(1.5, "L", 6) == "1.5L × 6"
    assert format_option_label(1, "팩", 1) == "1팩"


def test_parse_keeps_pack_count_out_of_volume_ml():
    parsed = parse_option_label("2L × 12")
    assert parsed is not None
    assert parsed.unit_amount == 2
    assert parsed.unit == "L"
    assert parsed.pack_count == 12
    assert parsed.volume_ml == 2000
    assert parsed.option_label == "2L × 12"

    parsed_ml = parse_option_label("500ml × 20")
    assert parsed_ml is not None
    assert parsed_ml.volume_ml == 500
    assert parsed_ml.pack_count == 20


def test_resolve_prefers_unit_fields_over_catalog_option():
    resolved = resolve_offer_units(option_label="2L", unit_amount=1.5, unit="L", pack_count=8)
    assert resolved.option_label == "1.5L × 8"
    assert resolved.volume_ml == 1500
    assert resolved.pack_count == 8


def test_resolve_free_entry_outside_volume_list():
    resolved = resolve_offer_units(option_label="3L × 4")
    assert resolved.option_label == "3L × 4"
    assert resolved.volume_ml == 3000
    assert resolved.pack_count == 4


def test_resolve_requires_capacity():
    try:
        resolve_offer_units()
    except HTTPException as exc:
        assert exc.status_code == 400
        assert "용량" in exc.detail
    else:
        raise AssertionError("expected 400")
