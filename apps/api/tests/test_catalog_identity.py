from app.services.catalog_identity import (
    HIGH_CONFIDENCE,
    canonicalize_csv_rows,
    cluster_parsed_titles,
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
