"""기존 catalog_products 행을 정규화 규칙으로 재병합."""

from __future__ import annotations

import json
from collections import defaultdict
from dataclasses import asdict, dataclass
from typing import Any
from uuid import UUID

from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.models import CatalogProduct, CatalogProductAlias, Product
from app.services.catalog_identity import (
    HIGH_CONFIDENCE,
    CanonicalGroup,
    ParsedCatalogTitle,
    ReferenceVariant,
    cluster_parsed_titles,
    is_volume_only_title,
    parse_catalog_title,
)


@dataclass
class RemargeReport:
    source_rows: int
    groups: int
    merged_groups: int
    cards_reduced: int
    offers_moved: int
    aliases_created: int
    medium_candidates: list[dict[str, Any]]
    applied: bool

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class VolumeTitleRepairReport:
    affected_rows: int
    source_variants: int
    target_groups: int
    missing_targets: list[dict[str, str]]
    rows_with_offers: list[str]
    aliases_repointed: int
    applied: bool

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class _VolumeTitleRepairPlan:
    bad: CatalogProduct
    targets_by_title: dict[str, CatalogProduct]
    title_by_original: dict[str, str]
    primary_title: str


def _merge_volume_options(*groups: list[str]) -> list[str]:
    seen: set[str] = set()
    merged: list[str] = []
    for group in groups:
        for item in group:
            if not item or item in seen:
                continue
            seen.add(item)
            merged.append(item)
    return merged


def _merge_reference_variants(*groups: list[dict] | list[ReferenceVariant]) -> list[dict]:
    seen: set[str] = set()
    out: list[dict] = []
    for group in groups:
        for item in group:
            data = item.to_dict() if isinstance(item, ReferenceVariant) else dict(item)
            key = str(data.get("originalTitle") or "")
            if not key or key in seen:
                continue
            seen.add(key)
            out.append(data)
    return out


def plan_db_remarge(db: Session) -> tuple[list[tuple[CanonicalGroup, list[CatalogProduct]]], RemargeReport]:
    catalogs = list(db.scalars(select(CatalogProduct).order_by(CatalogProduct.created_at)).all())
    parsed_items: list[ParsedCatalogTitle] = []
    by_raw: dict[tuple[str, str, str], list[CatalogProduct]] = defaultdict(list)

    for catalog in catalogs:
        parsed = parse_catalog_title(
            manufacturer=catalog.manufacturer or "",
            category=catalog.category,
            title=catalog.title,
            volumes_hint=list(catalog.volume_options or []),
        )
        parsed_items.append(parsed)
        by_raw[(parsed.manufacturer, parsed.category, parsed.raw_title)].append(catalog)

    groups, medium = cluster_parsed_titles(parsed_items, auto_threshold=HIGH_CONFIDENCE)

    planned: list[tuple[CanonicalGroup, list[CatalogProduct]]] = []
    for group in groups:
        rows: list[CatalogProduct] = []
        seen_ids: set[UUID] = set()
        for member in group.members:
            for catalog in by_raw.get((member.manufacturer, member.category, member.raw_title), []):
                if catalog.id in seen_ids:
                    continue
                seen_ids.add(catalog.id)
                rows.append(catalog)
        if rows:
            planned.append((group, rows))

    merged_groups = sum(1 for _, rows in planned if len(rows) > 1)
    cards_reduced = sum(len(rows) - 1 for _, rows in planned if len(rows) > 1)
    report = RemargeReport(
        source_rows=len(catalogs),
        groups=len(planned),
        merged_groups=merged_groups,
        cards_reduced=cards_reduced,
        offers_moved=0,
        aliases_created=0,
        medium_candidates=[
            {
                "manufacturer": a.manufacturer,
                "category": a.category,
                "left": a.raw_title,
                "right": b.raw_title,
                "confidence": round(conf, 3),
            }
            for a, b, conf in medium
        ],
        applied=False,
    )
    return planned, report


def _pick_survivor(rows: list[CatalogProduct], offer_counts: dict[UUID, int]) -> CatalogProduct:
    return max(
        rows,
        key=lambda r: (
            offer_counts.get(r.id, 0),
            1 if (r.image_url or "").startswith("http") else 0,
            r.created_at or r.id.hex,
        ),
    )


def apply_db_remarge(db: Session) -> RemargeReport:
    planned, report = plan_db_remarge(db)
    if not planned:
        report.applied = True
        return report

    ids = [row.id for _, rows in planned for row in rows]
    offer_counts: dict[UUID, int] = defaultdict(int)
    if ids:
        for catalog_id, count in db.execute(
            select(Product.catalog_product_id, func.count())
            .where(Product.catalog_product_id.in_(ids))
            .group_by(Product.catalog_product_id)
        ):
            offer_counts[catalog_id] = int(count)

    offers_moved = 0
    aliases_created = 0

    for group, rows in planned:
        if len(rows) == 1:
            survivor = rows[0]
            # 단독 행도 참고 변형·canonical title 갱신
            refs = _merge_reference_variants(
                list(survivor.reference_variants or []),
                [v.to_dict() for v in group.reference_variants],
            )
            if survivor.title != group.canonical_title:
                # unique 충돌 피하려고 같은 키가 없을 때만 제목 변경
                clash = db.scalar(
                    select(CatalogProduct.id).where(
                        CatalogProduct.manufacturer == survivor.manufacturer,
                        CatalogProduct.category == survivor.category,
                        CatalogProduct.title == group.canonical_title,
                        CatalogProduct.id != survivor.id,
                    )
                )
                if clash is None:
                    survivor.title = group.canonical_title
            survivor.volume_options = _merge_volume_options(
                list(survivor.volume_options or []),
                group.volume_options,
            )
            survivor.reference_variants = refs
            if group.category_major and not survivor.category_major:
                survivor.category_major = group.category_major
            if group.category_mid and not survivor.category_mid:
                survivor.category_mid = group.category_mid
            continue

        survivor = _pick_survivor(rows, offer_counts)
        dupes = [r for r in rows if r.id != survivor.id]

        for dupe in dupes:
            moved = db.execute(
                update(Product)
                .where(Product.catalog_product_id == dupe.id)
                .values(catalog_product_id=survivor.id)
            )
            offers_moved += moved.rowcount or 0

            existing_alias = db.get(CatalogProductAlias, dupe.id)
            if existing_alias is None:
                db.add(
                    CatalogProductAlias(
                        alias_id=dupe.id,
                        canonical_id=survivor.id,
                        original_title=dupe.title,
                    )
                )
                aliases_created += 1
            else:
                existing_alias.canonical_id = survivor.id
                existing_alias.original_title = dupe.title

        refs = _merge_reference_variants(
            list(survivor.reference_variants or []),
            *[list(d.reference_variants or []) for d in dupes],
            [v.to_dict() for v in group.reference_variants],
            [
                ReferenceVariant(
                    original_title=d.title,
                    volumes=list(d.volume_options or []),
                ).to_dict()
                for d in dupes
            ],
        )
        vols = _merge_volume_options(
            list(survivor.volume_options or []),
            *[list(d.volume_options or []) for d in dupes],
            group.volume_options,
        )

        # unique: survivor title을 canonical로 바꾸기 전 충돌 행 정리
        clash = db.scalar(
            select(CatalogProduct).where(
                CatalogProduct.manufacturer == survivor.manufacturer,
                CatalogProduct.category == survivor.category,
                CatalogProduct.title == group.canonical_title,
                CatalogProduct.id != survivor.id,
            )
        )
        if clash is not None and clash.id in {d.id for d in dupes}:
            pass  # 곧 삭제
        elif clash is not None:
            # 다른 생존 그룹과 충돌 — 제목은 유지
            group.canonical_title = survivor.title

        # canonical 제목이 중복 행의 현재 제목이면 UPDATE가 DELETE보다 먼저
        # flush되어 unique 위반이 난다. 중복 행을 먼저 제거한다.
        for dupe in dupes:
            db.delete(dupe)
        db.flush()

        survivor.title = group.canonical_title
        survivor.volume_options = vols
        survivor.reference_variants = refs
        if group.category_major:
            survivor.category_major = group.category_major
        if group.category_mid:
            survivor.category_mid = group.category_mid
        if not survivor.image_url:
            for d in dupes:
                if d.image_url:
                    survivor.image_url = d.image_url
                    break

    db.flush()
    report.offers_moved = offers_moved
    report.aliases_created = aliases_created
    report.applied = True
    return report


def plan_volume_title_repair(
    db: Session,
) -> tuple[list[_VolumeTitleRepairPlan], VolumeTitleRepairReport]:
    """v1 괄호 오인으로 용량만 남은 카드를 v2 import 결과로 연결한다."""

    catalogs = list(db.scalars(select(CatalogProduct)).all())
    bad_rows = [
        row
        for row in catalogs
        if is_volume_only_title(row.title) and list(row.reference_variants or [])
    ]
    by_key = {
        (row.manufacturer, row.category, row.title): row
        for row in catalogs
    }
    by_variant: dict[tuple[str, str, str], list[CatalogProduct]] = defaultdict(list)
    for row in catalogs:
        for raw_variant in list(row.reference_variants or []):
            if not isinstance(raw_variant, dict):
                continue
            original_title = str(
                raw_variant.get("originalTitle")
                or raw_variant.get("original_title")
                or ""
            )
            if original_title:
                by_variant[(row.manufacturer, row.category, original_title)].append(row)
    plans: list[_VolumeTitleRepairPlan] = []
    missing_targets: list[dict[str, str]] = []
    source_variants = 0
    target_group_count = 0

    for bad in bad_rows:
        parsed: list[ParsedCatalogTitle] = []
        for raw_variant in list(bad.reference_variants or []):
            if not isinstance(raw_variant, dict):
                continue
            variant = ReferenceVariant.from_dict(raw_variant)
            if not variant.original_title or is_volume_only_title(variant.original_title):
                continue
            parsed.append(
                parse_catalog_title(
                    manufacturer=bad.manufacturer,
                    category=bad.category,
                    title=variant.original_title,
                    volumes_hint=variant.volumes,
                    barcode=variant.barcode,
                )
            )

        if not parsed:
            continue

        groups, _ = cluster_parsed_titles(parsed, auto_threshold=HIGH_CONFIDENCE)
        source_variants += len(parsed)
        target_group_count += len(groups)
        targets_by_title: dict[str, CatalogProduct] = {}
        title_by_original: dict[str, str] = {}

        for group in groups:
            target = by_key.get((bad.manufacturer, bad.category, group.canonical_title))
            if target is None:
                overlap: dict[UUID, tuple[CatalogProduct, int]] = {}
                for member in group.members:
                    for candidate in by_variant.get(
                        (bad.manufacturer, bad.category, member.raw_title), []
                    ):
                        if candidate.id == bad.id or is_volume_only_title(candidate.title):
                            continue
                        current = overlap.get(candidate.id)
                        overlap[candidate.id] = (
                            candidate,
                            (current[1] if current else 0) + 1,
                        )
                if overlap:
                    ranked = sorted(
                        overlap.values(),
                        key=lambda item: (
                            item[1],
                            item[0].title == group.canonical_title,
                        ),
                        reverse=True,
                    )
                    if len(ranked) == 1 or ranked[0][1] > ranked[1][1]:
                        target = ranked[0][0]
            if target is None or target.id == bad.id:
                missing_targets.append(
                    {
                        "catalogId": str(bad.id),
                        "manufacturer": bad.manufacturer,
                        "category": bad.category,
                        "targetTitle": group.canonical_title,
                    }
                )
                continue
            targets_by_title[group.canonical_title] = target
            for member in group.members:
                title_by_original[member.raw_title] = group.canonical_title

        if len(targets_by_title) != len(groups):
            continue

        primary = max(
            groups,
            key=lambda group: (len(group.members), -len(group.canonical_title), group.canonical_title),
        )
        plans.append(
            _VolumeTitleRepairPlan(
                bad=bad,
                targets_by_title=targets_by_title,
                title_by_original=title_by_original,
                primary_title=primary.canonical_title,
            )
        )

    bad_ids = [plan.bad.id for plan in plans]
    rows_with_offers: list[str] = []
    if bad_ids:
        rows_with_offers = [
            str(catalog_id)
            for catalog_id in db.scalars(
                select(Product.catalog_product_id)
                .where(Product.catalog_product_id.in_(bad_ids))
                .distinct()
            ).all()
        ]

    report = VolumeTitleRepairReport(
        affected_rows=len(bad_rows),
        source_variants=source_variants,
        target_groups=target_group_count,
        missing_targets=missing_targets,
        rows_with_offers=rows_with_offers,
        aliases_repointed=0,
        applied=False,
    )
    return plans, report


def apply_volume_title_repair(db: Session) -> VolumeTitleRepairReport:
    plans, report = plan_volume_title_repair(db)
    if report.missing_targets:
        raise RuntimeError(
            f"v2 canonical import 대상이 없습니다: {len(report.missing_targets)}건"
        )
    if report.rows_with_offers:
        raise RuntimeError(
            "용량-only 카드에 판매 오퍼가 있어 자동 분할하지 않습니다: "
            + ", ".join(report.rows_with_offers)
        )

    aliases_repointed = 0
    for plan in plans:
        primary = plan.targets_by_title[plan.primary_title]
        aliases = list(
            db.scalars(
                select(CatalogProductAlias).where(
                    CatalogProductAlias.canonical_id == plan.bad.id
                )
            ).all()
        )
        for alias in aliases:
            target_title = plan.title_by_original.get(
                alias.original_title or "", plan.primary_title
            )
            alias.canonical_id = plan.targets_by_title[target_title].id
            aliases_repointed += 1

        own_alias = db.get(CatalogProductAlias, plan.bad.id)
        if own_alias is None:
            db.add(
                CatalogProductAlias(
                    alias_id=plan.bad.id,
                    canonical_id=primary.id,
                    original_title=plan.bad.title,
                )
            )
            aliases_repointed += 1
        else:
            own_alias.canonical_id = primary.id

        # alias FK를 먼저 새 target으로 옮겨야 bad 삭제의 CASCADE를 피한다.
        db.flush()
        db.delete(plan.bad)
        db.flush()

    report.aliases_repointed = aliases_repointed
    report.applied = True
    return report


def resolve_catalog_product(db: Session, catalog_id: UUID) -> CatalogProduct | None:
    catalog = db.get(CatalogProduct, catalog_id)
    if catalog is not None:
        return catalog
    alias = db.get(CatalogProductAlias, catalog_id)
    if alias is None:
        return None
    return db.get(CatalogProduct, alias.canonical_id)


def format_report(report: RemargeReport) -> str:
    return json.dumps(report.to_dict(), ensure_ascii=False, indent=2)
