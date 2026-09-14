"""Buyer shipping addresses and order snapshots.

Revision ID: 010
Revises: 009
Create Date: 2026-09-14
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "010"
down_revision: Union[str, None] = "009"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "shipping_addresses",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("recipient_name", sa.String(50), nullable=False),
        sa.Column("phone", sa.String(20), nullable=False),
        sa.Column("zonecode", sa.String(10), nullable=False),
        sa.Column("address", sa.String(200), nullable=False),
        sa.Column("detail_address", sa.String(100), nullable=False),
        sa.Column("is_default", sa.Boolean(), nullable=False, server_default="false"),
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
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
    )
    op.create_index("ix_shipping_addresses_user_id", "shipping_addresses", ["user_id"])
    op.add_column(
        "payment_intents",
        sa.Column("shipping_snapshot", postgresql.JSONB(), nullable=True),
    )
    op.add_column(
        "orders",
        sa.Column("shipping_snapshot", postgresql.JSONB(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("orders", "shipping_snapshot")
    op.drop_column("payment_intents", "shipping_snapshot")
    op.drop_index("ix_shipping_addresses_user_id", table_name="shipping_addresses")
    op.drop_table("shipping_addresses")
