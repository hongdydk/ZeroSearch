from app.services.guest_l1 import TAG_CAN, TAG_CUTLET, TAG_NOODLE, infer_l1_tags
from app.services.guest_l2 import GUEST_L2_BY_L1, infer_l2_tags, l2s_for


def _l2(**kwargs) -> list[str]:
    l1 = infer_l1_tags(**kwargs)
    return infer_l2_tags(**kwargs, l1_tags=l1.tags).tags


def test_locked_l2_lists_are_three_to_seven_under_each_l1():
    expected = {
        "생수/음료": ("생수", "탄산·이온·스포츠", "주스·과채", "전통음료", "병·캔 커피·차", "기타음료"),
        "커피/원두/차": ("원두·캡슐", "커피믹스", "티백·잎차", "RTD 커피·차", "코코아·기타"),
        "과자/초콜릿/시리얼": ("스낵·과자", "초콜릿·캔디", "시리얼·바", "안주·육포"),
        "라면/면류": ("봉지라면", "컵·용기면", "국수·당면·파스타", "냉면·기타면"),
        "통조림/캔": ("참치·수산캔", "햄·고기캔", "농산·과일캔", "기타캔"),
        "반찬/간편식/대용식": ("즉석반찬", "간편식·도시락", "대용식·선식", "기타"),
        "국/탕/찌개": ("국", "탕", "찌개", "분말·즉석국"),
        "즉석밥/볶음밥": ("흰밥·잡곡밥", "볶음밥·컵밥", "주먹밥·기타"),
        "죽/스프": ("죽", "스프", "미음·기타"),
        "분식/만두/피자": ("만두·교자", "떡볶이·어묵", "피자·핫도그", "기타분식"),
        "짜장/카레/돈까스": ("짜장", "카레", "돈까스·커틀릿", "너겟·강정"),
        "냉장/냉동/간편요리": ("냉장HMR", "냉동HMR", "냉동만두·분식", "기타냉동"),
        "가루/조미료/오일": ("가루·분말", "조미료", "식용유·참기름", "기타"),
        "장류/소스": ("고추장·된장·쌈장", "간장", "소스·드레싱", "식초·맛술"),
        "유제품/아이스크림": ("우유", "요거트·치즈·버터", "아이스크림·빙과"),
    }
    assert GUEST_L2_BY_L1 == expected
    for l1, tags in expected.items():
        assert 3 <= len(tags) <= 7, l1
        assert l2s_for(l1) == tags


def test_samdasu_l2_is_saengsu():
    assert _l2(title="제주 삼다수 2L", manufacturer="제주특별자치도개발공사") == ["생수"]


def test_shin_ramen_l2_is_bag():
    assert _l2(title="농심 신라면 5입", manufacturer="농심") == ["봉지라면"]


def test_cup_ramen_l2_is_cup_not_bag():
    tags = _l2(title="육개장사발면", manufacturer="농심")
    assert "컵·용기면" in tags
    assert "봉지라면" not in tags


def test_wanggyoja_l2_dumpling_and_frozen():
    tags = _l2(title="비비고 왕교자", manufacturer="비비고", storage="냉동")
    assert "만두·교자" in tags
    assert "냉동만두·분식" in tags
    assert "냉동HMR" not in tags


def test_doenjang_jjigae_l2_is_jjigae_and_hmr():
    tags = _l2(
        title="오뚜기 된장찌개 레토르트",
        manufacturer="오뚜기",
        category="즉석국/찌개",
        category_major="상온HMR",
        category_mid="레토르트",
    )
    assert "찌개" in tags
    assert "간편식·도시락" in tags
    assert "고추장·된장·쌈장" not in tags


def test_seoul_milk_l2_is_milk():
    assert _l2(title="서울우유 1L", manufacturer="서울우유") == ["우유"]


def test_gochujang_l2_is_jang():
    assert _l2(title="청정원 고추장", manufacturer="청정원", category="고추장", category_mid="장류") == [
        "고추장·된장·쌈장"
    ]


def test_cookie_l2_is_snack_not_chocolate():
    assert _l2(title="허쉬 초콜릿칩 쿠키", manufacturer="허쉬") == ["스낵·과자"]


def test_spam_l2_is_meat_can():
    tags = _l2(title="스팸 클래식", manufacturer="CJ제일제당")
    assert "햄·고기캔" in tags
    assert TAG_CAN in infer_l1_tags(title="스팸 클래식", manufacturer="CJ제일제당").tags


def test_fanta_l2_is_sparkling_drink():
    assert "탄산·이온·스포츠" in _l2(title="환타", manufacturer="코카콜라", category="음료")


def test_curry_l2_is_curry():
    assert "카레" in _l2(title="오뚜기 카레 약간매운맛", manufacturer="오뚜기")
    assert TAG_CUTLET in infer_l1_tags(title="오뚜기 카레 약간매운맛", manufacturer="오뚜기").tags


def test_housewares_have_no_l2():
    assert _l2(title="커피필터", manufacturer="그린에이드") == []


def test_ambiguous_ramen_without_cup_or_bag_signal_is_untagged():
    assert "봉지라면" not in infer_l2_tags(
        title="라면", l1_tags=[TAG_NOODLE]
    ).tags
    assert infer_l2_tags(title="라면", l1_tags=[TAG_NOODLE]).tags == []


def test_cold_brew_alone_is_untagged_l2():
    assert infer_l2_tags(title="콜드브루", l1_tags=["커피/원두/차"]).tags == []


def test_l2_without_l1_is_empty():
    assert infer_l2_tags(title="제주 삼다수 2L", l1_tags=[]).tags == []
