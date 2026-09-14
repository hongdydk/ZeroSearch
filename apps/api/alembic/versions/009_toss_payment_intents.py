"""Toss payment intents.

Revision ID: 009
Revises: 008
Create Date: 2026-09-14
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "009"
down_revision: Union[str, None] = "008"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "payment_intents",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("order_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("provider_order_id", sa.String(64), nullable=False),
        sa.Column("idempotency_key", sa.String(64), nullable=True),
        sa.Column("payment_key", sa.String(200), nullable=True),
        sa.Column("amount", sa.Integer(), nullable=False),
        sa.Column("order_name", sa.String(100), nullable=False),
        sa.Column("status", sa.String(24), nullable=False, server_default="ready"),
        sa.Column("cart_snapshot", postgresql.JSONB(), nullable=False),
        sa.Column("failure_code", sa.String(100), nullable=True),
        sa.Column("failure_message", sa.Text(), nullable=True),
        sa.Column(
            "requested_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column("approved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.ForeignKeyConstraint(["order_id"], ["orders.id"]),
        sa.UniqueConstraint("order_id"),
        sa.UniqueConstraint("provider_order_id"),
        sa.UniqueConstraint("payment_key"),
        sa.UniqueConstraint(
            "user_id",
            "idempotency_key",
            name="uq_payment_intents_user_key",
        ),
    )
    op.create_index("ix_payment_intents_user_id", "payment_intents", ["user_id"])


def downgrade() -> None:
    op.drop_index("ix_payment_intents_user_id", table_name="payment_intents")
    op.drop_table("payment_intents")
