"""Seller-managed public storefront profile.

Revision ID: 021
Revises: 020
"""

from alembic import op
import sqlalchemy as sa

revision = "021"
down_revision = "020"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("sellers", sa.Column("store_description", sa.String(500), nullable=True))
    op.add_column("sellers", sa.Column("store_logo_url", sa.String(500), nullable=True))
    op.add_column("sellers", sa.Column("store_banner_url", sa.String(500), nullable=True))


def downgrade() -> None:
    op.drop_column("sellers", "store_banner_url")
    op.drop_column("sellers", "store_logo_url")
    op.drop_column("sellers", "store_description")
