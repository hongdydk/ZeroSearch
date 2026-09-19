"""카탈로그 대표 상품 정규화·유사도 군집화.

회사+품목 identity는 브랜드부터·메뉴부터 같다. 전체 AI-Hub CSV 재import는 배포에서 기본 꺼 둔다.
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field
from decimal import Decimal
from difflib import SequenceMatcher
from typing import Iterable, Sequence

# 규칙 변경 시 bump — deploy fingerprint에 포함.
NORMALIZATION_VERSION = "v6"

# 자동 병합 임계값 (고신뢰만 자동 적용).
HIGH_CONFIDENCE = 0.92
MEDIUM_CONFIDENCE = 0.80

# 긴 단위부터. 킬로칼로리의 '킬로'는 용량이 아니므로 킬로그램만 인정.
_VOLUME_RE = re.compile(
    r"(?ix)"
    r"(\d+(?:\.\d+)?)\s*"
    r"("
    r"millilit(?:er|re)s?|밀리리터|미리리터|"
    r"kilograms?|킬로그램|"
    r"lit(?:er|re)s?|리터|"
    r"grams?|그램|"
    r"개입|"
    r"㎖|mℓ|ml|"
    r"㎏|kg|"
    r"cc|"
    r"ℓ|l|"
    r"g|"
    r"팩|입|포|개"
    r")"
)
_PACK_RE = re.compile(r"(?i)[x×＊*]\s*\d+")
_NON_ALNUM_RE = re.compile(r"[^0-9A-Za-z가-힣]+")
_SPACE_RE = re.compile(r"\s+")

_ML_UNITS = frozenset(
    {
        "ml",
        "mℓ",
        "㎖",
        "cc",
        "밀리리터",
        "미리리터",
        "milliliter",
        "millilitre",
        "milliliters",
        "millilitres",
    }
)
_L_UNITS = frozenset(
    {
        "l",
        "ℓ",
        "리터",
        "liter",
        "litre",
        "liters",
        "litres",
    }
)
_G_UNITS = frozenset({"g", "그램", "gram", "grams"})
_KG_UNITS = frozenset({"kg", "㎏", "킬로그램", "kilogram", "kilograms"})

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
            "트로피칼",
            "파인애플",
            "복숭아맛",
            "복숭아",
            "오렌지",
            "사과맛",
            "사과",
            "포도맛",
            "청포도",
            "포도",
            "슬라이스",
            "WTF",
        },
        key=len,
        reverse=True,
    )
)

# 용량 다음으로 버리는 포장 표기. 후룻볼 `100%주스` 같은 공통 접미.
_PACKAGING_NOISE: tuple[str, ...] = tuple(
    sorted(
        {
            "100%주스",
            "100퍼센트주스",
            "100%",
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

# 제조사 꼬리 — 제목의 `롯데)` / `동원)` 접두를 만들기 위한 별칭. identity 회사 키에는 쓰지 않음.
_COMPANY_TAILS = (
    "제일제당",
    "제과식품",
    "칠성음료",
    "생활건강",
    "에프앤비",
    "제과",
    "식품",
    "제약",
    "음료",
    "유업",
    "쇼핑",
    "주류",
    "코리아",
    "fb",
)

_ROMAN_TO_KO = {
    "lg": "엘지",
    "lotte": "롯데",
    "cj": "씨제이",
    "cocacola": "코카콜라",
    "coca": "코카",
    "dole": "돌",
}
_KO_TO_ROMAN = {ko: roman for roman, ko in _ROMAN_TO_KO.items()}

# 접미 1토큰이 이 집합이면 다른 품목으로 본다 (감귤 vs 감귤주스).
_PRODUCT_TYPE_NOUNS = frozenset(
    {
        "주스",
        "음료",
        "에이드",
        "커피",
        "라면",
        "면",
        "국",
        "탕",
        "찌개",
        "밥",
        "죽",
        "스프",
        "소스",
        "잼",
        "칩",
        "쿠키",
        "캔디",
        "젤리",
        "푸딩",
        "우유",
        "요거트",
        "요구르트",
        "술",
        "캔",
        "컵",
        "봉지",
        "스낵",
        "파이",
        "오일",
        "분말",
        "가루",
        "티",
        "워터",
        "차",
    }
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


@dataclass
class ReferenceVariant:
    original_title: str
    flavors: list[str] = field(default_factory=list)
    volumes: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "originalTitle": self.original_title,
            "flavors": list(self.flavors),
            "volumes": list(self.volumes),
        }

    @classmethod
    def from_dict(cls, data: dict) -> ReferenceVariant:
        return cls(
            original_title=str(data.get("originalTitle") or data.get("original_title") or ""),
            flavors=list(data.get("flavors") or []),
            volumes=list(data.get("volumes") or []),
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


def _manufacturer_identity(raw: str) -> str:
    """회사 identity. `롯데칠성`/`롯데칠성음료`만 같은 키. `롯데제과`와는 합치지 않음."""
    compact = normalize_manufacturer(raw)
    for roman, ko in sorted(_ROMAN_TO_KO.items(), key=lambda item: -len(item[0])):
        if compact.startswith(roman):
            compact = ko + compact[len(roman) :]
            break
    if compact.endswith("음료") and len(compact) >= 6:
        compact = compact[: -len("음료")]
    if compact.endswith("제일제당") and len(compact) > len("제일제당"):
        compact = compact[: -len("제일제당")]
    return compact


def _manufacturer_aliases(manufacturer: str) -> list[str]:
    raw = unicodedata.normalize("NFKC", (manufacturer or "").strip())
    aliases: list[str] = []
    seen: set[str] = set()

    def add(value: str) -> None:
        token = (value or "").strip()
        if not token:
            return
        key = token.casefold()
        if key in seen:
            return
        seen.add(key)
        aliases.append(token)

    add(raw)
    add(raw.replace(" ", ""))
    compact = normalize_manufacturer(raw)
    add(compact)
    heads = {compact} if compact else set()
    changed = True
    while changed:
        changed = False
        for head in list(heads):
            for tail in _COMPANY_TAILS:
                if head.endswith(tail) and len(head) - len(tail) >= 2:
                    stem = head[: len(head) - len(tail)]
                    if stem not in heads:
                        heads.add(stem)
                        changed = True
    for head in heads:
        add(head)
        for ko, roman in _KO_TO_ROMAN.items():
            if head.startswith(ko):
                add(roman + head[len(ko) :])
                add(roman)
        for roman, ko in _ROMAN_TO_KO.items():
            if head.startswith(roman):
                add(ko + head[len(roman) :])
                add(ko)
    aliases.sort(key=lambda item: (-len(_compact_key(item) or item), -len(item)))
    return aliases


def _strip_manufacturer_prefix(title: str, manufacturer: str) -> str:
    text = unicodedata.normalize("NFKC", (title or "").strip())
    for suffix in _CORP_SUFFIXES:
        if text.startswith(suffix):
            text = text[len(suffix) :].lstrip(" )）]-_|(")
    maker = manufacturer.strip()
    if not maker:
        return text.strip(" )）]-_|(")
    compact_title = _compact_key(text)
    for variant in _manufacturer_aliases(maker):
        if not variant:
            continue
        for form in (variant, f"{variant})", f"{variant}）", f"{variant}]"):
            if text.casefold().startswith(form.casefold()):
                rest = text[len(form) :].lstrip(" )）]-_|")
                if rest:
                    return rest.strip(" )）]-_|(")
        vcompact = _compact_key(variant)
        if (
            vcompact
            and compact_title.startswith(vcompact)
            and len(compact_title) > len(vcompact)
        ):
            rest = compact_title[len(vcompact) :]
            if rest:
                return rest.strip(" )）]-_|(")
    return text.strip(" )）]-_|(")


def _unit_kind(unit: str) -> str:
    token = unicodedata.normalize("NFKC", unit).replace(" ", "").casefold()
    token = token.replace("ℓ", "l").replace("㎖", "ml").replace("㎏", "kg")
    if token in _ML_UNITS:
        return "ml"
    if token in _L_UNITS:
        return "l"
    if token in _G_UNITS:
        return "g"
    if token in _KG_UNITS:
        return "kg"
    return "pack"


def _format_decimal(value: Decimal) -> str:
    value = value.normalize()
    if value == value.to_integral_value():
        return str(int(value))
    return format(value, "f").rstrip("0").rstrip(".")


def _format_scaled(amount: Decimal, *, thousand_unit: str, base_unit: str) -> str:
    if amount >= 1000:
        return f"{_format_decimal(amount / 1000)}{thousand_unit}"
    return f"{_format_decimal(amount)}{base_unit}"


def _canonical_volume(num: str, unit: str) -> str:
    amount = Decimal(num)
    kind = _unit_kind(unit)
    if kind == "ml":
        return _format_scaled(amount, thousand_unit="L", base_unit="ML")
    if kind == "l":
        return _format_scaled(amount * 1000, thousand_unit="L", base_unit="ML")
    if kind == "g":
        return _format_scaled(amount, thousand_unit="KG", base_unit="G")
    if kind == "kg":
        return _format_scaled(amount * 1000, thousand_unit="KG", base_unit="G")
    return f"{_format_decimal(amount)}{unit}"


def _extract_volumes(text: str) -> tuple[str, list[str]]:
    volumes: list[str] = []
    for match in _VOLUME_RE.finditer(text):
        token = _canonical_volume(match.group(1), match.group(2))
        if token and token not in volumes:
            volumes.append(token)
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


def _strip_packaging_noise(text: str) -> str:
    remaining = text
    for token in _PACKAGING_NOISE:
        remaining = remaining.replace(token, " ")
    return _SPACE_RE.sub(" ", remaining).strip()


def _flavor_remainder_ok(trial: str) -> bool:
    compact = _compact_key(trial)
    if len(compact) < 2:
        return False
    if compact in _PRODUCT_TYPE_NOUNS:
        return False
    return True


def _extract_flavors(text: str) -> tuple[str, list[str]]:
    flavors: list[str] = []
    remaining = text
    for token in _FLAVOR_TOKENS:
        compact_remaining = remaining.replace(" ", "")
        if token not in remaining and token.replace(" ", "") not in compact_remaining:
            continue
        trial = remaining.replace(token, " ")
        if token not in remaining:
            trial = trial.replace(token.replace(" ", ""), " ")
        trial = _SPACE_RE.sub(" ", trial).strip()
        if not _flavor_remainder_ok(trial):
            continue
        flavors.append(token)
        remaining = trial
    remaining = _SPACE_RE.sub(" ", remaining).strip()
    return remaining, flavors


def _compact_key(text: str) -> str:
    return _NON_ALNUM_RE.sub("", unicodedata.normalize("NFKC", text)).casefold()


def _collapse_compact_repeated_tokens(compact: str) -> str:
    """같은 제조사 제목의 반복 토큰·접미만 접는다.

    - 연속 반복: 신라면신라면 → 신라면, 사랑사랑감귤 → 사랑감귤
    - 접미 중복: 사랑감귤사랑 → 사랑감귤
    품목 유형 명사(주스·라면 등)는 접미만으로 접지 않는다.
    """
    if len(compact) < 4:
        return compact
    previous = None
    while compact != previous and len(compact) >= 4:
        previous = compact
        collapsed = False
        max_n = min(len(compact) // 2, 8)
        for n in range(max_n, 1, -1):
            if compact[: 2 * n] == compact[:n] * 2:
                compact = compact[n:]
                collapsed = True
                break
            if compact[-2 * n :] == compact[-n:] * 2:
                compact = compact[:-n]
                collapsed = True
                break
        if collapsed:
            continue
        for n in (3, 2):
            if len(compact) < n + 4:
                continue
            token = compact[-n:]
            stem = compact[:-n]
            if token not in stem:
                continue
            if token in _PRODUCT_TYPE_NOUNS and not stem.endswith(token):
                continue
            compact = stem
            break
    return compact


def _collapse_repeated_tokens(text: str) -> str:
    stripped = _SPACE_RE.sub(" ", (text or "").strip(" -_/|"))
    compact = _compact_key(stripped)
    collapsed = _collapse_compact_repeated_tokens(compact)
    if collapsed == compact:
        return stripped
    return collapsed


def _affix_leftover(a: str, b: str) -> str | None:
    if not a or not b or a == b:
        return None
    shorter, longer = (a, b) if len(a) <= len(b) else (b, a)
    if longer.startswith(shorter):
        return longer[len(shorter) :]
    if longer.endswith(shorter):
        return longer[: len(longer) - len(shorter)]
    return None


def parse_catalog_title(
    *,
    manufacturer: str,
    category: str,
    title: str,
    volumes_hint: Sequence[str] | None = None,
) -> ParsedCatalogTitle:
    raw = unicodedata.normalize("NFKC", (title or "").strip())
    maker = unicodedata.normalize("NFKC", (manufacturer or "").strip())
    cat = unicodedata.normalize("NFKC", (category or "").strip())

    stripped = _strip_manufacturer_prefix(raw, maker)
    without_vol, vols = _extract_volumes(stripped)
    without_vol = _strip_packaging_noise(without_vol)
    if volumes_hint:
        for hint in volumes_hint:
            h = (hint or "").strip()
            if not h or h == "해당없음":
                continue
            _, hint_vols = _extract_volumes(h)
            for token in hint_vols or [h]:
                if token not in vols:
                    vols.append(token)
    without_flavor, flavors = _extract_flavors(without_vol)
    base = _collapse_repeated_tokens(without_flavor)
    if not base:
        # 제조사 외 제품명이 없는 원본도 용량만 카드명이 되지 않게 한다.
        raw_without_vol, _ = _extract_volumes(raw)
        raw_without_flavor, _ = _extract_flavors(raw_without_vol)
        base = (
            _collapse_repeated_tokens(raw_without_flavor)
            or _collapse_repeated_tokens(stripped)
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
    leftover = _affix_leftover(a.base_key, b.base_key)
    if leftover and leftover in _PRODUCT_TYPE_NOUNS:
        return True
    if a.base_key in b.base_key or b.base_key in a.base_key:
        return False
    # 짧은 키(2글자 미만 compact)는 위험 → 차단
    if len(a.base_key) < 2 or len(b.base_key) < 2:
        return True
    return False


def _safe_near_duplicate(a: str, b: str) -> bool:
    """접두·접미 잔여가 짧은 1토큰이고, 이미 짧은 쪽에 있을 때만 같은 품목."""
    leftover = _affix_leftover(a, b)
    if leftover is None or leftover in _PRODUCT_TYPE_NOUNS:
        return False
    if not (2 <= len(leftover) <= 3):
        return False
    shorter = a if len(a) <= len(b) else b
    return leftover in shorter


def _pair_confidence(a: ParsedCatalogTitle, b: ParsedCatalogTitle) -> float:
    if _hard_blocked(a, b):
        return 0.0
    if a.base_key == b.base_key:
        return 1.0
    if _safe_near_duplicate(a.base_key, b.base_key):
        return 0.95
    leftover = _affix_leftover(a.base_key, b.base_key)
    similarity = _similarity(a.base_key, b.base_key)
    if leftover is not None:
        # 잔여가 새 토큰이면 SequenceMatcher 고유사도만으로 자동 병합하지 않음.
        return min(similarity, HIGH_CONFIDENCE - 0.01)
    return similarity


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

    groups = _merge_cross_category_identity(groups)
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
                )
            )
        for other in members:
            if other is m:
                continue
            conf = _pair_confidence(m, other)
            if conf > 0:
                confidences.append(conf)
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

    각 row는 manufacturer/category/title/volume_options 및 선택적 major/mid.
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
        members = [m for m in group.members if m.category == group.category] + list(group.members)
        for m in members:
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


def card_identity_key(manufacturer: str, title: str) -> tuple[str, str]:
    """손님 카드 identity: 회사 + 품목명.

    용량·맛 토큰·제조사 접두(`롯데)` / `LOTTE`)·공백·반복 접미는 같은 카드.
    소분류는 넣지 않는다. 브랜드부터·메뉴부터 같은 키.
    """
    parsed = parse_catalog_title(manufacturer=manufacturer, category="", title=title)
    return (
        _manufacturer_identity(manufacturer),
        _collapse_compact_repeated_tokens(_compact_key(parsed.canonical_title)),
    )


def matches_brand_axis(manufacturer: str, brand: str) -> bool:
    """브랜드 필터. `롯데칠성`/`롯데칠성음료`는 같은 회사."""
    token = (brand or "").strip()
    if not token:
        return True
    return card_identity_key(manufacturer, "x")[0] == card_identity_key(token, "x")[0]


def matches_menu_axis(manufacturer: str, title: str, menu: str) -> bool:
    """메뉴 필터. 맛만 다른 제목은 같은 품목. 브랜드부터와 동일 identity."""
    token = (menu or "").strip()
    if not token:
        return True
    if title == token:
        return True
    item = card_identity_key(manufacturer, title)[1]
    return item == card_identity_key(manufacturer, token)[1] or item == card_identity_key(
        "", token
    )[1]


def collapse_axis_facets(rows: Iterable[tuple[str, str]]) -> tuple[list[dict], list[dict]]:
    """(manufacturer, title) → 회사 identity 브랜드 패싯 + 회사+품목 메뉴 패싯."""
    brands: dict[str, dict] = {}
    menus: dict[tuple[str, str], dict] = {}
    for manufacturer, title in rows:
        maker = (manufacturer or "").strip()
        name = (title or "").strip()
        if not maker or not name:
            continue
        company, item = card_identity_key(maker, name)
        if not company or not item:
            continue
        brand = brands.get(company)
        if brand is None:
            brands[company] = {
                "name": maker,
                "count": 0,
                "items": set(),
                "freq": {maker: 1},
            }
            brand = brands[company]
        else:
            brand["freq"][maker] = brand["freq"].get(maker, 0) + 1
        brand["items"].add(item)
        parsed = parse_catalog_title(manufacturer=maker, category="", title=name)
        label = parsed.canonical_title or name
        menu = menus.get((company, item))
        if menu is None:
            # 회사+품목 한 장이 메뉴 한 칸. 맛만 다른 행을 카드 수로 세지 않는다.
            menus[(company, item)] = {"name": label, "count": 1}
        elif len(label) < len(menu["name"]):
            menu["name"] = label
    for brand in brands.values():
        brand["name"] = max(brand["freq"], key=lambda key: (brand["freq"][key], len(key), key))
        brand["count"] = len(brand["items"])
        del brand["items"]
        del brand["freq"]
    brand_list = sorted(brands.values(), key=lambda row: (-row["count"], row["name"]))
    menu_list = sorted(menus.values(), key=lambda row: (-row["count"], row["name"]))
    return brand_list, menu_list


def _merge_cross_category_identity(groups: list[CanonicalGroup]) -> list[CanonicalGroup]:
    """같은 제조사·같은 기본 품목명이면 AI-Hub 소분류가 달라도 한 장으로 합친다."""
    by_key: dict[tuple[str, str], list[CanonicalGroup]] = {}
    for group in groups:
        key = card_identity_key(group.manufacturer, group.canonical_title)
        by_key.setdefault(key, []).append(group)

    merged: list[CanonicalGroup] = []
    for bucket in by_key.values():
        if len(bucket) == 1:
            merged.append(bucket[0])
            continue
        primary = max(bucket, key=_identity_group_rank)
        members = [member for group in bucket for member in group.members]
        combined = _build_group(primary.manufacturer, primary.category, members)
        combined.category_major = primary.category_major
        combined.category_mid = primary.category_mid
        for group in bucket:
            if not combined.category_major and group.category_major:
                combined.category_major = group.category_major
            if not combined.category_mid and group.category_mid:
                combined.category_mid = group.category_mid
        merged.append(combined)
    return merged


def _identity_group_rank(group: CanonicalGroup) -> tuple:
    mid = group.category_mid or ""
    category = group.category or ""
    waterish = category in {"일반생수", "생수"} or mid == "생수"
    return (len(group.members), 1 if waterish else 0, -len(category), category)


def fingerprint_token() -> str:
    """배포 캐시에 넣을 정규화 규칙 버전."""
    return NORMALIZATION_VERSION
