"""Guest L2 browse tags — shopper language under each L1.

Rule SSOT: docs/guest-l2-tag-rules.md
Browse flow SSOT: docs/guest-l1.md
"""

from __future__ import annotations

from dataclasses import dataclass, field

from app.services.guest_l1 import (
    GUEST_L1_SET,
    TAG_CAN,
    TAG_COFFEE,
    TAG_CUTLET,
    TAG_DAIRY,
    TAG_FROZEN,
    TAG_NOODLE,
    TAG_PORRIDGE,
    TAG_POWDER,
    TAG_RICE,
    TAG_SAUCE,
    TAG_SIDE,
    TAG_SNACK,
    TAG_SNACKMEAL,
    TAG_SOUP,
    TAG_WATER,
    Confidence,
    L1Suggestion,
    Storage,
    _any_keyword,
    _contains,
    _is_jang_itself,
    _norm,
    _title_has_dish_shape,
)

GUEST_L2_BY_L1: dict[str, tuple[str, ...]] = {
    TAG_WATER: (
        "생수",
        "탄산·이온·스포츠",
        "주스·과채",
        "전통음료",
        "병·캔 커피·차",
        "기타음료",
    ),
    TAG_COFFEE: (
        "원두·캡슐",
        "커피믹스",
        "티백·잎차",
        "RTD 커피·차",
        "코코아·기타",
    ),
    TAG_SNACK: (
        "스낵·과자",
        "초콜릿·캔디",
        "시리얼·바",
        "안주·육포",
    ),
    TAG_NOODLE: (
        "봉지라면",
        "컵·용기면",
        "국수·당면·파스타",
        "냉면·기타면",
    ),
    TAG_CAN: (
        "참치·수산캔",
        "햄·고기캔",
        "농산·과일캔",
        "기타캔",
    ),
    TAG_SIDE: (
        "즉석반찬",
        "간편식·도시락",
        "대용식·선식",
        "기타",
    ),
    TAG_SOUP: (
        "국",
        "탕",
        "찌개",
        "분말·즉석국",
    ),
    TAG_RICE: (
        "흰밥·잡곡밥",
        "볶음밥·컵밥",
        "주먹밥·기타",
    ),
    TAG_PORRIDGE: (
        "죽",
        "스프",
        "미음·기타",
    ),
    TAG_SNACKMEAL: (
        "만두·교자",
        "떡볶이·어묵",
        "피자·핫도그",
        "기타분식",
    ),
    TAG_CUTLET: (
        "짜장",
        "카레",
        "돈까스·커틀릿",
        "너겟·강정",
    ),
    TAG_FROZEN: (
        "냉장HMR",
        "냉동HMR",
        "냉동만두·분식",
        "기타냉동",
    ),
    TAG_POWDER: (
        "가루·분말",
        "조미료",
        "식용유·참기름",
        "기타",
    ),
    TAG_SAUCE: (
        "고추장·된장·쌈장",
        "간장",
        "소스·드레싱",
        "식초·맛술",
    ),
    TAG_DAIRY: (
        "우유",
        "요거트·치즈·버터",
        "아이스크림·빙과",
    ),
}

GUEST_L2_SET = frozenset(tag for tags in GUEST_L2_BY_L1.values() for tag in tags)

_WATER_SAENGSU = "생수"
_WATER_SPARK = "탄산·이온·스포츠"
_WATER_JUICE = "주스·과채"
_WATER_TRAD = "전통음료"
_WATER_RTD = "병·캔 커피·차"
_WATER_OTHER = "기타음료"

_COFFEE_BEAN = "원두·캡슐"
_COFFEE_MIX = "커피믹스"
_COFFEE_TEA = "티백·잎차"
_COFFEE_RTD = "RTD 커피·차"
_COFFEE_COCOA = "코코아·기타"

_SNACK_CRISP = "스낵·과자"
_SNACK_CHOC = "초콜릿·캔디"
_SNACK_CEREAL = "시리얼·바"
_SNACK_JERKY = "안주·육포"

_NOODLE_BAG = "봉지라면"
_NOODLE_CUP = "컵·용기면"
_NOODLE_PASTA = "국수·당면·파스타"
_NOODLE_COLD = "냉면·기타면"

_CAN_FISH = "참치·수산캔"
_CAN_MEAT = "햄·고기캔"
_CAN_FRUIT = "농산·과일캔"
_CAN_OTHER = "기타캔"

_SIDE_BANCHAN = "즉석반찬"
_SIDE_HMR = "간편식·도시락"
_SIDE_MEAL = "대용식·선식"

_SOUP_GUK = "국"
_SOUP_TANG = "탕"
_SOUP_JJIGAE = "찌개"
_SOUP_POWDER = "분말·즉석국"

_RICE_WHITE = "흰밥·잡곡밥"
_RICE_FRIED = "볶음밥·컵밥"
_RICE_BALL = "주먹밥·기타"

_PORRIDGE_JUK = "죽"
_PORRIDGE_SOUP = "스프"
_PORRIDGE_MIUM = "미음·기타"

_SNACKMEAL_DUMP = "만두·교자"
_SNACKMEAL_TTEOK = "떡볶이·어묵"
_SNACKMEAL_PIZZA = "피자·핫도그"
_SNACKMEAL_OTHER = "기타분식"

_CUTLET_JJ = "짜장"
_CUTLET_CURRY = "카레"
_CUTLET_CUT = "돈까스·커틀릿"
_CUTLET_NUG = "너겟·강정"

_FROZEN_CHILL = "냉장HMR"
_FROZEN_HMR = "냉동HMR"
_FROZEN_DUMP = "냉동만두·분식"

_POWDER_FLOUR = "가루·분말"
_POWDER_SEAS = "조미료"
_POWDER_OIL = "식용유·참기름"
_POWDER_OTHER = "기타"

_SAUCE_JANG = "고추장·된장·쌈장"
_SAUCE_SOY = "간장"
_SAUCE_DRESS = "소스·드레싱"
_SAUCE_VINEGAR = "식초·맛술"

_DAIRY_MILK = "우유"
_DAIRY_YOG = "요거트·치즈·버터"
_DAIRY_ICE = "아이스크림·빙과"

_HIGH: dict[str, dict[str, tuple[str, ...]]] = {
    TAG_WATER: {
        _WATER_SAENGSU: ("생수", "먹는샘물", "삼다수", "백산수", "평창수"),
        _WATER_SPARK: (
            "탄산수",
            "탄산음료",
            "콜라",
            "사이다",
            "이온음료",
            "스포츠음료",
            "포카리",
            "게토레이",
        ),
        _WATER_JUICE: ("주스", "과채음료", "착즙", "juice"),
        _WATER_TRAD: ("식혜", "수정과", "숭늉", "전통음료", "보리차", "옥수수차"),
        _WATER_RTD: ("커피음료", "캔커피", "병커피", "아이스티", "티음료", "페트커피"),
        _WATER_OTHER: ("두유", "알로에음료", "콤부차", "에이드", "쿨피스"),
    },
    TAG_COFFEE: {
        _COFFEE_BEAN: ("원두", "캡슐커피", "홀빈", "분쇄원두"),
        _COFFEE_MIX: ("커피믹스", "믹스커피", "모카골드"),
        _COFFEE_TEA: ("티백", "잎차", "녹차", "홍차", "허브차", "둥굴레", "도라지차", "유자차"),
        _COFFEE_RTD: ("커피음료", "캔커피", "콜드브루음료", "아이스티", "티음료"),
        _COFFEE_COCOA: ("코코아", "핫초코"),
    },
    TAG_SNACK: {
        _SNACK_CRISP: (
            "과자",
            "스낵",
            "쿠키",
            "파이",
            "비스킷",
            "비스켓",
            "팝콘",
            "포카칩",
            "스윙칩",
            "새우깡",
            "감자깡",
        ),
        _SNACK_CHOC: ("초콜릿", "초콜렛", "젤리", "캔디", "껌"),
        _SNACK_CEREAL: ("시리얼바", "씨리얼바", "시리얼", "씨리얼", "그래놀라"),
        _SNACK_JERKY: ("육포", "어포", "쥐포", "안주꼬치", "안주"),
    },
    TAG_NOODLE: {
        _NOODLE_BAG: (
            "봉지라면",
            "봉지면",
            "국물봉지라면",
            "비빔봉지라면",
            "신라면",
            "진라면",
            "너구리",
            "안성탕면",
            "짜파게티",
        ),
        _NOODLE_CUP: (
            "컵라면",
            "용기면",
            "사발면",
            "큰사발",
            "컵누들",
            "국물용기라면",
            "비빔용기라면",
        ),
        _NOODLE_PASTA: (
            "국수",
            "소면",
            "중면",
            "당면",
            "칼국수",
            "쌀국수",
            "파스타",
            "스파게티",
            "우동",
        ),
        _NOODLE_COLD: ("냉면", "쫄면", "메밀면"),
    },
    TAG_CAN: {
        _CAN_FISH: ("캔참치", "참치캔", "골뱅이캔", "꽁치캔", "연어캔", "고등어캔"),
        _CAN_MEAT: ("스팸", "햄캔", "리챔", "런천미트"),
        _CAN_FRUIT: ("옥수수캔", "과일통조림", "황도캔", "과일캔"),
        _CAN_OTHER: ("기타캔", "죽캔"),
    },
    TAG_SIDE: {
        _SIDE_BANCHAN: ("즉석반찬", "반찬", "장조림", "잡채", "나물"),
        _SIDE_HMR: ("도시락", "간편식", "레토르트"),
        _SIDE_MEAL: ("대용식", "선식", "곤약밥"),
    },
    TAG_SOUP: {
        _SOUP_GUK: ("미역국", "북어국", "콩나물국", "황태국", "육개장"),
        _SOUP_TANG: ("설렁탕", "곰탕", "삼계탕", "갈비탕", "도가니탕"),
        _SOUP_JJIGAE: ("된장찌개", "김치찌개", "순두부찌개", "부대찌개", "찌개"),
        _SOUP_POWDER: ("분말국", "즉석국", "컵국"),
    },
    TAG_RICE: {
        _RICE_WHITE: ("햇반", "즉석밥", "백미밥", "잡곡밥", "현미밥"),
        _RICE_FRIED: ("볶음밥", "컵밥", "덮밥", "비빔밥"),
        _RICE_BALL: ("주먹밥", "삼각김밥"),
    },
    TAG_PORRIDGE: {
        _PORRIDGE_JUK: ("즉석죽", "죽", "porridge"),
        _PORRIDGE_SOUP: ("스프", "수프", "soup", "포터지"),
        _PORRIDGE_MIUM: ("미음",),
    },
    TAG_SNACKMEAL: {
        _SNACKMEAL_DUMP: ("만두", "교자", "딤섬"),
        _SNACKMEAL_TTEOK: ("떡볶이", "어묵", "오뎅", "떡국떡"),
        _SNACKMEAL_PIZZA: ("피자", "핫도그"),
        _SNACKMEAL_OTHER: ("쫄면", "순대", "분식"),
    },
    TAG_CUTLET: {
        _CUTLET_JJ: ("짜장소스", "짜장"),
        _CUTLET_CURRY: ("카레소스", "카레"),
        _CUTLET_CUT: ("돈까스", "돈가스", "포크커틀릿", "함박스테이크", "커틀릿"),
        _CUTLET_NUG: ("너겟", "강정"),
    },
    TAG_POWDER: {
        _POWDER_FLOUR: ("밀가루", "부침가루", "튀김가루", "설탕", "전분"),
        _POWDER_SEAS: ("다시다", "미원", "후추", "조미료", "소금"),
        _POWDER_OIL: ("식용유", "참기름", "들기름"),
        _POWDER_OTHER: ("올리고당", "물엿", "조청"),
    },
    TAG_SAUCE: {
        _SAUCE_JANG: ("고추장", "된장", "쌈장", "초고추장", "볶음고추장"),
        _SAUCE_SOY: ("간장",),
        _SAUCE_DRESS: ("케첩", "마요네즈", "드레싱", "칠리소스", "돈까스소스", "파스타소스"),
        _SAUCE_VINEGAR: ("식초", "맛술"),
    },
    TAG_DAIRY: {
        _DAIRY_MILK: ("멸균우유", "우유"),
        _DAIRY_YOG: ("요거트", "요구르트", "치즈", "버터", "생크림", "연유"),
        _DAIRY_ICE: ("아이스크림", "빙과", "아이스바"),
    },
}

_CUP_RAMEN = ("컵라면", "용기면", "사발면", "큰사발", "컵누들", "국물용기라면", "비빔용기라면")
_SNACK_SHAPE = ("쿠키", "파이", "과자", "스낵", "칩", "비스킷", "비스켓")
_DUMPLING_HINTS = ("만두", "교자", "떡볶이", "어묵", "피자", "핫도그", "딤섬", "오뎅")
_MEAL_HINTS = (
    "만두",
    "교자",
    "찌개",
    "볶음밥",
    "밀키트",
    "덮밥",
    "주먹밥",
    "비빔밥",
    "컵밥",
    "즉석밥",
    "햇반",
    "돈까스",
    "돈가스",
    "카레",
    "짜장",
    "국",
    "탕",
    "죽",
    "스프",
    "치킨",
    "튀김",
    "너겟",
    "강정",
)


@dataclass
class L2TagResult:
    tags: list[str] = field(default_factory=list)
    suggestions: list[L1Suggestion] = field(default_factory=list)

    @property
    def high_tags(self) -> list[str]:
        high = {s.tag for s in self.suggestions if s.confidence == "high"}
        return [t for t in self.tags if t in high]


def l2s_for(l1_tag: str) -> tuple[str, ...]:
    return GUEST_L2_BY_L1.get(l1_tag, ())


def is_guest_l2(l1_tag: str | None, l2_tag: str | None) -> bool:
    if not l1_tag or not l2_tag:
        return False
    return l2_tag in GUEST_L2_BY_L1.get(l1_tag, ())


def normalize_l2_tags(tags: list[str] | None, *, l1_tags: list[str] | None = None) -> list[str]:
    allowed: set[str]
    if l1_tags:
        allowed = {name for l1 in l1_tags for name in GUEST_L2_BY_L1.get(l1, ())}
    else:
        allowed = set(GUEST_L2_SET)
    out: list[str] = []
    seen: set[str] = set()
    for raw in tags or []:
        name = (raw or "").strip()
        if name not in allowed or name in seen:
            continue
        seen.add(name)
        out.append(name)
    return out


def _add(conf: dict[str, Confidence], tag: str, level: Confidence) -> None:
    prev = conf.get(tag)
    if prev == "high":
        return
    if level == "high" or prev is None:
        conf[tag] = level
    elif level == "mid" and prev == "low":
        conf[tag] = "mid"


def _scan_high(haystack: str, l1: str, conf: dict[str, Confidence]) -> None:
    for l2, keywords in _HIGH.get(l1, {}).items():
        if _any_keyword(haystack, keywords):
            _add(conf, l2, "high")


def infer_l2_tags(
    *,
    title: str,
    manufacturer: str = "",
    category: str = "",
    category_major: str = "",
    category_mid: str = "",
    storage: str | None = None,
    l1_tags: list[str] | None = None,
) -> L2TagResult:
    """Infer L2 under the given L1 tags. Ambiguous → untagged (not auto-saved)."""
    scoped = [tag for tag in (l1_tags or []) if tag in GUEST_L1_SET]
    if not scoped:
        return L2TagResult()

    title_norm = _norm(title)
    haystack = _norm(
        f"{title} {manufacturer} {category} {category_major} {category_mid} {storage or ''}"
    )
    resolved_storage: Storage | None
    explicit = (storage or "").strip()
    if explicit in {"상온", "냉장", "냉동"}:
        resolved_storage = explicit  # type: ignore[assignment]
    else:
        resolved_storage = None
    conf: dict[str, Confidence] = {}

    for l1 in scoped:
        if l1 == TAG_NOODLE:
            _infer_noodle(haystack, conf)
        elif l1 == TAG_COFFEE:
            _infer_coffee(haystack, conf)
        elif l1 == TAG_SNACK:
            _infer_snack(haystack, conf)
        elif l1 == TAG_SOUP:
            _infer_soup(haystack, conf)
        elif l1 == TAG_SAUCE:
            _infer_sauce(title_norm, haystack, category, category_mid, category_major, conf)
        elif l1 == TAG_FROZEN:
            _infer_frozen(haystack, resolved_storage, conf)
        elif l1 == TAG_DAIRY:
            _infer_dairy(haystack, conf)
        else:
            _scan_high(haystack, l1, conf)

    ordered: list[str] = []
    seen: set[str] = set()
    for l1 in scoped:
        for l2 in GUEST_L2_BY_L1.get(l1, ()):
            if l2 in conf and l2 not in seen:
                seen.add(l2)
                ordered.append(l2)
    suggestions = [L1Suggestion(tag=tag, confidence=conf[tag]) for tag in ordered]
    auto = [s.tag for s in suggestions if s.confidence == "high"]
    return L2TagResult(tags=auto, suggestions=suggestions)


def _infer_noodle(haystack: str, conf: dict[str, Confidence]) -> None:
    cup = _any_keyword(haystack, _CUP_RAMEN)
    if cup:
        _add(conf, _NOODLE_CUP, "high")
    elif _any_keyword(
        haystack,
        (
            "봉지라면",
            "봉지면",
            "국물봉지라면",
            "비빔봉지라면",
            "신라면",
            "진라면",
            "너구리",
            "안성탕면",
            "짜파게티",
        ),
    ):
        _add(conf, _NOODLE_BAG, "high")
    if _any_keyword(
        haystack, ("국수", "소면", "중면", "당면", "칼국수", "쌀국수", "파스타", "스파게티", "우동")
    ):
        _add(conf, _NOODLE_PASTA, "high")
    if _any_keyword(haystack, ("냉면", "쫄면", "메밀면")):
        _add(conf, _NOODLE_COLD, "high")


def _infer_coffee(haystack: str, conf: dict[str, Confidence]) -> None:
    bean = _any_keyword(haystack, ("원두", "캡슐커피", "홀빈", "분쇄원두"))
    rtd = _any_keyword(haystack, ("커피음료", "캔커피", "콜드브루음료", "아이스티", "티음료"))
    if bean and not rtd:
        _add(conf, _COFFEE_BEAN, "high")
    elif rtd and not bean:
        _add(conf, _COFFEE_RTD, "high")
    if _any_keyword(haystack, ("커피믹스", "믹스커피", "모카골드")):
        _add(conf, _COFFEE_MIX, "high")
    if _any_keyword(haystack, ("티백", "잎차", "녹차", "홍차", "허브차", "둥굴레", "도라지차", "유자차")):
        _add(conf, _COFFEE_TEA, "high")
    if _any_keyword(haystack, ("코코아", "핫초코")):
        _add(conf, _COFFEE_COCOA, "high")


def _infer_snack(haystack: str, conf: dict[str, Confidence]) -> None:
    snack_shape = _any_keyword(haystack, _SNACK_SHAPE)
    if snack_shape:
        _add(conf, _SNACK_CRISP, "high")
    elif _any_keyword(haystack, ("초콜릿", "초콜렛", "젤리", "캔디", "껌")):
        _add(conf, _SNACK_CHOC, "high")
    if _any_keyword(haystack, ("시리얼바", "씨리얼바", "시리얼", "씨리얼", "그래놀라")):
        _add(conf, _SNACK_CEREAL, "high")
    if _any_keyword(haystack, ("육포", "어포", "쥐포", "안주꼬치", "안주")):
        _add(conf, _SNACK_JERKY, "high")
    if not snack_shape and _any_keyword(
        haystack, ("과자", "스낵", "팝콘", "포카칩", "스윙칩", "새우깡", "감자깡")
    ):
        _add(conf, _SNACK_CRISP, "high")


def _infer_soup(haystack: str, conf: dict[str, Confidence]) -> None:
    if _any_keyword(haystack, ("분말국", "컵국")) or (
        _contains(haystack, "즉석국") and _any_keyword(haystack, ("분말", "가루"))
    ):
        _add(conf, _SOUP_POWDER, "high")
    elif _contains(haystack, "즉석국") or _contains(haystack, "컵국"):
        _add(conf, _SOUP_POWDER, "high")
    if _any_keyword(haystack, ("된장찌개", "김치찌개", "순두부찌개", "부대찌개", "찌개")):
        _add(conf, _SOUP_JJIGAE, "high")
    if _any_keyword(haystack, ("설렁탕", "곰탕", "삼계탕", "갈비탕", "도가니탕")):
        _add(conf, _SOUP_TANG, "high")
    if _any_keyword(haystack, ("미역국", "북어국", "콩나물국", "황태국", "육개장")):
        _add(conf, _SOUP_GUK, "high")


def _infer_sauce(
    title_norm: str,
    haystack: str,
    category: str,
    category_mid: str,
    category_major: str,
    conf: dict[str, Confidence],
) -> None:
    if _title_has_dish_shape(title_norm) and not _is_jang_itself(
        title_norm, _norm(f"{category}{category_mid}{category_major}")
    ):
        if _any_keyword(haystack, ("케첩", "마요네즈", "드레싱", "칠리소스", "돈까스소스", "파스타소스")):
            _add(conf, _SAUCE_DRESS, "high")
        if _any_keyword(haystack, ("식초", "맛술")):
            _add(conf, _SAUCE_VINEGAR, "high")
        return
    if _any_keyword(haystack, ("고추장", "된장", "쌈장", "초고추장", "볶음고추장")):
        _add(conf, _SAUCE_JANG, "high")
    if _contains(haystack, "간장"):
        _add(conf, _SAUCE_SOY, "high")
    if _any_keyword(haystack, ("케첩", "마요네즈", "드레싱", "칠리소스", "돈까스소스", "파스타소스")):
        _add(conf, _SAUCE_DRESS, "high")
    if _any_keyword(haystack, ("식초", "맛술")):
        _add(conf, _SAUCE_VINEGAR, "high")


def _infer_frozen(
    haystack: str,
    storage: Storage | None,
    conf: dict[str, Confidence],
) -> None:
    dumpling = _any_keyword(haystack, _DUMPLING_HINTS)
    meal = _any_keyword(haystack, _MEAL_HINTS)
    if storage == "냉동" and dumpling:
        _add(conf, _FROZEN_DUMP, "high")
        return
    if storage == "냉동" and meal:
        _add(conf, _FROZEN_HMR, "high")
        return
    if storage == "냉장" and meal:
        _add(conf, _FROZEN_CHILL, "high")


def _infer_dairy(haystack: str, conf: dict[str, Confidence]) -> None:
    if _any_keyword(haystack, ("아이스크림", "빙과", "아이스바")):
        _add(conf, _DAIRY_ICE, "high")
        return
    if _any_keyword(haystack, ("요거트", "요구르트", "치즈", "버터", "생크림", "연유")):
        _add(conf, _DAIRY_YOG, "high")
    if _any_keyword(haystack, ("멸균우유", "우유")):
        _add(conf, _DAIRY_MILK, "high")
