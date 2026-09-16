"""Seller catalog intake drafts for MD review.

Revision ID: 011
Revises: 010
Create Date: 2026-09-16
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "011"
down_revision: Union[str, None] = "010"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "catalog_intake_drafts",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("seller_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
        sa.Column("manufacturer", sa.String(200), nullable=False),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("category", sa.String(120), nullable=False),
        sa.Column("image_url", sa.String(500), nullable=True),
        sa.Column("flavor", sa.String(50), nullable=True),
        sa.Column("option_label", sa.String(100), nullable=True),
        sa.Column("volume_ml", sa.Integer(), nullable=True),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("price_credits", sa.Integer(), nullable=False),
        sa.Column("stock", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("catalog_product_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("product_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("reviewed_by", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["seller_id"], ["sellers.id"]),
        sa.ForeignKeyConstraint(["catalog_product_id"], ["catalog_products.id"]),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"]),
        sa.ForeignKeyConstraint(["reviewed_by"], ["users.id"]),
        sa.CheckConstraint("stock >= 0", name="ck_catalog_intake_drafts_stock_nonnegative"),
        sa.CheckConstraint(
            "status IN ('pending', 'attached', 'promoted')",
            name="ck_catalog_intake_drafts_status",
        ),
        sa.CheckConstraint("price_credits > 0", name="ck_catalog_intake_drafts_price_positive"),
    )
    op.create_index("ix_catalog_intake_drafts_seller_id", "catalog_intake_drafts", ["seller_id"])
    op.create_index("ix_catalog_intake_drafts_status", "catalog_intake_drafts", ["status"])
    op.create_index(
        "ix_catalog_intake_drafts_catalog_product_id",
        "catalog_intake_drafts",
        ["catalog_product_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_catalog_intake_drafts_catalog_product_id", table_name="catalog_intake_drafts")
    op.drop_index("ix_catalog_intake_drafts_status", table_name="catalog_intake_drafts")
    op.drop_index("ix_catalog_intake_drafts_seller_id", table_name="catalog_intake_drafts")
    op.drop_table("catalog_intake_drafts")
