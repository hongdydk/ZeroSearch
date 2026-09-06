"""Remove untrusted barcodes from catalog reference variants.

Revision ID: 008
Revises: 007
Create Date: 2026-09-06
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "008"
down_revision: Union[str, None] = "007"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        sa.text(
            """
            UPDATE catalog_products
            SET reference_variants = COALESCE(
                (
                    SELECT jsonb_agg(item - 'barcode')
                    FROM jsonb_array_elements(reference_variants) AS item
                ),
                '[]'::jsonb
            )
            WHERE reference_variants @? '$[*].barcode'
            """
        )
    )


def downgrade() -> None:
    # 삭제된 원본 값은 신뢰하지 않으며 복원하지 않는다.
    pass
