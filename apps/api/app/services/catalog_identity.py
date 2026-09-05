"""카탈로그 대표 상품 정규화·유사도 군집화.

버전을 바꾸면 배포 fingerprint가 바뀌어 CSV 재import가 강제된다.
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field
from difflib import SequenceMatcher
from typing import Iterable, Sequence

# 규칙 변경 시 bump — deploy fingerprint에 포함.
NORMALIZATION_VERSION = "v2"

# 자동 병합 임계값 (고신뢰만 자동 적용).
HIGH_CONFIDENCE = 0.92
MEDIUM_CONFIDENCE = 0.80

_VOLUME_RE = re.compile(
    r"(?i)(\d+(?:\.\d+)?)\s*(ml|mℓ|㎖|l|ℓ|㎖|g|kg|팩|개입|입|포|개)",
)
_PACK_RE = re.compile(r"(?i)[x×＊*]\s*\d+")
_NON_ALNUM_RE = re.compile(r"[^0-9A-Za-z가-힣]+")
_SPACE_RE = re.compile(r"\s+")

# 흔한 맛·옵션 표기 (긴 것부터 제거해 부분 매칭 우선).
_FLAVOR_TOKENS: tuple[str, ...] = tuple(
    sorted(
        {
            "핫앤스파이시",
            "버터캬라멜",
            "버터카라멜",
            "블랙페퍼크랩",
            "블랙페퍼",
            "할라피뇨",
            "사워크림양파",
            "사워크림앤어니언",
            "어니언",
            "양파맛",
            "양파",
            "오리지널",
            "오리지날",
            "클래식",
            "마요치즈맛",
            "마요치즈",
            "치즈맛",
            "치즈",
            "육개장사발면맛",
            "육개장맛",
            "바베큐맛",
            "바베큐",
            "레몬",
            "자몽",
            "딸기",
            "초코",
            "초콜릿",
            "무라벨",
            "플레인",
            "오리지널맛",
            "원래",
            "버터맛",
            "감자맛",
            "매콤한",
            "매운맛",
            "순한맛",
            "짜장맛",
            "크림맛",
            "허니버터",
            "스위트",
            "솔티드",
            "솔티드카라멜",
            "트러플",
            "갈릭",
            "페퍼",
            "와사비",
            "김치맛",
            "불닭맛",
            "WTF",
        },
        key=len,
        reverse=True,
    )
)

_CORP_SUFFIXES = (
    "주식회사",
    "(주)",
    "㈜",
    "유한회사",
    "유한공사",
    "농업회사법인",
    "협동조합",
)


@dataclass(frozen=True)
class ParsedCatalogTitle:
    manufacturer: str
    category: str
    raw_title: str
    canonical_title: str
    base_key: str
    flavors: tuple[str, ...]
    volumes: tuple[str, ...]
    barcode: str | None = None


@dataclass
class ReferenceVariant:
    original_title: str
    flavors: list[str] = field(default_factory=list)
    volumes: list[str] = field(default_factory=list)
    barcode: str | None = None

    def to_dict(self) -> dict:
        return {
            "originalTitle": self.original_title,
            "flavors": list(self.flavors),
            "volumes": list(self.volumes),
            "barcode": self.barcode,
        }

    @classmethod
    def from_dict(cls, data: dict) -> ReferenceVariant:
        return cls(
            original_title=str(data.get("originalTitle") or data.get("original_title") or ""),
            flavors=list(data.get("flavors") or []),
            volumes=list(data.get("volumes") or []),
            barcode=data.get("barcode"),
        )


@dataclass
class CanonicalGroup:
    manufacturer: str
    category: str
    canonical_title: str
    members: list[ParsedCatalogTitle]
    confidence: float
    volume_options: list[str] = field(default_factory=list)
    reference_variants: list[ReferenceVariant] = field(default_factory=list)
    category_major: str | None = None
    category_mid: str | None = None

    @property
    def natural_key(self) -> tuple[str, str, str]:
        return (self.manufacturer, self.category, self.canonical_title)


def normalize_manufacturer(raw: str) -> str:
    text = unicodedata.normalize("NFKC", (raw or "").strip())
    for suffix in _CORP_SUFFIXES:
        text = text.replace(suffix, "")
    text = _NON_ALNUM_RE.sub("", text)
    return text.casefold()


def _strip_manufacturer_prefix(title: str, manufacturer: str) -> str:
    text = title.strip()
    maker = manufacturer.strip()
    if not maker:
        return text
    variants = {
        maker,
        maker.replace(" ", ""),
        normalize_manufacturer(maker),
    }
    compact = text.replace(" ", "")
    for variant in variants:
        if not variant:
            continue
        if text.startswith(variant):
            text = text[len(variant) :].lstrip(" )）]-_|")
            break
        if compact.startswith(variant.replace(" ", "")):
            # 공백 없는 접두 제거 후 원문에서 대략 자르기
            rest = compact[len(variant.replace(" ", "")) :]
            # 원문에서 제조사 길이만큼 훑으며 재구성은 어렵 → compact rest 사용
            text = rest
            break
    return text.strip(" )）]-_|")


def _extract_volumes(text: str) -> tuple[str, list[str]]:
    volumes: list[str] = []
    for match in _VOLUME_RE.finditer(text):
        num, unit = match.group(1), match.group(2)
        unit_norm = unit.upper().replace("ℓ", "L").replace("㎖", "ML").replace("Mℓ", "ML")
        if unit_norm in {"L", "ML", "G", "KG"}:
            volumes.append(f"{num}{unit_norm}")
        else:
            volumes.append(f"{num}{unit}")
    cleaned = _VOLUME_RE.sub(" ", text)
    cleaned = _PACK_RE.sub(" ", cleaned)
    return cleaned, volumes


def is_volume_only_title(title: str) -> bool:
    """제품명 없이 용량·포장 수량만 남은 canonical 제목인지 확인한다."""

    raw = unicodedata.normalize("NFKC", (title or "").strip())
    if not _VOLUME_RE.search(raw):
        return False
    cleaned = _VOLUME_RE.sub(" ", raw)
    cleaned = _PACK_RE.sub(" ", cleaned)
    return not _compact_key(cleaned)


def _extract_flavors(text: str) -> tuple[str, list[str]]:
    flavors: list[str] = []
    remaining = text
    compact = remaining.replace(" ", "")
    for token in _FLAVOR_TOKENS:
        if token in remaining:
            flavors.append(token)
            remaining = remaining.replace(token, " ")
        elif token.replace(" ", "") in compact:
            flavors.append(token)
            remaining = remaining.replace(token, " ")
            # compact 치환이 어려우면 토큰 문자만 제거 시도
            for ch in token:
                remaining = remaining  # no-op placeholder
            remaining = remaining.replace(token.replace(" ", ""), " ")
    remaining = _SPACE_RE.sub(" ", remaining).strip()
    return remaining, flavors


def _compact_key(text: str) -> str:
    return _NON_ALNUM_RE.sub("", unicodedata.normalize("NFKC", text)).casefold()


def parse_catalog_title(
    *,
    manufacturer: str,
    category: str,
    title: str,
    volumes_hint: Sequence[str] | None = None,
    barcode: str | None = None,
) -> ParsedCatalogTitle:
    raw = unicodedata.normalize("NFKC", (title or "").strip())
    maker = unicodedata.normalize("NFKC", (manufacturer or "").strip())
    cat = unicodedata.normalize("NFKC", (category or "").strip())

    stripped = _strip_manufacturer_prefix(raw, maker)
    without_vol, vols = _extract_volumes(stripped)
    if volumes_hint:
        for hint in volumes_hint:
            h = (hint or "").strip()
            if h and h not in vols and h != "해당없음":
                vols.append(h)
    without_flavor, flavors = _extract_flavors(without_vol)
    base = _SPACE_RE.sub(" ", without_flavor).strip(" -_/|")
    if not base:
        # 제조사 외 제품명이 없는 원본도 용량만 카드명이 되지 않게 한다.
        raw_without_vol, _ = _extract_volumes(raw)
        raw_without_flavor, _ = _extract_flavors(raw_without_vol)
        base = (
            _SPACE_RE.sub(" ", raw_without_flavor).strip(" -_/|")
            or _SPACE_RE.sub(" ", stripped).strip()
            or raw
        )
    canonical = base
    base_key = _compact_key(base)
    return ParsedCatalogTitle(
        manufacturer=maker,
        category=cat,
        raw_title=raw,
        canonical_title=canonical,
        base_key=base_key,
        flavors=tuple(dict.fromkeys(flavors)),
        volumes=tuple(dict.fromkeys(vols)),
        barcode=(barcode or None),
    )


def _similarity(a: str, b: str) -> float:
    if not a or not b:
        return 0.0
    if a == b:
        return 1.0
    return SequenceMatcher(None, a, b).ratio()


def _hard_blocked(a: ParsedCatalogTitle, b: ParsedCatalogTitle) -> bool:
    if a.manufacturer != b.manufacturer or a.category != b.category:
        return True
    # 기본키가 서로 포함 관계가 아니고 유사도도 낮으면 차단은 cluster에서 처리.
    # 핵심 토큰이 완전히 다르면(한쪽만 긴 고유명) 중간 유사도라도 차단.
    if not a.base_key or not b.base_key:
        return True
    if a.base_key in b.base_key or b.base_key in a.base_key:
        return False
    # 짧은 키(2글자 미만 compact)는 위험 → 차단
    if len(a.base_key) < 2 or len(b.base_key) < 2:
        return True
    return False


def _pair_confidence(a: ParsedCatalogTitle, b: ParsedCatalogTitle) -> float:
    if _hard_blocked(a, b):
        return 0.0
    if a.base_key == b.base_key:
        return 1.0
    # 포함 관계(프링글스 vs 프링글스클래식 잔여 실패 시)
    if a.base_key in b.base_key or b.base_key in a.base_key:
        shorter, longer = sorted((a.base_key, b.base_key), key=len)
        if len(shorter) >= 3 and len(shorter) / max(len(longer), 1) >= 0.55:
            return 0.95
    return _similarity(a.base_key, b.base_key)


def cluster_parsed_titles(
    items: Sequence[ParsedCatalogTitle],
    *,
    auto_threshold: float = HIGH_CONFIDENCE,
) -> tuple[list[CanonicalGroup], list[tuple[ParsedCatalogTitle, ParsedCatalogTitle, float]]]:
    """제조사·소분류 내에서 고신뢰 군집화.

    반환: (자동 병합 그룹, 중간신뢰 후보 쌍)
    """
    by_bucket: dict[tuple[str, str], list[ParsedCatalogTitle]] = {}
    for item in items:
        by_bucket.setdefault((item.manufacturer, item.category), []).append(item)

    groups: list[CanonicalGroup] = []
    medium: list[tuple[ParsedCatalogTitle, ParsedCatalogTitle, float]] = []

    for (maker, category), bucket in by_bucket.items():
        n = len(bucket)
        parent = list(range(n))

        def find(i: int) -> int:
            while parent[i] != i:
                parent[i] = parent[parent[i]]
                i = parent[i]
            return i

        def union(i: int, j: int) -> None:
            ri, rj = find(i), find(j)
            if ri != rj:
                parent[rj] = ri

        for i in range(n):
            for j in range(i + 1, n):
                conf = _pair_confidence(bucket[i], bucket[j])
                if conf >= auto_threshold:
                    union(i, j)
                elif conf >= MEDIUM_CONFIDENCE:
                    medium.append((bucket[i], bucket[j], conf))

        clusters: dict[int, list[ParsedCatalogTitle]] = {}
        for i, item in enumerate(bucket):
            clusters.setdefault(find(i), []).append(item)

        for members in clusters.values():
            groups.append(_build_group(maker, category, members))

    groups.sort(key=lambda g: (g.manufacturer, g.category, g.canonical_title))
    return groups, medium


def _pick_canonical_title(members: Sequence[ParsedCatalogTitle]) -> str:
    # 가장 짧은 base(옵션이 덜 남은 것), 동점이면 빈도 높은 raw 축약
    scored = sorted(
        members,
        key=lambda m: (len(m.canonical_title), m.canonical_title),
    )
    return scored[0].canonical_title


def _build_group(
    manufacturer: str,
    category: str,
    members: Sequence[ParsedCatalogTitle],
) -> CanonicalGroup:
    canonical = _pick_canonical_title(members)
    volumes: list[str] = []
    seen_vol: set[str] = set()
    variants: list[ReferenceVariant] = []
    seen_raw: set[str] = set()
    confidences = [1.0]
    for m in members:
        for v in m.volumes:
            if v not in seen_vol:
                seen_vol.add(v)
                volumes.append(v)
        if m.raw_title not in seen_raw:
            seen_raw.add(m.raw_title)
            variants.append(
                ReferenceVariant(
                    original_title=m.raw_title,
                    flavors=list(m.flavors),
                    volumes=list(m.volumes),
                    barcode=m.barcode,
                )
            )
        for other in members:
            if other is m:
                continue
            confidences.append(_pair_confidence(m, other))
    confidence = min(confidences) if confidences else 1.0
    return CanonicalGroup(
        manufacturer=manufacturer,
        category=category,
        canonical_title=canonical,
        members=list(members),
        confidence=confidence,
        volume_options=volumes,
        reference_variants=variants,
    )


def canonicalize_csv_rows(rows: Iterable[dict]) -> tuple[list[CanonicalGroup], list[dict]]:
    """CSV row dict → canonical groups.

    각 row는 manufacturer/category/title/volume_options/barcode 및 선택적 major/mid.
    """
    parsed: list[ParsedCatalogTitle] = []
    meta: dict[tuple[str, str, str], dict] = {}
    for row in rows:
        maker = (row.get("manufacturer") or "").strip()
        category = (row.get("category") or "").strip()
        title = (row.get("title") or "").strip()
        if not maker or not category or not title:
            continue
        vols = list(row.get("volume_options") or [])
        item = parse_catalog_title(
            manufacturer=maker,
            category=category,
            title=title,
            volumes_hint=vols,
            barcode=row.get("barcode"),
        )
        parsed.append(item)
        key = (item.manufacturer, item.category, item.raw_title)
        prev = meta.get(key)
        if prev is None:
            meta[key] = {
                "category_major": row.get("category_major"),
                "category_mid": row.get("category_mid"),
            }
        else:
            if not prev.get("category_major"):
                prev["category_major"] = row.get("category_major")
            if not prev.get("category_mid"):
                prev["category_mid"] = row.get("category_mid")

    groups, medium = cluster_parsed_titles(parsed)
    for group in groups:
        # major/mid: 멤버 중 첫 non-null
        for m in group.members:
            info = meta.get((m.manufacturer, m.category, m.raw_title)) or {}
            if not group.category_major and info.get("category_major"):
                group.category_major = info["category_major"]
            if not group.category_mid and info.get("category_mid"):
                group.category_mid = info["category_mid"]

    medium_report = [
        {
            "manufacturer": a.manufacturer,
            "category": a.category,
            "left": a.raw_title,
            "right": b.raw_title,
            "confidence": round(conf, 3),
            "leftCanonical": a.canonical_title,
            "rightCanonical": b.canonical_title,
        }
        for a, b, conf in medium
    ]
    return groups, medium_report


def fingerprint_token() -> str:
    """배포 캐시에 넣을 정규화 규칙 버전."""
    return NORMALIZATION_VERSION
