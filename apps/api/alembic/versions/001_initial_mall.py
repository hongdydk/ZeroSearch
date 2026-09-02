"""Initial mall schema.

Revision ID: 001
Revises:
Create Date: 2026-08-31
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("email", sa.String(255), nullable=False),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column("display_name", sa.String(100), nullable=True),
        sa.Column("is_admin", sa.Boolean(), nullable=False, server_default="false"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_users_email", "users", ["email"], unique=True)

    op.create_table(
        "credit_wallets",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("balance", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_credit_wallets_user_id", "credit_wallets", ["user_id"], unique=True)

    op.create_table(
        "credit_transactions",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("wallet_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("credit_wallets.id"), nullable=False),
        sa.Column("type", sa.String(20), nullable=False),
        sa.Column("amount", sa.Integer(), nullable=False),
        sa.Column("balance_after", sa.Integer(), nullable=False),
        sa.Column("ref_type", sa.String(50), nullable=True),
        sa.Column("ref_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("note", sa.String(500), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_credit_transactions_wallet_id", "credit_transactions", ["wallet_id"])

    op.create_table(
        "products",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("price_credits", sa.Integer(), nullable=False),
        sa.Column("stock", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("category", sa.String(50), nullable=False),
        sa.Column("image_url", sa.String(500), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_products_category", "products", ["category"])

    op.create_table(
        "cart_items",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("product_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("products.id"), nullable=False),
        sa.Column("qty", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("user_id", "product_id", name="uq_cart_items_user_product"),
    )
    op.create_index("ix_cart_items_user_id", "cart_items", ["user_id"])

    op.create_table(
        "orders",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
        sa.Column("total_credits", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_orders_user_id", "orders", ["user_id"])

    op.create_table(
        "order_items",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("order_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("orders.id"), nullable=False),
        sa.Column("product_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("products.id"), nullable=False),
        sa.Column("qty", sa.Integer(), nullable=False),
        sa.Column("unit_price_credits", sa.Integer(), nullable=False),
        sa.Column("product_title", sa.String(200), nullable=False),
    )
    op.create_index("ix_order_items_order_id", "order_items", ["order_id"])

    op.create_table(
        "membership_plans",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("slug", sa.String(50), nullable=False),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("price_credits", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("interval", sa.String(20), nullable=False, server_default="month"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_membership_plans_slug", "membership_plans", ["slug"], unique=True)

    op.create_table(
        "subscriptions",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("plan_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("membership_plans.id"), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="active"),
        sa.Column("current_period_end", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_subscriptions_user_id", "subscriptions", ["user_id"])


def downgrade() -> None:
    op.drop_table("subscriptions")
    op.drop_table("membership_plans")
    op.drop_table("order_items")
    op.drop_table("orders")
    op.drop_table("cart_items")
    op.drop_table("products")
    op.drop_table("credit_transactions")
    op.drop_table("credit_wallets")
    op.drop_table("users")
