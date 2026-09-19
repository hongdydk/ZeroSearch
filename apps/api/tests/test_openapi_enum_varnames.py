import json
import sys
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parents[3] / "scripts"
SPEC = SCRIPTS / "openapi.json"
sys.path.insert(0, str(SCRIPTS))
from export_openapi import dart_enum_varname, inject_dart_enum_varnames  # noqa: E402


def test_dart_enum_varname_maps_pack():
    assert dart_enum_varname("ml") == "ml"
    assert dart_enum_varname("L") == "L"
    assert dart_enum_varname("팩") == "pack"
    with pytest.raises(ValueError, match="Dart identifier"):
        dart_enum_varname("박스")


def test_inject_adds_x_enum_varnames():
    node = {"enum": ["ml", "L", "g", "kg", "팩"], "type": "string"}
    inject_dart_enum_varnames({"unit": node})
    assert node["x-enum-varnames"] == ["ml", "L", "g", "kg", "pack"]


def test_pack_unit_enum_has_dart_varname():
    spec = json.loads(SPEC.read_text(encoding="utf-8"))
    found = 0

    def walk(node: object) -> None:
        nonlocal found
        if isinstance(node, dict):
            if node.get("enum") == ["ml", "L", "g", "kg", "팩"]:
                assert node.get("x-enum-varnames") == ["ml", "L", "g", "kg", "pack"]
                found += 1
            for child in node.values():
                walk(child)
        elif isinstance(node, list):
            for child in node:
                walk(child)

    walk(spec)
    assert found >= 1
