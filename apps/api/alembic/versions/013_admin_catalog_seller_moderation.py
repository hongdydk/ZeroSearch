"""Admin catalog retire status and seller moderation history.

Revision ID: 013
Revises: 012
Create Date: 2026-09-18
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "013"
down_revision: Union[str, None] = "012"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "catalog_products",
        sa.Column("status", sa.String(20), nullable=False, server_default="active"),
    )
    op.create_index("ix_catalog_products_status", "catalog_products", ["status"])

    op.create_table(
        "seller_moderation_events",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("seller_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("admin_user_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("action", sa.String(20), nullable=False),
        sa.Column("reason", sa.Text(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.ForeignKeyConstraint(["seller_id"], ["sellers.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["admin_user_id"], ["users.id"], ondelete="SET NULL"),
        sa.CheckConstraint(
            "action IN ('warn', 'suspend', 'unsuspend', 'remove')",
            name="ck_seller_moderation_events_action",
        ),
    )
    op.create_index(
        "ix_seller_moderation_events_seller_id",
        "seller_moderation_events",
        ["seller_id"],
    )
    op.create_index(
        "ix_seller_moderation_events_created_at",
        "seller_moderation_events",
        ["created_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_seller_moderation_events_created_at", table_name="seller_moderation_events")
    op.drop_index("ix_seller_moderation_events_seller_id", table_name="seller_moderation_events")
    op.drop_table("seller_moderation_events")
    op.drop_index("ix_catalog_products_status", table_name="catalog_products")
    op.drop_column("catalog_products", "status")
