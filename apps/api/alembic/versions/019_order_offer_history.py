"""Preserve order offer identity when a seller deletes an offer.

Revision ID: 019
Revises: 018
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision = "019"
down_revision = "018"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("order_items", sa.Column("catalog_product_id", UUID(as_uuid=True), nullable=True))
    op.execute(
        "UPDATE order_items SET catalog_product_id = products.catalog_product_id "
        "FROM products WHERE order_items.product_id = products.id"
    )
    op.drop_constraint("order_items_product_id_fkey", "order_items", type_="foreignkey")


def downgrade() -> None:
    op.create_foreign_key(
        "order_items_product_id_fkey", "order_items", "products", ["product_id"], ["id"]
    )
    op.drop_column("order_items", "catalog_product_id")
