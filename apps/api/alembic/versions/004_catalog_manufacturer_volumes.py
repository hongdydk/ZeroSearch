"""Catalog manufacturer, MFDS categories, volume options.

Revision ID: 004
Revises: 003
Create Date: 2026-09-05
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "004"
down_revision: Union[str, None] = "003"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "catalog_products",
        sa.Column("manufacturer", sa.String(200), nullable=False, server_default=""),
    )
    op.add_column(
        "catalog_products",
        sa.Column("category_major", sa.String(120), nullable=True),
    )
    op.add_column(
        "catalog_products",
        sa.Column("category_mid", sa.String(120), nullable=True),
    )
    op.add_column(
        "catalog_products",
        sa.Column("volume_options", postgresql.JSONB(), nullable=False, server_default="[]"),
    )
    op.alter_column(
        "catalog_products",
        "category",
        existing_type=sa.String(50),
        type_=sa.String(120),
        existing_nullable=False,
    )
    op.create_index("ix_catalog_products_manufacturer", "catalog_products", ["manufacturer"])
    op.create_unique_constraint(
        "uq_catalog_products_maker_category_title",
        "catalog_products",
        ["manufacturer", "category", "title"],
    )


def downgrade() -> None:
    op.drop_constraint("uq_catalog_products_maker_category_title", "catalog_products", type_="unique")
    op.drop_index("ix_catalog_products_manufacturer", table_name="catalog_products")
    op.alter_column(
        "catalog_products",
        "category",
        existing_type=sa.String(120),
        type_=sa.String(50),
        existing_nullable=False,
    )
    op.drop_column("catalog_products", "volume_options")
    op.drop_column("catalog_products", "category_mid")
    op.drop_column("catalog_products", "category_major")
    op.drop_column("catalog_products", "manufacturer")
