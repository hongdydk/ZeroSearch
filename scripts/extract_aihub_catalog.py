#!/usr/bin/env python3
"""AI-Hub 상품 이미지 Validation 라벨 zip → 카탈로그 CSV.

한 품목 폴더의 _meta.xml 하나에서 제조사·품목명·분류·용량을 읽는다.
"""

from __future__ import annotations

import argparse
import csv
import re
import zipfile
from pathlib import Path
from xml.etree import ElementTree

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SRC = Path(r"C:\Users\ghddy\Downloads\상품 이미지\Validation")
DEFAULT_OUT = REPO_ROOT / "data" / "aihub-catalog.csv"

TAG = re.compile(r"<([a-z_]+)>([^<]*)</\1>", re.IGNORECASE)


def text(parent: ElementTree.Element | None, tag: str) -> str:
    if parent is None:
        return ""
    node = parent.find(tag)
    if node is None or node.text is None:
        return ""
    return node.text.strip()


def parse_meta(raw: bytes) -> dict[str, str] | None:
    try:
        root = ElementTree.fromstring(raw)
    except ElementTree.ParseError:
        found = {m.group(1): m.group(2).strip() for m in TAG.finditer(raw.decode("utf-8", errors="replace"))}
        if not found.get("img_prod_nm") and not found.get("comp_nm"):
            return None
        return found
    div = root.find("div_cd")
    src = div if div is not None else root
    row = {
        "item_no": text(src, "item_no"),
        "div_l": text(src, "div_l"),
        "div_m": text(src, "div_m"),
        "div_s": text(src, "div_s"),
        "comp_nm": text(src, "comp_nm"),
        "img_prod_nm": text(src, "img_prod_nm"),
        "volume": text(src, "volume"),
        "barcd": text(src, "barcd"),
    }
    if not row["img_prod_nm"] or not row["comp_nm"]:
        return None
    return row


def extract(src: Path, out: Path) -> int:
    zips = sorted(
        p for p in src.glob("*.zip") if p.name.startswith("[라벨]")
    )
    if not zips:
        raise SystemExit(f"라벨 zip이 없습니다: {src}")

    by_item: dict[str, dict[str, str]] = {}
    for zip_path in zips:
        with zipfile.ZipFile(zip_path) as archive:
            seen_folders: set[str] = set()
            for name in archive.namelist():
                if not name.endswith("_meta.xml"):
                    continue
                folder = name.split("/", 1)[0]
                if folder in seen_folders:
                    continue
                seen_folders.add(folder)
                row = parse_meta(archive.read(name))
                if row is None:
                    continue
                key = row["item_no"] or row["barcd"] or f"{row['comp_nm']}|{row['img_prod_nm']}"
                prev = by_item.get(key)
                if prev is None:
                    by_item[key] = row
                    continue
                vols = {v for v in (prev["volume"], row["volume"]) if v}
                prev["volume"] = "|".join(sorted(vols))

    out.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = ["대분류", "중분류", "소분류", "품목명", "제조사", "용량", "바코드"]
    rows = []
    for row in by_item.values():
        rows.append(
            {
                "대분류": row["div_l"],
                "중분류": row["div_m"],
                "소분류": row["div_s"] or row["div_m"] or row["div_l"],
                "품목명": row["img_prod_nm"],
                "제조사": row["comp_nm"],
                "용량": row["volume"],
                "바코드": row["barcd"],
            }
        )
    rows.sort(key=lambda r: (r["대분류"], r["소분류"], r["제조사"], r["품목명"]))
    with out.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    print(f"zips={len(zips)} cards={len(rows)} -> {out}")
    return len(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description="AI-Hub 상품 이미지 라벨 → catalog CSV")
    parser.add_argument("--src", type=Path, default=DEFAULT_SRC)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    if not args.src.is_dir():
        raise SystemExit(f"source dir not found: {args.src}")
    extract(args.src, args.out)


if __name__ == "__main__":
    main()
