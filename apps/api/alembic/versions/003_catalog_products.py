"""Catalog products and offer option fields.

Revision ID: 003
Revises: 002
Create Date: 2026-09-02
"""

import uuid
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "003"
down_revision: Union[str, None] = "002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "catalog_products",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("category", sa.String(50), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("image_url", sa.String(500), nullable=True),
        sa.Column("search_keywords", postgresql.JSONB(), nullable=True),
        sa.Column("price_unit", sa.String(10), nullable=False, server_default="ml"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_catalog_products_title", "catalog_products", ["title"])
    op.create_index("ix_catalog_products_category", "catalog_products", ["category"])

    op.add_column("products", sa.Column("catalog_product_id", postgresql.UUID(as_uuid=True), nullable=True))
    op.add_column("products", sa.Column("option_label", sa.String(100), nullable=True))
    op.add_column("products", sa.Column("volume_ml", sa.Integer(), nullable=True))
    op.add_column("products", sa.Column("flavor", sa.String(50), nullable=True))

    conn = op.get_bind()
    rows = conn.execute(
        sa.text(
            """
            SELECT id, title, category, description, image_url
            FROM products
            ORDER BY created_at
            """
        )
    ).fetchall()

    for row in rows:
        catalog_id = uuid.uuid4()
        conn.execute(
            sa.text(
                """
                INSERT INTO catalog_products (id, title, category, description, image_url, price_unit)
                VALUES (:id, :title, :category, :description, :image_url, 'each')
                """
            ),
            {
                "id": str(catalog_id),
                "title": row.title,
                "category": row.category,
                "description": row.description,
                "image_url": row.image_url,
            },
        )
        conn.execute(
            sa.text("UPDATE products SET catalog_product_id = :catalog_id WHERE id = :product_id"),
            {"catalog_id": str(catalog_id), "product_id": str(row.id)},
        )

    op.alter_column("products", "catalog_product_id", nullable=False)
    op.create_foreign_key(
        "fk_products_catalog_product_id",
        "products",
        "catalog_products",
        ["catalog_product_id"],
        ["id"],
    )
    op.create_index("ix_products_catalog_product_id", "products", ["catalog_product_id"])


def downgrade() -> None:
    op.drop_index("ix_products_catalog_product_id", table_name="products")
    op.drop_constraint("fk_products_catalog_product_id", "products", type_="foreignkey")
    op.drop_column("products", "flavor")
    op.drop_column("products", "volume_ml")
    op.drop_column("products", "option_label")
    op.drop_column("products", "catalog_product_id")

    op.drop_index("ix_catalog_products_category", table_name="catalog_products")
    op.drop_index("ix_catalog_products_title", table_name="catalog_products")
    op.drop_table("catalog_products")
