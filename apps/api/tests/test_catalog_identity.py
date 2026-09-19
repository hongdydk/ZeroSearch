from app.services.catalog_identity import (
    HIGH_CONFIDENCE,
    canonicalize_csv_rows,
    card_identity_key,
    collapse_axis_facets,
    cluster_parsed_titles,
    matches_brand_axis,
    matches_menu_axis,
    parse_catalog_title,
)


def test_parse_strips_maker_volume_flavor():
    parsed = parse_catalog_title(
        manufacturer="농심",
        category="감자스낵",
        title="농심)프링글스버터캬라멜110G",
        volumes_hint=["110G"],
    )
    assert parsed.canonical_title == "프링글스"
    assert "버터캬라멜" in parsed.flavors
    assert "110G" in parsed.volumes


def test_parse_without_paren_prefix():
    parsed = parse_catalog_title(
        manufacturer="농심",
        category="감자스낵",
        title="프링글스양파맛 53G",
        volumes_hint=["53G"],
    )
    assert parsed.canonical_title == "프링글스"
    assert "양파맛" in parsed.flavors or "양파" in parsed.flavors


def test_parse_keeps_product_name_before_option_parentheses():
    cases = [
        ("농심튀김우동(봉지)118G", "튀김우동(봉지)"),
        ("농심 새우탕컵(소) 67G", "새우탕컵(소)"),
        ("농심)앵그리알티에이(RtA)(낱개)121G", "앵그리알티에이(RtA)(낱개)"),
    ]

    for title, expected in cases:
        parsed = parse_catalog_title(
            manufacturer="농심",
            category="라면",
            title=title,
        )
        assert parsed.canonical_title == expected


def test_parse_never_replaces_maker_only_title_with_volume():
    parsed = parse_catalog_title(
        manufacturer="피카소F",
        category="과채음료",
        title="피카소F120ML",
    )
    assert parsed.canonical_title == "피카소F"


def test_cluster_merges_flavor_volume_variants():
    items = [
        parse_catalog_title(manufacturer="농심", category="감자스낵", title="농심)프링글스클래식110G"),
        parse_catalog_title(manufacturer="농심", category="감자스낵", title="프링글스양파맛 53G"),
        parse_catalog_title(manufacturer="농심", category="감자스낵", title="농심감자깡75G"),
        parse_catalog_title(manufacturer="농심", category="감자스낵", title="농심 수미칩 어니언 85G"),
        parse_catalog_title(manufacturer="농심", category="감자스낵", title="농심수미칩어니언55G"),
    ]
    groups, medium = cluster_parsed_titles(items, auto_threshold=HIGH_CONFIDENCE)
    titles = {g.canonical_title: len(g.members) for g in groups}
    assert titles.get("프링글스", 0) >= 2
    assert titles.get("감자깡", 0) == 1
    assert titles.get("수미칩", 0) >= 2
    # 감자깡과 프링글스는 합치지 않음
    assert all(g.canonical_title != "감자깡" or len(g.members) == 1 for g in groups)


def test_different_maker_not_merged():
    items = [
        parse_catalog_title(manufacturer="농심", category="감자스낵", title="프링글스클래식110G"),
        parse_catalog_title(manufacturer="켈로그", category="감자스낵", title="프링글스 오리지날110G"),
    ]
    groups, _ = cluster_parsed_titles(items)
    assert len(groups) == 2


def test_canonicalize_csv_rows_builds_reference_variants():
    rows = [
        {
            "manufacturer": "농심",
            "category": "감자스낵",
            "title": "농심)프링글스클래식110G",
            "volume_options": ["110G"],
            "category_major": "과자",
            "category_mid": "스낵",
        },
        {
            "manufacturer": "농심",
            "category": "감자스낵",
            "title": "프링글스양파맛 53G",
            "volume_options": ["53G"],
        },
    ]
    groups, medium = canonicalize_csv_rows(rows)
    pringles = next(g for g in groups if g.canonical_title == "프링글스")
    assert len(pringles.members) == 2
    assert set(pringles.volume_options) >= {"110G", "53G"}
    assert len(pringles.reference_variants) == 2
    assert pringles.category_major == "과자"
    assert isinstance(medium, list)


def test_cluster_merges_same_maker_item_across_wrong_categories():
    items = [
        parse_catalog_title(
            manufacturer="제주특별자치도개발공사",
            category="일반생수",
            title="제주삼다수2L",
        ),
        parse_catalog_title(
            manufacturer="제주특별자치도개발공사",
            category="커피음료",
            title="제주삼다수500ML",
        ),
        parse_catalog_title(
            manufacturer="광동",
            category="일반생수",
            title="광동)제주삼다수",
        ),
    ]
    groups, _ = cluster_parsed_titles(items)
    jeju = [
        g
        for g in groups
        if g.manufacturer == "제주특별자치도개발공사" and g.canonical_title == "제주삼다수"
    ]
    gwangdong = [g for g in groups if g.manufacturer == "광동"]
    assert len(jeju) == 1
    assert len(jeju[0].members) == 2
    assert jeju[0].category == "일반생수"
    assert len(gwangdong) == 1


def test_cluster_merges_paldo_sikhye_split_categories():
    items = [
        parse_catalog_title(manufacturer="팔도", category="비타민/에너지음료", title="팔도비락식혜1.8L"),
        parse_catalog_title(manufacturer="팔도", category="전통차음료", title="팔도비락식혜238ML"),
        parse_catalog_title(manufacturer="팔도", category="전통차음료", title="팔도비락식혜500ML"),
        parse_catalog_title(manufacturer="비락식혜", category="과일음료", title="비락식혜1.2L"),
    ]
    groups, _ = cluster_parsed_titles(items)
    paldo = [g for g in groups if g.manufacturer == "팔도"]
    other = [g for g in groups if g.manufacturer == "비락식혜"]
    assert len(paldo) == 1
    assert len(paldo[0].members) == 3
    assert paldo[0].canonical_title == "비락식혜"
    assert len(other) == 1


def test_parse_collapses_duplicated_trailing_token():
    repeated = parse_catalog_title(
        manufacturer="롯데칠성음료",
        category="과일음료",
        title="롯데제주사랑감귤사랑1.2L",
    )
    short = parse_catalog_title(
        manufacturer="롯데칠성음료",
        category="일반생수",
        title="롯데제주사랑감귤500ML",
    )
    assert repeated.canonical_title == "제주사랑감귤"
    assert short.canonical_title == "제주사랑감귤"
    assert repeated.base_key == short.base_key
    assert "1.2L" in repeated.volumes
    assert "500ML" in short.volumes


def test_cluster_merges_same_maker_gamtul_near_duplicates_across_categories():
    items = [
        parse_catalog_title(
            manufacturer="롯데칠성음료",
            category="과일음료",
            title="롯데제주사랑감귤사랑1.2L",
        ),
        parse_catalog_title(
            manufacturer="롯데칠성음료",
            category="과일음료",
            title="롯데제주사랑감귤사랑1.8L",
        ),
        parse_catalog_title(
            manufacturer="롯데칠성음료",
            category="채소음료",
            title="롯데제주사랑감귤사랑1.5L",
        ),
        parse_catalog_title(
            manufacturer="롯데칠성음료",
            category="일반생수",
            title="롯데제주사랑감귤500ML",
        ),
    ]
    groups, _ = cluster_parsed_titles(items)
    lotte = [g for g in groups if g.manufacturer == "롯데칠성음료"]
    assert len(lotte) == 1
    assert len(lotte[0].members) == 4
    assert lotte[0].canonical_title == "제주사랑감귤"
    assert set(lotte[0].volume_options) >= {"1.2L", "1.8L", "1.5L", "500ML"}


def test_cluster_keeps_gamtul_juice_apart_from_plain_gamtul():
    items = [
        parse_catalog_title(manufacturer="롯데칠성음료", category="과일음료", title="사랑감귤1.5L"),
        parse_catalog_title(manufacturer="롯데칠성음료", category="과일음료", title="사랑감귤주스1.5L"),
    ]
    groups, _ = cluster_parsed_titles(items)
    titles = {g.canonical_title for g in groups}
    assert "사랑감귤" in titles
    assert "사랑감귤주스" in titles
    assert len(groups) == 2


def test_cluster_keeps_distinct_lotte_gamtul_lines_apart():
    items = [
        parse_catalog_title(
            manufacturer="롯데칠성음료",
            category="과일음료",
            title="롯데제주사랑감귤500ML",
        ),
        parse_catalog_title(
            manufacturer="롯데칠성음료",
            category="과일음료",
            title="롯데쌕쌕제주감귤캔180ML",
        ),
    ]
    groups, _ = cluster_parsed_titles(items)
    assert len(groups) == 2


def test_cluster_does_not_merge_gamtul_across_manufacturers():
    items = [
        parse_catalog_title(
            manufacturer="롯데칠성음료",
            category="과일음료",
            title="롯데제주사랑감귤사랑1.2L",
        ),
        parse_catalog_title(
            manufacturer="웅진식품",
            category="과일음료",
            title="웅진자연은내사랑감귤1.5L",
        ),
    ]
    groups, _ = cluster_parsed_titles(items)
    assert len(groups) == 2
    assert {g.manufacturer for g in groups} == {"롯데칠성음료", "웅진식품"}


def test_cluster_keeps_packaging_suffix_as_separate_card():
    items = [
        parse_catalog_title(
            manufacturer="LG생활건강",
            category="주방세제",
            title="메소드주방세제핑크그레이프후루트향",
        ),
        parse_catalog_title(
            manufacturer="LG생활건강",
            category="주방세제",
            title="메소드주방세제핑크그레이프후루트향리필",
        ),
    ]
    groups, medium = cluster_parsed_titles(items)
    assert len(groups) == 2
    assert any(conf >= 0.80 for _, _, conf in medium)


def test_parse_collapses_consecutive_repeated_name():
    parsed = parse_catalog_title(
        manufacturer="농심",
        category="라면",
        title="신라면신라면120G",
    )
    assert parsed.canonical_title == "신라면"


def test_card_identity_key_collapses_gamtul_near_duplicates():
    maker = "롯데칠성음료"
    assert card_identity_key(maker, "롯데제주사랑감귤") == card_identity_key(
        maker, "롯데제주사랑감귤사랑"
    )
    assert card_identity_key(maker, "롯데제주사랑감귤") != card_identity_key(
        "웅진식품", "롯데제주사랑감귤"
    )
    assert card_identity_key(maker, "사랑감귤") != card_identity_key(maker, "사랑감귤주스")


def test_parse_unifies_equivalent_volume_spellings():
    titles = [
        "제주삼다수1L",
        "제주삼다수1리터",
        "제주삼다수1ℓ",
        "제주삼다수1000ml",
        "제주삼다수1000mL",
        "제주삼다수1000밀리리터",
        "제주삼다수1 liter",
    ]
    parsed = [
        parse_catalog_title(
            manufacturer="제주특별자치도개발공사",
            category="일반생수",
            title=title,
        )
        for title in titles
    ]
    assert {item.canonical_title for item in parsed} == {"제주삼다수"}
    assert {item.volumes for item in parsed} == {("1L",)}


def test_parse_unifies_ml_below_liter_and_mass_equivalents():
    half = parse_catalog_title(
        manufacturer="제주특별자치도개발공사",
        category="일반생수",
        title="제주삼다수0.5L",
    )
    five_hundred = parse_catalog_title(
        manufacturer="제주특별자치도개발공사",
        category="일반생수",
        title="제주삼다수500ml",
    )
    assert half.canonical_title == five_hundred.canonical_title == "제주삼다수"
    assert half.volumes == five_hundred.volumes == ("500ML",)

    grams = parse_catalog_title(manufacturer="농심", category="스낵", title="감자깡500그램")
    kilo = parse_catalog_title(manufacturer="농심", category="스낵", title="감자깡0.5kg")
    assert grams.canonical_title == kilo.canonical_title == "감자깡"
    assert grams.volumes == kilo.volumes == ("500G",)
    kilo_full = parse_catalog_title(manufacturer="농심", category="스낵", title="감자깡1000g")
    assert kilo_full.volumes == ("1KG",)


def test_cluster_merges_same_item_across_volume_spellings():
    items = [
        parse_catalog_title(
            manufacturer="제주특별자치도개발공사",
            category="일반생수",
            title="제주삼다수1리터",
        ),
        parse_catalog_title(
            manufacturer="제주특별자치도개발공사",
            category="일반생수",
            title="제주삼다수1000mL",
        ),
        parse_catalog_title(
            manufacturer="제주특별자치도개발공사",
            category="커피음료",
            title="제주삼다수1ℓ",
        ),
    ]
    groups, _ = cluster_parsed_titles(items)
    assert len(groups) == 1
    assert groups[0].canonical_title == "제주삼다수"
    assert groups[0].volume_options == ["1L"]


def test_cluster_keeps_flavors_and_other_products_apart_when_volumes_match():
    items = [
        parse_catalog_title(manufacturer="롯데칠성음료", category="과일음료", title="사랑감귤1L"),
        parse_catalog_title(manufacturer="롯데칠성음료", category="과일음료", title="사랑감귤주스1리터"),
        parse_catalog_title(manufacturer="롯데칠성음료", category="과일음료", title="쌕쌕제주감귤캔1000ml"),
    ]
    groups, _ = cluster_parsed_titles(items)
    titles = {g.canonical_title for g in groups}
    assert titles == {"사랑감귤", "사랑감귤주스", "쌕쌕제주감귤캔"}


def test_parse_does_not_treat_kilocalorie_as_kilogram():
    parsed = parse_catalog_title(
        manufacturer="대웅생명과학",
        category="파우치음료",
        title="글램디4킬로칼로리곤약워터젤리복숭아맛150G",
    )
    assert "4킬로칼로리" in parsed.canonical_title
    assert parsed.volumes == ("150G",)


def test_card_identity_key_unifies_volume_spellings():
    maker = "제주특별자치도개발공사"
    assert card_identity_key(maker, "제주삼다수1L") == card_identity_key(maker, "제주삼다수1리터")
    assert card_identity_key(maker, "제주삼다수1L") == card_identity_key(maker, "제주삼다수1000ml")
    assert card_identity_key(maker, "제주삼다수1L") != card_identity_key("농심", "제주삼다수1리터")


def test_strip_brand_paren_and_dangling_maker_token():
    parsed = parse_catalog_title(
        manufacturer="롯데칠성음료",
        category="커피음료",
        title="롯데)레쓰비190ml",
    )
    assert parsed.canonical_title == "레쓰비"
    no_paren = parse_catalog_title(
        manufacturer="롯데칠성음료",
        category="커피음료",
        title="롯데레쓰비175ML",
    )
    assert no_paren.canonical_title == "레쓰비"


def test_card_identity_collapses_letsbe_brand_prefix_noise():
    assert card_identity_key("롯데칠성음료", "롯데)레쓰비190ml") == card_identity_key(
        "롯데칠성음료", "롯데레쓰비175ML"
    )
    lotte_en = parse_catalog_title(
        manufacturer="롯데칠성",
        category="커피음료",
        title="LOTTE레쓰비 마일드 커피150ML",
    )
    assert "레쓰비" in lotte_en.canonical_title.replace(" ", "")
    assert card_identity_key("롯데칠성음료", "롯데)레쓰비190ml")[0] == card_identity_key(
        "롯데칠성", "LOTTE레쓰비 마일드 커피150ML"
    )[0]
    kko = parse_catalog_title(
        manufacturer="롯데제과", category="스낵", title="롯데)꼬깔콘매콤달콤72G"
    )
    assert kko.canonical_title.startswith("꼬깔콘")
    assert card_identity_key("롯데제과", "롯데)꼬깔콘매콤달콤72G") != card_identity_key(
        "롯데칠성음료", "롯데)레쓰비190ml"
    )


def test_card_identity_collapses_flavor_tokens_in_title():
    maker = "농심"
    assert card_identity_key(maker, "농심)프링글스버터캬라멜110G") == card_identity_key(
        maker, "프링글스양파맛 53G"
    )
    assert card_identity_key(maker, "프링글스양파맛 53G") != card_identity_key(
        maker, "농심감자깡75G"
    )


def test_card_identity_unifies_chilsung_maker_spellings():
    assert card_identity_key("롯데칠성음료", "롯데레쓰비마일드커피240ML") == card_identity_key(
        "롯데칠성", "LOTTE레쓰비 마일드 커피150ML"
    )


def test_card_identity_collapses_letsbe_asia_trip_prefix_noise():
    assert card_identity_key("롯데칠성음료", "롯데)레쓰비아시아트립쏠트커피240ML") == card_identity_key(
        "롯데칠성음료", "레쓰비아시아트립쏠트커피240ML"
    )


def test_card_identity_collapses_dole_fruitbowl_flavors():
    maker = "Dole 코리아"
    assert card_identity_key(maker, "Dole 후룻볼 트로피칼 4입 100%주스") == card_identity_key(
        maker, "Dole 후룻볼 복숭아 4입 100%주스"
    )
    parsed = parse_catalog_title(
        manufacturer=maker,
        category="과일통조림",
        title="Dole 후룻볼 복숭아 4입 100%주스",
    )
    assert "복숭아" in parsed.flavors or "트로피칼" not in parsed.canonical_title.replace(" ", "")
    assert "후룻볼" in parsed.canonical_title.replace(" ", "")


def test_card_identity_collapses_petitchel_water_jelly_flavors():
    assert card_identity_key("CJ제일제당", "CJ 쁘띠첼워터젤리사과 130ML") == card_identity_key(
        "씨제이제일제당", "씨제이쁘띠첼워터젤리포도"
    )


def test_card_identity_keeps_fruit_juice_when_fruit_is_the_item():
    assert card_identity_key("델몬트", "델몬트사과주스") != card_identity_key(
        "델몬트", "델몬트포도주스"
    )


def test_card_identity_keeps_bare_fruit_juice_when_remainder_is_type_noun():
    apple = parse_catalog_title(
        manufacturer="농심",
        category="과일음료",
        title="사과주스",
    )
    grape = parse_catalog_title(
        manufacturer="농심",
        category="과일음료",
        title="포도주스",
    )
    assert "사과" in apple.canonical_title.replace(" ", "")
    assert "포도" in grape.canonical_title.replace(" ", "")
    assert apple.canonical_title != grape.canonical_title


def test_menu_axis_matches_flavor_variant_titles():
    maker = "Dole 코리아"
    peach = "Dole 후룻볼 복숭아 4입 100%주스"
    tropical = "Dole 후룻볼 트로피칼 4입 100%주스"
    assert matches_menu_axis(maker, peach, tropical)
    assert matches_menu_axis(maker, tropical, peach)
    assert matches_menu_axis(maker, peach, "후룻볼")
    assert not matches_menu_axis(maker, peach, "쁘띠첼워터젤리")


def test_brand_axis_matches_chilsung_spellings():
    assert matches_brand_axis("롯데칠성음료", "롯데칠성")
    assert not matches_brand_axis("롯데제과", "롯데칠성음료")


def test_axis_facets_collapse_flavor_variants_to_one_menu():
    brands, menus = collapse_axis_facets(
        [
            ("Dole 코리아", "Dole 후룻볼 복숭아 4입 100%주스"),
            ("Dole 코리아", "Dole 후룻볼 트로피칼 4입 100%주스"),
            ("CJ제일제당", "CJ 쁘띠첼워터젤리사과 130ML"),
            ("씨제이제일제당", "씨제이쁘띠첼워터젤리포도"),
        ]
    )
    assert len(brands) == 2
    assert len(menus) == 2
    menu_names = " ".join(row["name"] for row in menus)
    assert "후룻볼" in menu_names.replace(" ", "")
    assert "쁘띠첼" in menu_names.replace(" ", "")
    assert all("복숭아" not in row["name"] for row in menus)
    assert all("트로피칼" not in row["name"] for row in menus)
