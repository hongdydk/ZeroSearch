"""Reviewed options under catalog cards.

Revision ID: 020
Revises: 019
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB, UUID

revision = "020"
down_revision = "019"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "catalog_variants",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("catalog_product_id", UUID(as_uuid=True), sa.ForeignKey("catalog_products.id"), nullable=False),
        sa.Column("name", sa.String(100), nullable=False, server_default="기본"),
        sa.Column("unit_amount", sa.Numeric(12, 3), nullable=False),
        sa.Column("unit", sa.String(10), nullable=False),
        sa.Column("pack_count", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("image_url", sa.String(500), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.CheckConstraint("pack_count >= 1", name="ck_catalog_variants_pack_count_positive"),
        sa.UniqueConstraint("catalog_product_id", "name", "unit_amount", "unit", "pack_count", name="uq_catalog_variants_configuration"),
    )
    op.create_index("ix_catalog_variants_catalog_product_id", "catalog_variants", ["catalog_product_id"])
    op.add_column("products", sa.Column("variant_id", UUID(as_uuid=True), sa.ForeignKey("catalog_variants.id"), nullable=True))
    op.create_index("ix_products_variant_id", "products", ["variant_id"])
    op.add_column("catalog_intake_drafts", sa.Column("variant_name", sa.String(100), nullable=True))
    op.add_column("catalog_intake_drafts", sa.Column("variant_proposals", JSONB(), nullable=False, server_default="[]"))


def downgrade() -> None:
    op.drop_column("catalog_intake_drafts", "variant_proposals")
    op.drop_column("catalog_intake_drafts", "variant_name")
    op.drop_index("ix_products_variant_id", table_name="products")
    op.drop_column("products", "variant_id")
    op.drop_index("ix_catalog_variants_catalog_product_id", table_name="catalog_variants")
    op.drop_table("catalog_variants")
