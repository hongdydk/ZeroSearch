"""Sellers marketplace schema.

Revision ID: 002
Revises: 001
Create Date: 2026-08-31
"""

import uuid
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "002"
down_revision: Union[str, None] = "001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

PLATFORM_SELLER_ID = uuid.UUID("00000000-0000-4000-8000-000000000001")


def upgrade() -> None:
    op.create_table(
        "sellers",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("shop_name", sa.String(100), nullable=False),
        sa.Column("slug", sa.String(100), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
        sa.Column("seller_type", sa.String(20), nullable=False, server_default="merchant"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_sellers_user_id", "sellers", ["user_id"], unique=True)
    op.create_index("ix_sellers_slug", "sellers", ["slug"], unique=True)

    op.add_column("products", sa.Column("seller_id", postgresql.UUID(as_uuid=True), nullable=True))
    op.add_column(
        "products",
        sa.Column("status", sa.String(20), nullable=False, server_default="published"),
    )

    op.add_column("order_items", sa.Column("seller_id", postgresql.UUID(as_uuid=True), nullable=True))
    op.add_column(
        "order_items",
        sa.Column("fulfillment_status", sa.String(20), nullable=False, server_default="paid"),
    )

    conn = op.get_bind()
    admin_row = conn.execute(
        sa.text("SELECT id FROM users WHERE is_admin = true ORDER BY created_at LIMIT 1")
    ).first()
    if admin_row is not None:
        admin_id = admin_row[0]
        conn.execute(
            sa.text(
                """
                INSERT INTO sellers (id, user_id, shop_name, slug, status, seller_type)
                VALUES (:id, :user_id, :shop_name, :slug, 'active', 'platform')
                ON CONFLICT DO NOTHING
                """
            ),
            {
                "id": str(PLATFORM_SELLER_ID),
                "user_id": str(admin_id),
                "shop_name": "Shopping Mall 공식",
                "slug": "official",
            },
        )
        conn.execute(
            sa.text("UPDATE products SET seller_id = :seller_id WHERE seller_id IS NULL"),
            {"seller_id": str(PLATFORM_SELLER_ID)},
        )
        conn.execute(
            sa.text(
                """
                UPDATE order_items oi
                SET seller_id = p.seller_id
                FROM products p
                WHERE oi.product_id = p.id AND oi.seller_id IS NULL
                """
            )
        )

    op.alter_column("products", "seller_id", nullable=False)
    op.alter_column("order_items", "seller_id", nullable=False)

    op.create_foreign_key("fk_products_seller_id", "products", "sellers", ["seller_id"], ["id"])
    op.create_index("ix_products_seller_id", "products", ["seller_id"])
    op.create_foreign_key("fk_order_items_seller_id", "order_items", "sellers", ["seller_id"], ["id"])
    op.create_index("ix_order_items_seller_id", "order_items", ["seller_id"])


def downgrade() -> None:
    op.drop_index("ix_order_items_seller_id", table_name="order_items")
    op.drop_constraint("fk_order_items_seller_id", "order_items", type_="foreignkey")
    op.drop_column("order_items", "fulfillment_status")
    op.drop_column("order_items", "seller_id")

    op.drop_index("ix_products_seller_id", table_name="products")
    op.drop_constraint("fk_products_seller_id", "products", type_="foreignkey")
    op.drop_column("products", "status")
    op.drop_column("products", "seller_id")

    op.drop_index("ix_sellers_slug", table_name="sellers")
    op.drop_index("ix_sellers_user_id", table_name="sellers")
    op.drop_table("sellers")
