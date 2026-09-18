"""Guest L2 tags on catalog_products.

Revision ID: 015
Revises: 014
Create Date: 2026-09-18
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "015"
down_revision: Union[str, None] = "014"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "catalog_products",
        sa.Column("l2_tags", postgresql.JSONB(), nullable=False, server_default="[]"),
    )
    op.create_index(
        "ix_catalog_products_l2_tags",
        "catalog_products",
        ["l2_tags"],
        postgresql_using="gin",
    )


def downgrade() -> None:
    op.drop_index("ix_catalog_products_l2_tags", table_name="catalog_products")
    op.drop_column("catalog_products", "l2_tags")
