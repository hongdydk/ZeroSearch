"""Guest L1 browse tags — Coupang-style overlapping multi-tags.

Rule SSOT: docs/guest-l1-tag-rules.md
Browse flow SSOT: docs/guest-l1.md
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Literal

Confidence = Literal["high", "mid", "low"]
Axis = Literal["brand", "menu"]
BrowseAxis = Literal["brand", "menu", "seller"]
Storage = Literal["상온", "냉장", "냉동"]
BROWSE_AXIS_SELLER = "seller"

GUEST_L1_TAGS: tuple[str, ...] = (
    "생수/음료",
    "커피/원두/차",
    "과자/초콜릿/시리얼",
    "라면/면류",
    "통조림/캔",
    "반찬/간편식/대용식",
    "국/탕/찌개",
    "즉석밥/볶음밥",
    "죽/스프",
    "분식/만두/피자",
    "짜장/카레/돈까스",
    "냉장/냉동/간편요리",
    "가루/조미료/오일",
    "장류/소스",
    "유제품/아이스크림",
)

GUEST_L1_SET = frozenset(GUEST_L1_TAGS)

# 자동 태거 규칙 버전. 배포 시 강제 backfill 마커와 맞춘다. v3부터 L2 포함.
TAGGER_VERSION = "v4"

DEFAULT_AXIS: dict[str, Axis] = {
    "생수/음료": "brand",
    "커피/원두/차": "brand",
    "과자/초콜릿/시리얼": "brand",
    "라면/면류": "brand",
    "통조림/캔": "brand",
    "반찬/간편식/대용식": "menu",
    "국/탕/찌개": "menu",
    "즉석밥/볶음밥": "menu",
    "죽/스프": "menu",
    "분식/만두/피자": "menu",
    "짜장/카레/돈까스": "menu",
    "냉장/냉동/간편요리": "menu",
    "가루/조미료/오일": "brand",
    "장류/소스": "brand",
    "유제품/아이스크림": "brand",
}

TAG_WATER = "생수/음료"
TAG_COFFEE = "커피/원두/차"
TAG_SNACK = "과자/초콜릿/시리얼"
TAG_NOODLE = "라면/면류"
TAG_CAN = "통조림/캔"
TAG_SIDE = "반찬/간편식/대용식"
TAG_SOUP = "국/탕/찌개"
TAG_RICE = "즉석밥/볶음밥"
TAG_PORRIDGE = "죽/스프"
TAG_SNACKMEAL = "분식/만두/피자"
TAG_CUTLET = "짜장/카레/돈까스"
TAG_FROZEN = "냉장/냉동/간편요리"
TAG_POWDER = "가루/조미료/오일"
TAG_SAUCE = "장류/소스"
TAG_DAIRY = "유제품/아이스크림"

# 요리명 — 장류 원재료만으로 장류/소스를 붙이지 않음 (된장찌개 등).
_DISH_SHAPE = (
    "찌개",
    "전골",
    "볶음",
    "조림",
    "무침",
    "찜",
    "구이",
    "라면",
    "죽",
    "스프",
    "수프",
    "소스맛",
    "레토르트",
    "컵밥",
    "덮밥",
    "비빔밥",
    "주먹밥",
    "볶음밥",
    "국밥",
)
# 짧은 접미(국/탕/밥/면)는 된장·고추장 바로 뒤에 붙을 때만 요리로 본다.
_DISH_AFTER_JANG = ("국", "탕", "밥", "면", "찌개", "전골", "라면", "죽")

_JANG_HEADS = ("고추장", "된장", "쌈장", "간장")

_HIGH: dict[str, tuple[str, ...]] = {
    TAG_WATER: (
        "생수",
        "먹는샘물",
        "탄산수",
        "탄산음료",
        "탄산",
        "콜라",
        "사이다",
        "환타",
        "스프라이트",
        "이온음료",
        "스포츠음료",
        "주스",
        "과채음료",
        "에이드",
        "쿨피스",
        "식혜",
        "수정과",
        "삼다수",
        "백산수",
        "평창수",
        "보리차",
        "옥수수차",
        "두유",
    ),
    TAG_COFFEE: (
        "커피믹스",
        "원두",
        "캡슐커피",
        "티백",
        "녹차",
        "홍차",
        "허브차",
        "둥굴레",
        "도라지차",
        "유자차",
        "코코아",
        "핫초코",
        "더치커피",
        "콜드브루",
        "커피음료",
    ),
    TAG_SNACK: (
        "과자",
        "스낵",
        "쿠키",
        "파이",
        "비스킷",
        "비스켓",
        "초콜릿",
        "초콜렛",
        "젤리",
        "캔디",
        "껌",
        "시리얼",
        "씨리얼",
        "그래놀라",
        "팝콘",
        "육포",
        "어포",
        "쥐포",
        "안주꼬치",
        "포카칩",
        "스윙칩",
        "프링글",
        "수미칩",
        "감자깡",
        "새우깡",
    ),
    TAG_NOODLE: (
        "라면",
        "컵라면",
        "봉지라면",
        "우동",
        "소면",
        "중면",
        "당면",
        "냉면",
        "칼국수",
        "쌀국수",
        "국물봉지라면",
        "국물용기라면",
        "비빔봉지라면",
        "비빔용기라면",
        "봉지면",
        "용기면",
        "사발면",
        "큰사발",
        "컵누들",
    ),
    TAG_CAN: (
        "통조림",
        "캔참치",
        "스팸",
        "햄캔",
        "골뱅이캔",
        "꽁치캔",
        "연어캔",
        "옥수수캔",
        "과일통조림",
    ),
    TAG_SIDE: (
        "반찬",
        "즉석반찬",
        "장조림",
        "잡채",
        "나물",
        "대용식",
        "선식",
        "곤약밥",
        "도시락",
        "간편식",
    ),
    TAG_SOUP: (
        "찌개",
        "육개장",
        "미역국",
        "북어국",
        "설렁탕",
        "곰탕",
        "삼계탕",
        "된장찌개",
        "김치찌개",
        "순두부",
        "부대찌개",
        "즉석국",
    ),
    TAG_RICE: (
        "즉석밥",
        "햇반",
        "볶음밥",
        "컵밥",
        "덮밥",
        "비빔밥",
        "주먹밥",
    ),
    TAG_PORRIDGE: ("죽", "스프", "수프", "포터지", "soup", "porridge", "즉석죽", "즉석스프"),
    TAG_SNACKMEAL: (
        "떡볶이",
        "어묵",
        "오뎅",
        "만두",
        "교자",
        "딤섬",
        "피자",
        "핫도그",
        "쫄면",
        "떡국떡",
        "분식",
    ),
    TAG_CUTLET: (
        "짜장",
        "짜장소스",
        "카레",
        "카레소스",
        "돈까스",
        "돈가스",
        "포크커틀릿",
        "함박스테이크",
        "너겟",
        "강정",
        "즉석카레짜장",
    ),
    TAG_POWDER: (
        "설탕",
        "소금",
        "밀가루",
        "부침가루",
        "튀김가루",
        "식용유",
        "참기름",
        "들기름",
        "올리고당",
        "물엿",
        "조청",
        "다시다",
        "미원",
        "후추",
    ),
    TAG_SAUCE: (
        "고추장",
        "된장",
        "쌈장",
        "간장",
        "케첩",
        "마요네즈",
        "드레싱",
        "칠리소스",
        "돈까스소스",
        "파스타소스",
        "맛술",
        "식초",
        "초고추장",
        "볶음고추장",
    ),
    TAG_DAIRY: (
        "멸균우유",
        "우유",
        "요거트",
        "요구르트",
        "치즈",
        "버터",
        "생크림",
        "연유",
        "아이스크림",
        "빙과",
        "아이스바",
    ),
}

_MID: dict[str, tuple[str, ...]] = {
    TAG_WATER: ("음료", "워터", "water", "juice", "과채"),
    TAG_COFFEE: ("커피", "차음료", "tea", "coffee"),
    TAG_SNACK: ("간식", "바"),
    TAG_NOODLE: ("면류", "noodle", "ramen", "파스타", "스파게티"),
    TAG_CAN: ("canned", "보일드통조림", "가미통조림"),
    TAG_SIDE: ("레토르트", "hmr", "즉석조리", "상온hmr"),
    TAG_SOUP: ("국물", "즉석국/찌개", "분말국"),
    TAG_RICE: ("즉석밥",),
    TAG_PORRIDGE: ("미음", "분말죽", "분말스프"),
    TAG_SNACKMEAL: (),
    TAG_CUTLET: ("커틀릿", "cutlet"),
    TAG_FROZEN: ("frozen", "chilled"),
    TAG_POWDER: ("가루", "분말", "오일", "oil", "분말조미료", "식용유"),
    TAG_SAUCE: ("sauce", "장류", "소스류"),
    TAG_DAIRY: ("유제품", "dairy", "ice cream", "아이스크림"),
}

_MEAL_COOK_HINTS = (
    "만두",
    "교자",
    "돈까스",
    "돈가스",
    "피자",
    "찌개",
    "볶음밥",
    "치킨",
    "핫도그",
    "튀김",
    "밀키트",
    "떡볶이",
    "어묵",
    "너겟",
    "강정",
    "카레",
    "짜장",
    "국",
    "탕",
    "죽",
    "스프",
    "덮밥",
    "주먹밥",
    "비빔밥",
    "컵밥",
    "즉석밥",
    "햇반",
)

_PUNCT_RE = re.compile(r"[\s\-_/()\[\].,+&·•|'\"~!@#$%^*=]+")
_UNIT_RE = re.compile(
    r"\d+(?:\.\d+)?\s*(?:ml|l|g|kg|입|개입|팩|봉|캔|병|pet|ℓ)?",
    re.IGNORECASE,
)


@dataclass
class L1Suggestion:
    tag: str
    confidence: Confidence


@dataclass
class L1TagResult:
    tags: list[str] = field(default_factory=list)
    suggestions: list[L1Suggestion] = field(default_factory=list)
    storage: Storage | None = None

    @property
    def high_tags(self) -> list[str]:
        high = {s.tag for s in self.suggestions if s.confidence == "high"}
        return [t for t in self.tags if t in high]


def default_axis_for(tag: str) -> Axis:
    return DEFAULT_AXIS.get(tag, "brand")


def normalize_l1_tags(tags: list[str] | None) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()
    for raw in tags or []:
        name = (raw or "").strip()
        if name not in GUEST_L1_SET or name in seen:
            continue
        seen.add(name)
        out.append(name)
    return out


def _norm(text: str) -> str:
    lowered = (text or "").lower()
    stripped_units = _UNIT_RE.sub("", lowered)
    return _PUNCT_RE.sub("", stripped_units)


def _contains(haystack: str, keyword: str) -> bool:
    needle = _norm(keyword)
    if not needle:
        return False
    if needle == "캔":
        if "캔디" in haystack or "캔들" in haystack:
            return "캔참치" in haystack or "햄캔" in haystack or "골뱅이캔" in haystack
        return "캔" in haystack
    if needle == "에이드":
        # 레몬에이드·자몽에이드는 음료. 그린에이드는 생활용품 브랜드.
        return "에이드" in haystack.replace("그린에이드", "")
    if needle == "바":
        return haystack.endswith("바") or "씨리얼바" in haystack or "시리얼바" in haystack
    if needle == "면":
        return "면" in haystack
    if needle == "장":
        return any(h in haystack for h in _JANG_HEADS) or "장류" in haystack
    if needle == "국":
        return "국" in haystack and "국수" not in haystack.replace("쌀국수", "")
    return needle in haystack


def _any_keyword(haystack: str, keywords: tuple[str, ...]) -> bool:
    return any(_contains(haystack, kw) for kw in keywords)


def infer_storage(
    *,
    title: str,
    category: str = "",
    category_mid: str = "",
    category_major: str = "",
    storage: str | None = None,
) -> Storage | None:
    explicit = (storage or "").strip()
    if explicit in {"상온", "냉장", "냉동"}:
        return explicit  # type: ignore[return-value]
    blob = _norm(f"{title}{category}{category_mid}{category_major}{explicit}")
    if "냉동" in blob or "frozen" in blob or "아이스크림" in blob or "빙과" in blob:
        return "냉동"
    if "멸균우유" in blob:
        return "상온"
    if "냉장" in blob or "chilled" in blob:
        return "냉장"
    if any(k in blob for k in ("우유", "요거트", "요구르트", "치즈", "생크림")):
        return "냉장"
    return "상온"


def _title_has_dish_shape(title_norm: str) -> bool:
    if any(shape in title_norm for shape in _DISH_SHAPE):
        return True
    for head in _JANG_HEADS:
        idx = title_norm.find(head)
        while idx != -1:
            rest = title_norm[idx + len(head) :]
            if any(rest.startswith(suffix) for suffix in _DISH_AFTER_JANG):
                return True
            idx = title_norm.find(head, idx + 1)
    return False


def _is_jang_itself(title_norm: str, category_blob: str) -> bool:
    """고추장/된장 등 장 자체. 된장찌개·볶음고추장맛(스낵)은 False."""
    if title_norm.endswith("맛") and any(head + "맛" in title_norm for head in _JANG_HEADS):
        if any(s in title_norm for s in ("칩", "과자", "스낵", "쿠키", "파이")):
            return False
    if any(title_norm.endswith(head) for head in _JANG_HEADS):
        return True
    if "볶음고추장" in title_norm and "맛" not in title_norm[title_norm.find("볶음고추장") + 5 :]:
        return True
    if any(k in category_blob for k in ("장류", "고추장", "된장", "쌈장", "간장")):
        if _title_has_dish_shape(title_norm) and not any(title_norm.endswith(h) for h in _JANG_HEADS):
            return False
        return True
    return False


def _should_apply_sauce_keyword(title_norm: str, keyword: str) -> bool:
    if keyword in {"케첩", "마요네즈", "드레싱", "칠리소스", "돈까스소스", "파스타소스", "맛술", "식초"}:
        return True
    if keyword in _JANG_HEADS or keyword in {"초고추장", "볶음고추장", "소스"}:
        if _is_jang_itself(title_norm, ""):
            return True
        if _title_has_dish_shape(title_norm):
            return False
        if title_norm.endswith("소스") and not any(
            dish in title_norm for dish in ("찌개", "라면", "볶음밥", "덮밥")
        ):
            return True
        return keyword in title_norm and not _title_has_dish_shape(title_norm)
    return True


def infer_l1_tags(
    *,
    title: str,
    manufacturer: str = "",
    category: str = "",
    category_major: str = "",
    category_mid: str = "",
    storage: str | None = None,
) -> L1TagResult:
    title_norm = _norm(title)
    haystack = _norm(
        f"{title} {manufacturer} {category} {category_major} {category_mid} {storage or ''}"
    )
    resolved_storage = infer_storage(
        title=title,
        category=category,
        category_mid=category_mid,
        category_major=category_major,
        storage=storage,
    )
    conf: dict[str, Confidence] = {}

    def add(tag: str, level: Confidence) -> None:
        prev = conf.get(tag)
        if prev == "high":
            return
        if level == "high" or prev is None:
            conf[tag] = level
        elif level == "mid" and prev == "low":
            conf[tag] = "mid"

    # 1. 보관 + 한 끼/조리
    if resolved_storage in {"냉장", "냉동"} and _any_keyword(haystack, _MEAL_COOK_HINTS):
        add(TAG_FROZEN, "high")
    elif resolved_storage in {"냉장", "냉동"} and _any_keyword(
        haystack, ("냉동", "냉장", "frozen", "chilled")
    ):
        if _any_keyword(haystack, _MEAL_COOK_HINTS):
            add(TAG_FROZEN, "high")

    # 2. strong 키워드
    for tag, keywords in _HIGH.items():
        if tag == TAG_SAUCE:
            if any(
                _contains(haystack, kw) and _should_apply_sauce_keyword(title_norm, kw)
                for kw in keywords
            ) or _is_jang_itself(title_norm, _norm(f"{category}{category_mid}{category_major}")):
                add(TAG_SAUCE, "high")
            continue
        if tag == TAG_SOUP:
            if _any_keyword(haystack, keywords) or (
                _contains(haystack, "국")
                and not _contains(haystack, "국수")
                and (_contains(haystack, "찌개") or _contains(haystack, "탕") or "즉석국" in haystack)
            ):
                add(TAG_SOUP, "high")
            continue
        if _any_keyword(haystack, keywords):
            add(tag, "high")

    for tag, keywords in _MID.items():
        if not keywords:
            continue
        if tag == TAG_SAUCE and _title_has_dish_shape(title_norm) and not _is_jang_itself(
            title_norm, _norm(f"{category}{category_mid}")
        ):
            continue
        if tag in conf:
            continue
        if _any_keyword(haystack, keywords):
            add(tag, "mid")

    # 3. 겹침 규칙
    if _any_keyword(haystack, ("만두", "교자", "피자", "핫도그", "떡볶이", "어묵", "오뎅")):
        add(TAG_SNACKMEAL, "high")
        if resolved_storage in {"냉장", "냉동"}:
            add(TAG_FROZEN, "high")
    if _any_keyword(haystack, ("돈까스", "돈가스", "카레", "짜장소스", "너겟")):
        add(TAG_CUTLET, "high")
        if resolved_storage in {"냉장", "냉동"}:
            add(TAG_FROZEN, "high")
    if _any_keyword(haystack, ("찌개", "육개장", "설렁탕", "곰탕", "삼계탕")) or (
        _contains(haystack, "국") and _any_keyword(haystack, ("즉석", "레토르트", "냉동", "탕"))
    ):
        add(TAG_SOUP, "high")
        if _any_keyword(haystack, ("즉석", "레토르트", "냉동", "hmr")):
            add(TAG_SIDE, "high")
        if resolved_storage == "냉동":
            add(TAG_FROZEN, "high")
    if _any_keyword(haystack, ("스팸", "햄캔", "통조림")):
        add(TAG_CAN, "high")
        add(TAG_SIDE, "high")

    # 4. 폴백
    if not conf and _any_keyword(haystack, ("한끼", "한 끼", "즉석", "레토르트", "hmr", "간편식")):
        add(TAG_SIDE, "mid")

    # 5. 충돌 완화
    pasta_sauce = _contains(haystack, "파스타소스") or _contains(haystack, "스파게티소스")
    dry_pasta = (
        _any_keyword(haystack, ("파스타", "스파게티"))
        and not pasta_sauce
        and _any_keyword(haystack, ("건면", "면", "면류"))
    )
    if dry_pasta:
        add(TAG_NOODLE, "high")
        conf.pop(TAG_SNACKMEAL, None)
    if pasta_sauce:
        add(TAG_SAUCE, "high")
        conf.pop(TAG_NOODLE, None)
    if resolved_storage == "상온":
        # 상온 레토르트만이면 12번 제외
        if TAG_FROZEN in conf and not _any_keyword(haystack, ("냉동", "냉장", "frozen")):
            conf.pop(TAG_FROZEN, None)

    if TAG_SAUCE in conf and _title_has_dish_shape(title_norm) and not _is_jang_itself(
        title_norm, _norm(f"{category}{category_mid}{category_major}")
    ):
        if not _any_keyword(haystack, ("파스타소스", "돈까스소스", "케첩", "마요네즈", "드레싱", "칠리소스")):
            conf.pop(TAG_SAUCE, None)

    ordered = [tag for tag in GUEST_L1_TAGS if tag in conf]
    suggestions = [L1Suggestion(tag=tag, confidence=conf[tag]) for tag in ordered]
    # 자동 확정은 high만. mid는 MD 게이트 초안에만.
    auto = [s.tag for s in suggestions if s.confidence == "high"]
    return L1TagResult(tags=auto, suggestions=suggestions, storage=resolved_storage)


def suggestions_payload(result: L1TagResult) -> list[dict[str, str]]:
    return [{"tag": s.tag, "confidence": s.confidence} for s in result.suggestions]
