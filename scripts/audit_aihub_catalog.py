#!/usr/bin/env python3
"""정규화 제품명이 여러 AI-Hub 분류에 걸친 후보를 CSV로 출력한다."""

from __future__ import annotations

import argparse
import csv
import sys
from collections import defaultdict
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "apps" / "api"))

from app.services.catalog_identity import normalize_manufacturer, parse_catalog_title  # noqa: E402

DEFAULT_INPUT = REPO_ROOT / "data" / "aihub-catalog.csv"
DEFAULT_OUTPUT = REPO_ROOT / "data" / "catalog-category-conflicts.csv"


def audit(input_path: Path, output_path: Path) -> int:
    with input_path.open(encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))

    grouped: dict[tuple[str, str], list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        manufacturer = (row.get("제조사") or "").strip()
        title = (row.get("품목명") or "").strip()
        category = (row.get("소분류") or "").strip()
        if not manufacturer or not title or not category:
            continue
        parsed = parse_catalog_title(
            manufacturer=manufacturer,
            category=category,
            title=title,
            volumes_hint=[row.get("용량") or ""],
        )
        grouped[(normalize_manufacturer(manufacturer), parsed.base_key)].append(row)

    conflicts: list[dict[str, str]] = []
    for (_, base_key), members in grouped.items():
        categories = {
            (
                row.get("대분류") or "",
                row.get("중분류") or "",
                row.get("소분류") or "",
            )
            for row in members
        }
        if len(categories) < 2:
            continue
        conflicts.append(
            {
                "제조사": members[0].get("제조사") or "",
                "정규화제품키": base_key,
                "원본품목번호": "|".join(
                    sorted(
                        {
                            row.get("원본품목번호") or ""
                            for row in members
                            if row.get("원본품목번호")
                        }
                    )
                ),
                "분류후보": "|".join(
                    sorted(" > ".join(category) for category in categories)
                ),
                "원본품목명": "|".join(
                    sorted({row.get("품목명") or "" for row in members})
                ),
                "검토상태": "pending",
            }
        )

    conflicts.sort(key=lambda row: (row["제조사"], row["정규화제품키"]))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "제조사",
        "정규화제품키",
        "원본품목번호",
        "분류후보",
        "원본품목명",
        "검토상태",
    ]
    with output_path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(conflicts)
    print(f"rows={len(rows)} conflicts={len(conflicts)} -> {output_path}")
    return len(conflicts)


def main() -> None:
    parser = argparse.ArgumentParser(description="AI-Hub 카탈로그 분류 충돌 후보 감사")
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    audit(args.input, args.output)


if __name__ == "__main__":
    main()
