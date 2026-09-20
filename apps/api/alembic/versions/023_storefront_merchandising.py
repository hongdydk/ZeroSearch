"""Add seller storefront product placement fields.

Revision ID: 023
Revises: 022
"""

from alembic import op
import sqlalchemy as sa

revision = "023"
down_revision = "022"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("products", sa.Column("storefront_rank", sa.Integer(), nullable=False, server_default="0"))
    op.add_column("products", sa.Column("storefront_featured", sa.Boolean(), nullable=False, server_default=sa.false()))


def downgrade() -> None:
    op.drop_column("products", "storefront_featured")
    op.drop_column("products", "storefront_rank")
