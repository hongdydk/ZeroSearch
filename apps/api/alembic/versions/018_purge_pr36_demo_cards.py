"""One-shot: drop PR #36 demo catalog cards (제주삼다수 / 레쓰비) if present.

Revision ID: 018
Revises: 017
Create Date: 2026-09-19
"""

from typing import Sequence, Union

from alembic import op
from sqlalchemy.orm import Session

revision: str = "018"
down_revision: Union[str, None] = "017"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    from app.services.catalog_cleanup import purge_pr36_demo_catalog_cards

    session = Session(bind=op.get_bind())
    purge_pr36_demo_catalog_cards(session)
    session.flush()


def downgrade() -> None:
    # Demo seed is gone; deleted rows are not restored.
    pass
