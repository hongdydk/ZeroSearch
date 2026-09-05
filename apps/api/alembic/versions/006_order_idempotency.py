"""Order checkout idempotency key.

Revision ID: 006
Revises: 005
Create Date: 2026-09-06
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "006"
down_revision: Union[str, None] = "005"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "orders",
        sa.Column("idempotency_key", sa.String(64), nullable=True),
    )
    op.create_unique_constraint(
        "uq_orders_user_idempotency_key",
        "orders",
        ["user_id", "idempotency_key"],
    )


def downgrade() -> None:
    op.drop_constraint("uq_orders_user_idempotency_key", "orders", type_="unique")
    op.drop_column("orders", "idempotency_key")
