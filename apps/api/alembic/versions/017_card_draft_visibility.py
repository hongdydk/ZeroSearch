"""Seller card-draft visibility intent (public vs hidden).

Revision ID: 017
Revises: 016
Create Date: 2026-09-19
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "017"
down_revision: Union[str, None] = "016"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "catalog_intake_drafts",
        sa.Column("visibility", sa.String(20), nullable=False, server_default="public"),
    )
    op.create_check_constraint(
        "ck_catalog_intake_drafts_visibility",
        "catalog_intake_drafts",
        "visibility IN ('public', 'hidden')",
    )


def downgrade() -> None:
    op.drop_constraint(
        "ck_catalog_intake_drafts_visibility",
        "catalog_intake_drafts",
        type_="check",
    )
    op.drop_column("catalog_intake_drafts", "visibility")
