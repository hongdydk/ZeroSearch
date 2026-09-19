#!/usr/bin/env python3
"""Export FastAPI OpenAPI schema to scripts/openapi.json for CI and codegen."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
API_DIR = REPO_ROOT / "apps" / "api"
OUTPUT = Path(__file__).resolve().parent / "openapi.json"

# dart-dio (openapi-generator 7.11) strips non-ASCII enum values to an empty
# identifier, which fails built_value. Keep wire values; map Dart names here.
_DART_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_ENUM_VARNAME_OVERRIDES = {"팩": "pack"}


def dart_enum_varname(value: str) -> str:
    if _DART_IDENT.fullmatch(value):
        return value
    mapped = _ENUM_VARNAME_OVERRIDES.get(value)
    if mapped is None:
        raise ValueError(
            f"OpenAPI enum value {value!r} is not a valid Dart identifier; "
            "add it to _ENUM_VARNAME_OVERRIDES"
        )
    return mapped


def inject_dart_enum_varnames(node: object) -> None:
    if isinstance(node, dict):
        enum_values = node.get("enum")
        if (
            isinstance(enum_values, list)
            and enum_values
            and all(isinstance(item, str) for item in enum_values)
        ):
            varnames = [dart_enum_varname(item) for item in enum_values]
            if varnames != enum_values:
                node["x-enum-varnames"] = varnames
        for child in node.values():
            inject_dart_enum_varnames(child)
    elif isinstance(node, list):
        for child in node:
            inject_dart_enum_varnames(child)


def main() -> None:
    sys.path.insert(0, str(API_DIR))
    from main import app  # noqa: PLC0415

    schema = app.openapi()
    inject_dart_enum_varnames(schema)
    OUTPUT.write_text(
        json.dumps(schema, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {OUTPUT}")


if __name__ == "__main__":
    main()
