from __future__ import annotations

import csv
import sys
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from audit_aihub_catalog import audit  # noqa: E402
from extract_aihub_catalog import extract  # noqa: E402


def _meta(
    *,
    item_no: str,
    title: str,
    category_mid: str,
    category_small: str,
    volume: str,
) -> str:
    return f"""<root><div_cd>
<item_no>{item_no}</item_no>
<div_l>음료</div_l><div_m>{category_mid}</div_m><div_s>{category_small}</div_s>
<comp_nm>농심</comp_nm><img_prod_nm>{title}</img_prod_nm><volume>{volume}</volume>
</div_cd></root>"""


def test_extract_dedupes_splits_and_applies_category_override(tmp_path: Path):
    source = tmp_path / "상품 이미지"
    for split in ("Training", "Validation"):
        folder = source / split
        folder.mkdir(parents=True)
        with zipfile.ZipFile(folder / "[라벨]음료.zip", "w") as archive:
            archive.writestr(
                "35600_농심백산수/35600_meta.xml",
                _meta(
                    item_no="35600",
                    title="농심 백산수 330ML",
                    category_mid="탄산음료",
                    category_small="혼합탄산",
                    volume="330ML",
                ),
            )

    overrides = tmp_path / "overrides.csv"
    with overrides.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["원본품목번호", "대분류", "중분류", "소분류", "사유"],
        )
        writer.writeheader()
        writer.writerow(
            {
                "원본품목번호": "35600",
                "대분류": "음료",
                "중분류": "생수",
                "소분류": "일반생수",
                "사유": "검토",
            }
        )

    output = tmp_path / "catalog.csv"
    assert extract(source, output, overrides) == 1
    with output.open(encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    assert len(rows) == 1
    assert rows[0]["원본품목번호"] == "35600"
    assert rows[0]["원본분할"] == "Training|Validation"
    assert rows[0]["중분류"] == "생수"
    assert rows[0]["소분류"] == "일반생수"
    assert "바코드" not in rows[0]


def test_audit_writes_cross_category_candidates(tmp_path: Path):
    input_path = tmp_path / "catalog.csv"
    fieldnames = [
        "원본품목번호",
        "원본분할",
        "대분류",
        "중분류",
        "소분류",
        "품목명",
        "제조사",
        "용량",
    ]
    with input_path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(
            [
                {
                    "원본품목번호": "1",
                    "원본분할": "Training|Validation",
                    "대분류": "음료",
                    "중분류": "생수",
                    "소분류": "일반생수",
                    "품목명": "농심 백산수 330ML",
                    "제조사": "농심",
                    "용량": "330ML",
                },
                {
                    "원본품목번호": "2",
                    "원본분할": "Training|Validation",
                    "대분류": "음료",
                    "중분류": "탄산음료",
                    "소분류": "혼합탄산",
                    "품목명": "농심백산수500ML",
                    "제조사": "농심",
                    "용량": "500ML",
                },
            ]
        )

    output_path = tmp_path / "conflicts.csv"
    assert audit(input_path, output_path) == 1
    with output_path.open(encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    assert rows[0]["원본품목번호"] == "1|2"
    assert rows[0]["검토상태"] == "pending"
