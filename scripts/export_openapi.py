#!/usr/bin/env python3
"""Export FastAPI OpenAPI schema to scripts/openapi.json for CI and codegen."""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
API_DIR = REPO_ROOT / "apps" / "api"
OUTPUT = Path(__file__).resolve().parent / "openapi.json"


def main() -> None:
    sys.path.insert(0, str(API_DIR))
    from main import app  # noqa: PLC0415

    schema = app.openapi()
    OUTPUT.write_text(
        json.dumps(schema, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {OUTPUT}")


if __name__ == "__main__":
    main()
