"""Add seller product detail image gallery.

Revision ID: 022
Revises: 021
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB

revision = "022"
down_revision = "021"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "products",
        sa.Column("detail_image_urls", JSONB(), nullable=False, server_default="[]"),
    )


def downgrade() -> None:
    op.drop_column("products", "detail_image_urls")
