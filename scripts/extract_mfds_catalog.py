#!/usr/bin/env python3
"""식약처 통합식품영양성분(가공식품) CSV → 카드 후보 CSV.

한 줄 = 제조사 + 소분류 + 품목명. 용량은 그 묶음의 식품중량 선택지.
"""

from __future__ import annotations

import argparse
import csv
import re
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SRC = REPO_ROOT / "식품의약품안전처_통합식품영양성분정보(가공식품).csv"
DEFAULT_OUT = REPO_ROOT / "data" / "mfds-catalog.csv"

SKIP_MAKER = frozenset({"", "해당없음", "-"})
SKIP_WEIGHT = frozenset({"", "해당없음", "-"})

VOL_IN_NAME = re.compile(
    r"(?:"
    r"\d+(?:\.\d+)?\s*(?:kg|g|ml|l|리터|킬로|키로)"
    r"|\d+\s*[xX×]\s*\d+(?:\s*(?:kg|g|ml|l))?"
    r"|\d+\s*입"
    r")",
    re.IGNORECASE,
)
PARENS = re.compile(r"[\[\]()（）]")
SPACES = re.compile(r"\s+")
WEIGHT_PARSE = re.compile(
    r"^\s*(\d+(?:\.\d+)?)\s*(kg|g|ml|l|리터)?\s*$",
    re.IGNORECASE,
)

UNIT_ML = {"ml": 1, "l": 1000, "리터": 1000}
UNIT_G = {"g": 1, "kg": 1000, "킬로": 1000, "키로": 1000}


def clean_text(value: str | None) -> str:
    return (value or "").strip().lstrip("\ufeff").replace("\uFFFD", "")


def fallback_type(*parts: str) -> str:
    for part in parts:
        if part and part != "해당없음":
            return part
    return next((p for p in parts if p), "")


def product_title(name: str) -> str:
    stripped = VOL_IN_NAME.sub(" ", name)
    stripped = PARENS.sub(" ", stripped)
    stripped = SPACES.sub(" ", stripped).strip(" -/")
    return stripped or name


def weight_sort_key(weight: str) -> tuple:
    match = WEIGHT_PARSE.match(weight)
    if not match:
        return (2, 0.0, weight)
    num = float(match.group(1))
    unit = (match.group(2) or "").lower()
    if unit in UNIT_ML:
        return (0, num * UNIT_ML[unit], weight)
    if unit in UNIT_G:
        return (1, num * UNIT_G[unit], weight)
    return (2, num, weight)


def mode(values: list[str]) -> str:
    nonempty = [v for v in values if v]
    if not nonempty:
        return ""
    return Counter(nonempty).most_common(1)[0][0]


def extract(src: Path, out: Path) -> int:
    groups: dict[tuple[str, str, str], dict[str, object]] = {}
    skipped_maker = 0
    source_rows = 0

    with src.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            source_rows += 1
            maker = clean_text(row.get("제조사명"))
            if maker in SKIP_MAKER:
                skipped_maker += 1
                continue

            name = clean_text(row.get("식품명"))
            if not name:
                continue

            major = clean_text(row.get("식품대분류명"))
            mid = clean_text(row.get("식품중분류명"))
            minor = fallback_type(
                clean_text(row.get("식품소분류명")),
                clean_text(row.get("대표식품명")),
                major,
            )
            title = product_title(name)
            weight = clean_text(row.get("식품중량"))

            key = (maker, minor, title)
            bucket = groups.get(key)
            if bucket is None:
                bucket = {
                    "majors": [],
                    "mids": [],
                    "weights": set(),
                }
                groups[key] = bucket
            majors = bucket["majors"]
            mids = bucket["mids"]
            weights = bucket["weights"]
            assert isinstance(majors, list)
            assert isinstance(mids, list)
            assert isinstance(weights, set)
            majors.append(major)
            mids.append(mid)
            if weight not in SKIP_WEIGHT:
                weights.add(weight)

    out.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = ["대분류", "중분류", "소분류", "품목명", "제조사", "용량"]
    rows_out = []
    for (maker, minor, title), bucket in groups.items():
        majors = bucket["majors"]
        mids = bucket["mids"]
        weights = bucket["weights"]
        assert isinstance(majors, list)
        assert isinstance(mids, list)
        assert isinstance(weights, set)
        rows_out.append(
            {
                "대분류": mode(majors),
                "중분류": mode(mids),
                "소분류": minor,
                "품목명": title,
                "제조사": maker,
                "용량": "|".join(sorted(weights, key=weight_sort_key)),
            }
        )
    rows_out.sort(key=lambda r: (r["대분류"], r["소분류"], r["제조사"], r["품목명"]))

    with out.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows_out)

    print(
        f"source={source_rows} skip_maker={skipped_maker} "
        f"cards={len(rows_out)} -> {out}"
    )
    return len(rows_out)


def main() -> None:
    parser = argparse.ArgumentParser(description="MFDS nutrition CSV → catalog candidate CSV")
    parser.add_argument("--src", type=Path, default=DEFAULT_SRC)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    if not args.src.is_file():
        raise SystemExit(f"source CSV not found: {args.src}")
    extract(args.src, args.out)


if __name__ == "__main__":
    main()
