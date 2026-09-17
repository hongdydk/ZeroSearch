"""Guest L1 tags and storage on catalog_products.

Revision ID: 012
Revises: 011
Create Date: 2026-09-17
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "012"
down_revision: Union[str, None] = "011"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "catalog_products",
        sa.Column("l1_tags", postgresql.JSONB(), nullable=False, server_default="[]"),
    )
    op.add_column(
        "catalog_products",
        sa.Column("storage", sa.String(20), nullable=True),
    )
    op.create_index(
        "ix_catalog_products_l1_tags",
        "catalog_products",
        ["l1_tags"],
        postgresql_using="gin",
    )
    op.create_index("ix_catalog_products_storage", "catalog_products", ["storage"])


def downgrade() -> None:
    op.drop_index("ix_catalog_products_storage", table_name="catalog_products")
    op.drop_index("ix_catalog_products_l1_tags", table_name="catalog_products")
    op.drop_column("catalog_products", "storage")
    op.drop_column("catalog_products", "l1_tags")
