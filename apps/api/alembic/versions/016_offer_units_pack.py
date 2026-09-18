"""Seller offer unit amount, unit, pack count; allow unpriced drafts.

Revision ID: 016
Revises: 015
Create Date: 2026-09-18
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "016"
down_revision: Union[str, None] = "015"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _add_unit_columns(table: str) -> None:
    op.add_column(table, sa.Column("unit_amount", sa.Numeric(12, 3), nullable=True))
    op.add_column(table, sa.Column("unit", sa.String(10), nullable=True))
    op.add_column(
        table,
        sa.Column("pack_count", sa.Integer(), nullable=False, server_default="1"),
    )


def _drop_unit_columns(table: str) -> None:
    op.drop_column(table, "pack_count")
    op.drop_column(table, "unit")
    op.drop_column(table, "unit_amount")


def upgrade() -> None:
    _add_unit_columns("products")
    op.create_check_constraint("ck_products_pack_count_positive", "products", "pack_count >= 1")
    _add_unit_columns("catalog_intake_drafts")
    op.create_check_constraint(
        "ck_catalog_intake_drafts_pack_count_positive",
        "catalog_intake_drafts",
        "pack_count >= 1",
    )
    op.drop_constraint("ck_catalog_intake_drafts_price_positive", "catalog_intake_drafts", type_="check")
    op.create_check_constraint(
        "ck_catalog_intake_drafts_price_nonnegative",
        "catalog_intake_drafts",
        "price_credits >= 0",
    )


def downgrade() -> None:
    op.drop_constraint(
        "ck_catalog_intake_drafts_price_nonnegative",
        "catalog_intake_drafts",
        type_="check",
    )
    op.create_check_constraint(
        "ck_catalog_intake_drafts_price_positive",
        "catalog_intake_drafts",
        "price_credits > 0",
    )
    op.drop_constraint(
        "ck_catalog_intake_drafts_pack_count_positive",
        "catalog_intake_drafts",
        type_="check",
    )
    _drop_unit_columns("catalog_intake_drafts")
    op.drop_constraint("ck_products_pack_count_positive", "products", type_="check")
    _drop_unit_columns("products")
