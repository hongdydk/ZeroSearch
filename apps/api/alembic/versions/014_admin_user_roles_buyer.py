"""Buyer role flag and seller restore moderation action.

Revision ID: 014
Revises: 013
Create Date: 2026-09-18
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "014"
down_revision: Union[str, None] = "013"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("is_buyer", sa.Boolean(), nullable=False, server_default=sa.text("true")),
    )
    op.drop_constraint("ck_seller_moderation_events_action", "seller_moderation_events", type_="check")
    op.create_check_constraint(
        "ck_seller_moderation_events_action",
        "seller_moderation_events",
        "action IN ('warn', 'suspend', 'unsuspend', 'remove', 'restore')",
    )


def downgrade() -> None:
    op.drop_constraint("ck_seller_moderation_events_action", "seller_moderation_events", type_="check")
    op.create_check_constraint(
        "ck_seller_moderation_events_action",
        "seller_moderation_events",
        "action IN ('warn', 'suspend', 'unsuspend', 'remove')",
    )
    op.drop_column("users", "is_buyer")
