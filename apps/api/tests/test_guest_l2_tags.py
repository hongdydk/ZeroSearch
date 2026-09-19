from app.services.guest_l1 import TAG_CAN, TAG_CUTLET, TAG_DAIRY, TAG_NOODLE, TAG_WATER, infer_l1_tags
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


def test_sparkling_water_is_not_plain_saengsu():
    tags = infer_l2_tags(
        title="올리브영워터스파클링자몽350ML",
        l1_tags=[TAG_WATER],
    ).tags
    assert "생수" not in tags
    assert "탄산·이온·스포츠" in tags


def test_coffee_filter_title_is_not_rtd_drink_l2():
    assert infer_l2_tags(title="커피필터", l1_tags=[TAG_WATER]).tags == []


def test_taxonomy_saengsu_does_not_tag_juice_coffee_spark():
    juice = infer_l2_tags(
        title="롯데델몬트콜드수박주스250ML",
        manufacturer="롯데칠성음료",
        category="일반생수",
        category_major="음료",
        category_mid="생수",
        l1_tags=[TAG_WATER],
    )
    assert "생수" not in juice.tags
    assert "주스·과채" in juice.tags

    coffee = infer_l2_tags(
        title="롯데칸타타아이스블랙커피230ML",
        manufacturer="롯데칠성음료",
        category="일반생수",
        category_major="음료",
        category_mid="생수",
        l1_tags=[TAG_WATER],
    )
    assert "생수" not in coffee.tags
    assert "병·캔 커피·차" in coffee.tags

    cola = infer_l2_tags(
        title="코카콜라오리지날테이스트250ml",
        manufacturer="코카콜라",
        category="일반생수",
        category_major="음료",
        category_mid="생수",
        l1_tags=[TAG_WATER],
    )
    assert "생수" not in cola.tags
    assert "탄산·이온·스포츠" in cola.tags


def test_taxonomy_only_saengsu_is_mid_not_auto_saved():
    result = infer_l2_tags(
        title="델몬트오렌지드링크",
        manufacturer="델몬트",
        category="일반생수",
        category_major="음료",
        category_mid="생수",
        l1_tags=[TAG_WATER],
    )
    assert "생수" not in result.tags
    assert "생수" in {s.tag for s in result.suggestions if s.confidence == "mid"}


def test_samdasu_keeps_saengsu_even_if_taxonomy_says_coffee():
    tags = infer_l2_tags(
        title="제주삼다수500ML",
        manufacturer="제주특별자치도개발공사",
        category="커피음료",
        category_major="음료",
        category_mid="커피음료",
        l1_tags=[TAG_WATER, "커피/원두/차"],
    ).tags
    assert tags == ["생수"]


def test_seoul_milk_cheese_is_not_milk_l2():
    tags = infer_l2_tags(
        title="서울우유 체다슬라이스치즈",
        manufacturer="서울우유",
        category="체다치즈",
        category_major="유제품",
        category_mid="치즈",
        l1_tags=[TAG_DAIRY],
    ).tags
    assert tags == ["요거트·치즈·버터"]


def test_seoul_milk_juice_is_not_milk_l2():
    tags = infer_l2_tags(
        title="서울우유아침에주스포도",
        manufacturer="서울우유",
        category="가공우유",
        category_major="유제품",
        category_mid="우유",
        l1_tags=[TAG_WATER, TAG_DAIRY],
    ).tags
    assert "우유" not in tags
    assert "주스·과채" in tags


def test_small_cup_jin_ramen_is_cup_not_bag():
    tags = infer_l2_tags(
        title="오뚜기진라면매운맛65G(작은용기)",
        manufacturer="오뚜기",
        category="국물봉지라면",
        category_major="면류",
        category_mid="봉지면",
        l1_tags=[TAG_NOODLE],
    ).tags
    assert "컵·용기면" in tags
    assert "봉지라면" not in tags


def test_hatban_cupban_is_fried_rice_not_white_rice():
    tags = infer_l2_tags(
        title="햇반컵반김치날치알밥",
        manufacturer="CJ제일제당",
        l1_tags=["즉석밥/볶음밥"],
    ).tags
    assert "볶음밥·컵밥" in tags
    assert "흰밥·잡곡밥" not in tags
