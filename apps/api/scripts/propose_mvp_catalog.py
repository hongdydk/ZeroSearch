"""Propose ~100 high-confidence MVP catalog cards from AI-Hub CSV.

Review output only. Does not connect to the database or import.
Picks are explicit shopper-sure SKUs, not a greedy sweep of the full CSV.
"""

from __future__ import annotations

import csv
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
API_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(API_DIR))

from app.services.catalog_identity import (  # noqa: E402
    card_identity_key,
    parse_catalog_title,
)
from app.services.guest_l1 import GUEST_L1_TAGS, infer_l1_tags  # noqa: E402
from app.services.guest_l2 import GUEST_L2_BY_L1, infer_l2_tags  # noqa: E402

SOURCE_CSV = ROOT / "data" / "aihub-catalog.csv"
OUT_CSV = ROOT / "data" / "mvp-catalog-100.csv"
OUT_MD = ROOT / "docs" / "mvp-catalog-100.md"

# (l1, l2, maker_substr, title_substr, exclude_substrs)
# maker/title match is compact (spaces stripped). First CSV hit wins.
PICKS: tuple[tuple[str, str, str, str, tuple[str, ...]], ...] = (
    ("생수/음료", "생수", "제주특별", "제주삼다수", ()),
    ("생수/음료", "생수", "농심", "백산수", ()),
    ("생수/음료", "생수", "롯데칠성", "아이시스8.0", ()),
    ("생수/음료", "탄산·이온·스포츠", "코카콜라음료", "코카콜라1.25L", ()),
    ("생수/음료", "탄산·이온·스포츠", "롯데칠성", "칠성사이다1.5L", ()),
    ("생수/음료", "탄산·이온·스포츠", "롯데칠성", "펩시콜라1.5L", ()),
    ("생수/음료", "탄산·이온·스포츠", "동아오츠카", "포카리스웨트", ("이온워터",)),
    ("생수/음료", "탄산·이온·스포츠", "롯데칠성", "게토레이600ML", ()),
    ("생수/음료", "탄산·이온·스포츠", "코카콜라", "파워에이드", ()),
    ("생수/음료", "주스·과채", "롯데칠성", "델몬트오렌지100", ()),
    ("생수/음료", "주스·과채", "코카콜라음료", "미닛메이드오리지널오렌지", ()),
    ("생수/음료", "주스·과채", "서울우유", "아침에주스사과", ()),
    ("생수/음료", "전통음료", "팔도", "비락식혜", ()),
    ("생수/음료", "병·캔 커피·차", "롯데칠성", "레쓰비마일드커피", ()),
    ("생수/음료", "기타음료", "광동", "알찬콩두유", ()),
    ("커피/원두/차", "커피믹스", "동서", "맥심모카골드마일드커피믹스", ()),
    ("커피/원두/차", "커피믹스", "동서", "카누마일드아메리카노10T", ()),
    ("커피/원두/차", "티백·잎차", "동서", "둥굴레차", ()),
    ("커피/원두/차", "티백·잎차", "동서", "현미녹차100T", ()),
    ("커피/원두/차", "RTD 커피·차", "롯데칠성", "칸타타아이스블랙커피", ()),
    ("커피/원두/차", "RTD 커피·차", "롯데칠성", "칸타타프리미엄라떼175ML", ()),
    ("커피/원두/차", "RTD 커피·차", "코카콜라음료", "조지아오리지날350ML", ()),
    ("커피/원두/차", "코코아·기타", "동서", "미떼핫초코오리지날", ()),
    ("커피/원두/차", "커피믹스", "네스카페", "네스카페부드러운모카", ()),
    ("과자/초콜릿/시리얼", "스낵·과자", "농심", "농심새우깡90G", ()),
    ("과자/초콜릿/시리얼", "스낵·과자", "롯데제과", "꼬깔콘고소한맛72G", ()),
    ("과자/초콜릿/시리얼", "스낵·과자", "오리온", "포카칩오리지널66G", ()),
    ("과자/초콜릿/시리얼", "스낵·과자", "농심", "프링글스오리지날110G", ()),
    ("과자/초콜릿/시리얼", "초콜릿·캔디", "롯데제과", "오리지날빼빼로", ()),
    ("과자/초콜릿/시리얼", "초콜릿·캔디", "오리온", "초코파이(12입)", ()),
    ("과자/초콜릿/시리얼", "시리얼·바", "농심켈로그", "첵스초코", ()),
    ("과자/초콜릿/시리얼", "시리얼·바", "농심켈로그", "콘푸로스트컵시리얼", ()),
    ("과자/초콜릿/시리얼", "안주·육포", "CJ제일제당", "쫄깃한육포", ()),
    ("과자/초콜릿/시리얼", "초콜릿·캔디", "해태", "홈런볼", ()),
    ("라면/면류", "봉지라면", "농심", "농심신라면120G", ()),
    ("라면/면류", "봉지라면", "농심", "신라면블랙101G", ()),
    ("라면/면류", "컵·용기면", "오뚜기", "컵누들팟타이쌀국수", ()),
    ("라면/면류", "봉지라면", "오뚜기", "진라면매운맛(봉지)", ()),
    ("라면/면류", "봉지라면", "농심", "농심안성탕면125G", ()),
    ("라면/면류", "봉지라면", "농심", "올리브짜파게티", ()),
    ("라면/면류", "봉지라면", "농심", "순한너구리120G", ()),
    ("라면/면류", "봉지라면", "팔도", "김치도시락", ("용기",)),
    ("라면/면류", "컵·용기면", "오뚜기", "진라면매운맛컵", ()),
    ("라면/면류", "컵·용기면", "오뚜기", "컵누들김치쌀국수", ()),
    ("라면/면류", "국수·당면·파스타", "오뚜기", "옛날사리당면", ()),
    ("라면/면류", "국수·당면·파스타", "농심", "생생우동봉지", ()),
    ("라면/면류", "냉면·기타면", "풀무원", "탱탱쫄면", ()),
    ("통조림/캔", "참치·수산캔", "동원", "동원참치200G", ()),
    ("통조림/캔", "햄·고기캔", "CJ제일제당", "CJ스팸200G", ()),
    ("통조림/캔", "햄·고기캔", "동원", "리챔오리지날", ()),
    ("통조림/캔", "농산·과일캔", "Dole", "후룻볼", ()),
    ("통조림/캔", "농산·과일캔", "오뚜기", "오뚜기황도", ()),
    ("통조림/캔", "햄·고기캔", "씨제이", "스팸25%라이트", ()),
    ("반찬/간편식/대용식", "간편식·도시락", "오뚜기", "3분제육덮밥", ()),
    ("반찬/간편식/대용식", "간편식·도시락", "오뚜기", "3분햄버그스테이크", ()),
    ("반찬/간편식/대용식", "간편식·도시락", "CJ제일제당", "비비고차돌된장찌개", ()),
    ("반찬/간편식/대용식", "즉석반찬", "동원", "소고기장조림", ()),
    ("반찬/간편식/대용식", "즉석반찬", "오뚜기", "옛날잡채용기", ()),
    ("국/탕/찌개", "국", "CJ제일제당", "비비고소고기미역국", ()),
    ("국/탕/찌개", "찌개", "CJ제일제당", "비비고돼지고기김치찌개", ()),
    ("국/탕/찌개", "찌개", "CJ제일제당", "비비고차돌된장찌개", ()),
    ("국/탕/찌개", "탕", "CJ제일제당", "비비고진국설렁탕", ()),
    ("국/탕/찌개", "국", "오뚜기", "간편미역국", ()),
    ("국/탕/찌개", "찌개", "동원", "양반돼지고기김치찌개", ()),
    ("즉석밥/볶음밥", "볶음밥·컵밥", "씨제이", "햇반컵반불닭마요덮밥", ()),
    ("즉석밥/볶음밥", "볶음밥·컵밥", "CJ제일제당", "햇반컵반스팸마요덮밥", ()),
    ("즉석밥/볶음밥", "볶음밥·컵밥", "오뚜기", "컵밥제육덮밥", ()),
    ("즉석밥/볶음밥", "볶음밥·컵밥", "오뚜기", "3분제육덮밥", ()),
    ("죽/스프", "죽", "CJ제일제당", "비비고소고기죽", ()),
    ("죽/스프", "죽", "동원", "양반단호박죽", ()),
    ("죽/스프", "죽", "동원", "양반전복죽", ()),
    ("죽/스프", "스프", "오뚜기", "콘크림스프", ("크루통",)),
    ("죽/스프", "스프", "오뚜기", "오뚜기야채스프80G", ()),
    ("분식/만두/피자", "떡볶이·어묵", "뽀로로매", "뽀로로매콤떡볶이", ()),
    ("짜장/카레/돈까스", "짜장", "오뚜기", "오뚜기3분짜장200G", ()),
    ("짜장/카레/돈까스", "카레", "오뚜기", "오뚜기3분카레약간매운맛", ()),
    ("짜장/카레/돈까스", "카레", "오뚜기", "백세카레약간매운맛100G", ()),
    ("짜장/카레/돈까스", "돈까스·커틀릿", "오뚜기", "경양식돈까스", ()),
    ("짜장/카레/돈까스", "짜장", "삼양", "맛이차이나짜장면", ()),
    ("짜장/카레/돈까스", "너겟·강정", "오뚜기", "화끈한닭강정", ()),
    ("가루/조미료/오일", "가루·분말", "오뚜기", "오뚜기부침가루1KG", ()),
    ("가루/조미료/오일", "가루·분말", "대한제분", "곰표부침가루", ()),
    ("가루/조미료/오일", "조미료", "CJ제일제당", "다시다쇠고기", ()),
    ("가루/조미료/오일", "조미료", "대상", "감칠맛미원", ()),
    ("가루/조미료/오일", "식용유·참기름", "오뚜기", "고소한참기름", ()),
    ("가루/조미료/오일", "식용유·참기름", "해표", "해표식용유", ()),
    ("장류/소스", "고추장·된장·쌈장", "씨제이", "해찬들태양초고추장500G", ()),
    ("장류/소스", "고추장·된장·쌈장", "청정원", "순창초고추장300G", ()),
    ("장류/소스", "고추장·된장·쌈장", "씨제이", "해찬들고기전용쌈장450G", ()),
    ("장류/소스", "간장", "샘표", "진간장금F3", ()),
    ("장류/소스", "소스·드레싱", "오뚜기", "골드마요네즈", ()),
    ("장류/소스", "소스·드레싱", "오뚜기", "토마토케찹800G", ()),
    ("장류/소스", "식초·맛술", "오뚜기", "오뚜기양조식초", ()),
    ("장류/소스", "식초·맛술", "CJ제일제당", "백설건강발효현미식초", ()),
    ("장류/소스", "식초·맛술", "대상", "청정원맛술", ()),
    ("유제품/아이스크림", "우유", "서울우유", "서울우유", ("딸기", "초코", "주스", "커피", "연유", "귀리", "바나나", "흑임자", "살롱", "까요", "버터")),
    ("유제품/아이스크림", "우유", "매일유업", "상하목장유기농우유", ()),
    ("유제품/아이스크림", "우유", "남양", "맛있는우유GT", ()),
    ("유제품/아이스크림", "요거트·치즈·버터", "빙그레", "요구르트", ("큐브", "칩")),
    ("유제품/아이스크림", "요거트·치즈·버터", "매일유업", "바이오드링킹요거트", ()),
)

GAPS = (
    "냉장/냉동/간편요리: AI-Hub 추출에 왕교자·냉동만두·냉동HMR 고신뢰 행이 거의 없음 (용기·탈취제·안주만 걸림).",
    "즉석밥 흰밥·잡곡밥: 추출에 컵반만 있고 흰밥 햇반 본품이 없음.",
    "분식 만두·교자 / 피자·핫도그: 만두 본품·피자 본품 없음 (소스·칩만 있음).",
    "아이스크림·빙과: 메로나·월드콘 본품 없음 (젤리·보틀만 있음).",
)


@dataclass(frozen=True)
class Candidate:
    l1: str
    l2: str
    manufacturer: str
    title: str
    flavors: tuple[str, ...]
    volumes: tuple[str, ...]
    l1_tags: tuple[str, ...]
    l2_tags: tuple[str, ...]
    identity_company: str
    identity_item: str
    source_titles: tuple[str, ...]
    preferred: bool = True
    pick_matched: str = ""


def _compact(value: str) -> str:
    return (value or "").replace(" ", "")


def _load_raw_rows() -> list[dict]:
    rows: list[dict] = []
    with SOURCE_CSV.open(encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            maker = (row.get("제조사") or "").strip()
            title = (row.get("품목명") or "").strip()
            if not maker or not title:
                continue
            rows.append(row)
    return rows


def _find_row(
    rows: list[dict],
    *,
    maker: str,
    title: str,
    exclude: tuple[str, ...],
) -> dict | None:
    maker_c = _compact(maker)
    title_c = _compact(title)
    excludes = tuple(_compact(item) for item in exclude)
    for row in rows:
        maker_blob = _compact(row.get("제조사") or "")
        title_blob = _compact(row.get("품목명") or "")
        if maker_c not in maker_blob:
            continue
        if title_c not in title_blob:
            continue
        if any(token and token in title_blob for token in excludes):
            continue
        if any(token and token in maker_blob for token in excludes):
            continue
        return row
    return None


def _candidate_from_pick(
    row: dict,
    *,
    l1: str,
    l2: str,
    pick_matched: str,
) -> Candidate:
    maker = (row.get("제조사") or "").strip()
    raw_title = (row.get("품목명") or "").strip()
    category = (row.get("소분류") or "").strip()
    parsed = parse_catalog_title(
        manufacturer=maker,
        category=category,
        title=raw_title,
        volumes_hint=[part for part in (row.get("용량") or "").split("|") if part and part != "해당없음"],
    )
    company, item = card_identity_key(maker, raw_title)
    inferred_l1 = infer_l1_tags(
        title=parsed.canonical_title,
        manufacturer=maker,
        category=category,
        category_major=row.get("대분류") or "",
        category_mid=row.get("중분류") or "",
    )
    inferred_l2 = infer_l2_tags(
        title=parsed.canonical_title,
        manufacturer=maker,
        category=category,
        category_major=row.get("대분류") or "",
        category_mid=row.get("중분류") or "",
        l1_tags=inferred_l1.tags or [l1],
    )
    return Candidate(
        l1=l1,
        l2=l2,
        manufacturer=maker,
        title=parsed.canonical_title,
        flavors=parsed.flavors,
        volumes=parsed.volumes,
        l1_tags=tuple(inferred_l1.tags),
        l2_tags=tuple(inferred_l2.tags),
        identity_company=company,
        identity_item=item,
        source_titles=(raw_title,),
        pick_matched=pick_matched,
    )


def propose(raw_rows: list[dict] | None = None) -> tuple[list[Candidate], list[str]]:
    rows = raw_rows if raw_rows is not None else _load_raw_rows()
    picked: list[Candidate] = []
    missing: list[str] = []
    seen_identity_l1: set[tuple[str, str, str]] = set()
    for l1, l2, maker, title, exclude in PICKS:
        if l2 not in GUEST_L2_BY_L1[l1]:
            missing.append(f"bad L2 mapping {l1}/{l2}")
            continue
        hit = _find_row(rows, maker=maker, title=title, exclude=exclude)
        if hit is None:
            missing.append(f"{l1} / {l2} / {maker} / {title}")
            continue
        candidate = _candidate_from_pick(
            hit, l1=l1, l2=l2, pick_matched=f"{maker}|{title}"
        )
        key = (candidate.identity_company, candidate.identity_item, l1)
        if key in seen_identity_l1:
            continue
        seen_identity_l1.add(key)
        picked.append(candidate)
    picked.sort(key=lambda row: (GUEST_L1_TAGS.index(row.l1), row.l2, row.manufacturer, row.title))
    return picked, missing


def write_csv(rows: list[Candidate], path: Path = OUT_CSV) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "l1",
        "l2",
        "manufacturer",
        "title",
        "flavors",
        "volumes",
        "inferred_l1",
        "inferred_l2",
        "identity_company",
        "identity_item",
        "source_titles",
        "pick",
    ]
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(
                {
                    "l1": row.l1,
                    "l2": row.l2,
                    "manufacturer": row.manufacturer,
                    "title": row.title,
                    "flavors": "|".join(row.flavors),
                    "volumes": "|".join(row.volumes),
                    "inferred_l1": "|".join(row.l1_tags),
                    "inferred_l2": "|".join(row.l2_tags),
                    "identity_company": row.identity_company,
                    "identity_item": row.identity_item,
                    "source_titles": "|".join(row.source_titles),
                    "pick": row.pick_matched,
                }
            )


def write_markdown(rows: list[Candidate], missing: list[str], path: Path = OUT_MD) -> None:
    covered = {row.l1 for row in rows}
    lines = [
        "# MVP 카탈로그 후보 (리뷰용)",
        "",
        "관리자가 AI-Hub를 소프트삭제한 뒤 **이 목록만 리뷰**한다. **확정 전에 운영 DB에 넣지 않는다.**",
        "전체 `data/aihub-catalog.csv` 재import는 하지 않는다.",
        "",
        f"- 후보 수: **{len(rows)}** (목표 ~100, 고신뢰만 — 빈 L1은 억지로 채우지 않음)",
        "- identity: 회사 + 품목. 맛은 `flavors` 옵션.",
        "- `l1`/`l2` 열은 리뷰용 제안. `inferred_*`는 태거가 제목에서 읽은 값.",
        "",
        "다시 뽑기: `cd apps/api && PYTHONPATH=. python -m scripts.propose_mvp_catalog`",
        "",
        "## CSV에 없는 칸 (채우지 않음)",
        "",
    ]
    for gap in GAPS:
        lines.append(f"- {gap}")
    missing_l1 = [tag for tag in GUEST_L1_TAGS if tag not in covered]
    if missing_l1:
        lines.append(f"- 이번 후보에 L1 없음: {', '.join(missing_l1)}")
    lines.append("")
    if missing:
        lines.append("## 픽이 CSV에 없음 (스크립트 경고)")
        lines.append("")
        for item in missing:
            lines.append(f"- {item}")
        lines.append("")
    for l1 in GUEST_L1_TAGS:
        subset = [row for row in rows if row.l1 == l1]
        lines.append(f"## {l1} ({len(subset)})")
        lines.append("")
        if not subset:
            lines.append("고신뢰 행 없음. 확정 시 수동 추가.")
            lines.append("")
            continue
        lines.append("| L2 | 제조사 | 품목 | 맛 | 용량 |")
        lines.append("|---|---|---|---|---|")
        for row in subset:
            flavors = ", ".join(row.flavors) if row.flavors else "—"
            volumes = ", ".join(row.volumes[:4]) if row.volumes else "—"
            name = row.source_titles[0] if row.source_titles else row.title
            lines.append(
                f"| {row.l2} | {row.manufacturer} | {name} | {flavors} | {volumes} |"
            )
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    if not SOURCE_CSV.is_file():
        raise SystemExit(f"not found: {SOURCE_CSV}")
    rows, missing = propose()
    write_csv(rows)
    write_markdown(rows, missing)
    print(f"candidates={len(rows)} missing_picks={len(missing)} csv={OUT_CSV} md={OUT_MD}")
    if missing:
        print("unmatched:")
        for item in missing:
            print(" ", item)


if __name__ == "__main__":
    main()
