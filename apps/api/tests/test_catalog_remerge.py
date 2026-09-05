"""카탈로그 재병합 단위·통합 테스트."""

from __future__ import annotations

import csv
import os
import uuid
from pathlib import Path
from unittest.mock import MagicMock

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.models import CatalogProduct, CatalogProductAlias, Product, Seller, User
from app.services.catalog_identity import canonicalize_csv_rows
from app.services.catalog_remerge import (
    apply_db_remarge,
    plan_db_remarge,
    resolve_catalog_product,
)

REPO_ROOT = Path(__file__).resolve().parents[3]
CSV_PATH = REPO_ROOT / "data" / "aihub-catalog.csv"


def test_csv_full_dry_run_canonical_reduces_cards():
    if not CSV_PATH.is_file():
        pytest.skip("data/aihub-catalog.csv 없음")

    rows: list[dict] = []
    with CSV_PATH.open(encoding="utf-8-sig", newline="") as handle:
        for raw in csv.DictReader(handle):
            maker = (raw.get("제조사") or "").strip()
            title = (raw.get("품목명") or "").strip()
            category = (raw.get("소분류") or "").strip()
            if not maker or not title or not category:
                continue
            vols = [p.strip() for p in (raw.get("용량") or "").split("|") if p.strip() and p.strip() != "해당없음"]
            rows.append(
                {
                    "manufacturer": maker,
                    "title": title,
                    "category": category,
                    "volume_options": vols,
                    "barcode": (raw.get("바코드") or "").strip() or None,
                    "category_major": (raw.get("대분류") or "").strip() or None,
                    "category_mid": (raw.get("중분류") or "").strip() or None,
                }
            )

    groups, medium = canonicalize_csv_rows(rows)
    assert len(groups) < len(rows)
    assert len(groups) > 0
    # 중간 신뢰는 자동 병합에 포함되지 않음(별도 후보만)
    assert isinstance(medium, list)
    # 프링글스류가 있으면 한 장으로 줄었는지 샘플
    pringles = [g for g in groups if "프링글스" in g.canonical_title or any("프링글스" in m.raw_title for m in g.members)]
    if pringles:
        assert any(len(g.members) >= 2 or len(g.reference_variants) >= 2 for g in pringles)


def test_resolve_catalog_product_via_alias():
    survivor_id = uuid.uuid4()
    alias_id = uuid.uuid4()
    survivor = CatalogProduct(
        id=survivor_id,
        title="프링글스",
        manufacturer="농심켈로그",
        category="스낵",
        volume_options=[],
        reference_variants=[],
    )
    alias = CatalogProductAlias(
        alias_id=alias_id,
        canonical_id=survivor_id,
        original_title="프링글스양파맛53G",
    )

    db = MagicMock()
    db.get.side_effect = lambda model, key: {
        (CatalogProduct, alias_id): None,
        (CatalogProductAlias, alias_id): alias,
        (CatalogProduct, survivor_id): survivor,
    }.get((model, key))

    resolved = resolve_catalog_product(db, alias_id)
    assert resolved is survivor


@pytest.mark.skipif(
    os.environ.get("RUN_PG_CATALOG_REMERGE") != "1",
    reason="RUN_PG_CATALOG_REMERGE=1 일 때만 PostgreSQL 재병합 테스트 실행",
)
def test_pg_apply_remarge_moves_offers_and_aliases():
    database_url = os.environ.get("DATABASE_URL")
    if not database_url or "postgresql" not in database_url:
        pytest.skip("DATABASE_URL(postgresql) 필요")

    engine = create_engine(database_url, pool_pre_ping=True)
    SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    db: Session = SessionLocal()
    try:
        user = User(
            id=uuid.uuid4(),
            email=f"remerge-{uuid.uuid4().hex[:8]}@example.com",
            password_hash="x",
            display_name="remerge",
        )
        db.add(user)
        db.flush()
        seller = Seller(
            id=uuid.uuid4(),
            user_id=user.id,
            shop_name="remerge-shop",
            slug=f"remerge-{uuid.uuid4().hex[:8]}",
            status="active",
            seller_type="platform",
        )
        db.add(seller)

        a = CatalogProduct(
            id=uuid.uuid4(),
            # canonical 제목을 가진 행이 중복 삭제 대상이어도 unique 위반 없이
            # 오퍼가 있는 b가 생존해 이 제목을 이어받아야 한다.
            title="프링글스",
            manufacturer="농심켈로그",
            category="스낵류",
            volume_options=["110G"],
            reference_variants=[],
            price_unit="each",
        )
        b = CatalogProduct(
            id=uuid.uuid4(),
            title="프링글스양파맛53G",
            manufacturer="농심켈로그",
            category="스낵류",
            volume_options=["53G"],
            reference_variants=[],
            price_unit="each",
        )
        db.add_all([a, b])
        db.flush()

        offer = Product(
            id=uuid.uuid4(),
            seller_id=seller.id,
            catalog_product_id=b.id,
            title="프링글스 오퍼",
            price_credits=1000,
            stock=5,
            category="스낵류",
            status="published",
            option_label="53G",
        )
        db.add(offer)
        db.flush()

        _, dry = plan_db_remarge(db)
        assert dry.cards_reduced >= 1

        report = apply_db_remarge(db)
        db.flush()
        assert report.applied
        assert report.cards_reduced >= 1

        survivor = resolve_catalog_product(db, a.id) or resolve_catalog_product(db, b.id)
        assert survivor is not None
        db.refresh(offer)
        assert offer.catalog_product_id == survivor.id

        lost_id = a.id if survivor.id == b.id else b.id
        assert resolve_catalog_product(db, lost_id) is not None
        assert resolve_catalog_product(db, lost_id).id == survivor.id
        assert db.get(CatalogProductAlias, lost_id) is not None

        # 멱등
        report2 = apply_db_remarge(db)
        assert report2.cards_reduced == 0

        db.rollback()
    finally:
        db.rollback()
        db.close()
        engine.dispose()
