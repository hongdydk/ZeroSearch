"""Catalog remarge: reference_variants + alias table.

Revision ID: 007
Revises: 006
Create Date: 2026-09-06
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "007"
down_revision: Union[str, None] = "006"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "catalog_products",
        sa.Column(
            "reference_variants",
            postgresql.JSONB(),
            nullable=False,
            server_default="[]",
        ),
    )
    op.create_table(
        "catalog_product_aliases",
        sa.Column("alias_id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("canonical_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("original_title", sa.String(200), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["canonical_id"],
            ["catalog_products.id"],
            ondelete="CASCADE",
        ),
    )
    op.create_index(
        "ix_catalog_product_aliases_canonical_id",
        "catalog_product_aliases",
        ["canonical_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_catalog_product_aliases_canonical_id", table_name="catalog_product_aliases")
    op.drop_table("catalog_product_aliases")
    op.drop_column("catalog_products", "reference_variants")
