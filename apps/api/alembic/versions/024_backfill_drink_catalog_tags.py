"""Backfill buyer browse tags for existing beverage catalog cards.

Revision ID: 024
Revises: 023
"""

from alembic import op
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import CatalogProduct
from app.services.catalog_l1 import apply_auto_l1_tags


revision = "024"
down_revision = "023"
branch_labels = None
depends_on = None


def upgrade() -> None:
    session = Session(bind=op.get_bind())
    try:
        for catalog in session.scalars(select(CatalogProduct)).yield_per(200):
            # Preserve an operator's existing classification. Only cards that
            # cannot appear in buyer L1/L2 browse because tags are empty get
            # the updated automatic drink classification.
            apply_auto_l1_tags(catalog, only_if_empty=True)
        session.flush()
    finally:
        session.close()


def downgrade() -> None:
    # Tag classification is data enrichment and remains valid on downgrade.
    pass
