from app.services.guest_l1 import TAG_CAN, TAG_FROZEN, TAG_SAUCE, TAG_SIDE, TAG_SNACK
from app.services.guest_l1 import TAG_SNACKMEAL, TAG_SOUP, TAG_WATER, TAG_NOODLE, TAG_CUTLET
from app.services.guest_l1 import TAG_RICE, TAG_DAIRY, infer_l1_tags


def _tags(**kwargs) -> list[str]:
    return infer_l1_tags(**kwargs).tags


def test_shin_ramen_is_noodle():
    assert _tags(title="농심 신라면 5입", manufacturer="농심") == [TAG_NOODLE]


def test_samdasu_is_water():
    assert _tags(title="제주 삼다수 2L", manufacturer="제주특별자치도개발공사") == [TAG_WATER]


def test_doenjang_jjigae_retort_is_soup_not_sauce():
    result = infer_l1_tags(
        title="오뚜기 된장찌개 레토르트",
        manufacturer="오뚜기",
        category="즉석국/찌개",
        category_major="상온HMR",
        category_mid="레토르트",
    )
    assert TAG_SOUP in result.tags
    assert TAG_SIDE in result.tags
    assert TAG_SAUCE not in result.tags
    assert TAG_FROZEN not in result.tags
    assert result.storage == "상온"


def test_wanggyoja_frozen_is_snackmeal_and_frozen():
    result = infer_l1_tags(
        title="비비고 왕교자",
        manufacturer="비비고",
        storage="냉동",
    )
    assert result.tags == [TAG_SNACKMEAL, TAG_FROZEN]
    assert result.storage == "냉동"


def test_tteokbokki_frozen_overlap():
    result = infer_l1_tags(
        title="동원 심야식당 떡볶이",
        manufacturer="동원",
        storage="냉동",
    )
    assert TAG_SNACKMEAL in result.tags
    assert TAG_FROZEN in result.tags


def test_kimchi_fried_rice_frozen():
    result = infer_l1_tags(
        title="CJ 비비고 트레블 김치볶음밥",
        manufacturer="CJ제일제당",
        storage="냉동",
    )
    assert TAG_RICE in result.tags
    assert TAG_FROZEN in result.tags


def test_gochujang_is_sauce():
    assert _tags(title="청정원 고추장", manufacturer="청정원", category="고추장", category_mid="장류") == [
        TAG_SAUCE
    ]


def test_doenjang_jar_is_sauce():
    assert TAG_SAUCE in _tags(title="청정원 된장 500g", manufacturer="청정원")
    assert TAG_SOUP not in _tags(title="청정원 된장 500g", manufacturer="청정원")


def test_spam_is_can_and_side():
    tags = _tags(title="스팸 클래식", manufacturer="CJ제일제당")
    assert TAG_CAN in tags
    assert TAG_SIDE in tags


def test_hershey_cookie_is_snack():
    assert _tags(title="허쉬 초콜릿칩 쿠키", manufacturer="허쉬") == [TAG_SNACK]


def test_seoul_milk_is_dairy():
    result = infer_l1_tags(title="서울우유 1L", manufacturer="서울우유")
    assert result.tags == [TAG_DAIRY]
    assert result.storage == "냉장"


def test_swingchip_gochujang_flavor_is_snack_not_sauce():
    tags = _tags(
        title="오리온 스윙칩 볶음고추장맛",
        manufacturer="오리온",
        category="감자스낵",
        category_major="과자",
        category_mid="스낵",
    )
    assert TAG_SNACK in tags
    assert TAG_SAUCE not in tags


def test_curry_is_cutlet_not_sauce():
    tags = _tags(title="오뚜기 카레 약간매운맛", manufacturer="오뚜기")
    assert TAG_CUTLET in tags
    assert TAG_SAUCE not in tags


def test_category_saengsu_tags_water_without_title_keyword():
    assert TAG_WATER in _tags(title="백산수", manufacturer="농심", category="일반생수", category_mid="생수")


def test_greenaid_housewares_are_not_water():
    for title in (
        "커피필터",
        "그린에이드 실리콘 퍼프",
        "국물팩",
        "캔들",
        "쓰레기통",
        "각질제거기",
        "발각질파일",
        "티눈깎기",
    ):
        assert TAG_WATER not in _tags(title=title, manufacturer="그린에이드"), title


def test_ade_drinks_stay_water_including_greenaid_brand():
    assert TAG_WATER in _tags(title="레몬에이드 1.5L", manufacturer="롯데")
    assert TAG_WATER in _tags(title="자몽에이드", manufacturer="해태")
    assert TAG_WATER in _tags(title="그린에이드 레몬에이드", manufacturer="그린에이드")
