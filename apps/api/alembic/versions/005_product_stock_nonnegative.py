"""Enforce non-negative product stock.

Revision ID: 005
Revises: 004
Create Date: 2026-09-06
"""

from typing import Sequence, Union

from alembic import op

revision: str = "005"
down_revision: Union[str, None] = "004"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 음수 재고가 있으면 제약 추가가 실패한다 — 운영자가 재고를 먼저 바로잡아야 한다.
    op.create_check_constraint(
        "ck_products_stock_nonnegative",
        "products",
        "stock >= 0",
    )


def downgrade() -> None:
    op.drop_constraint("ck_products_stock_nonnegative", "products", type_="check")
