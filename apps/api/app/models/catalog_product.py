import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, Text, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class CatalogProduct(Base):
    __tablename__ = "catalog_products"
    __table_args__ = (
        UniqueConstraint(
            "manufacturer",
            "category",
            "title",
            name="uq_catalog_products_maker_category_title",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    title: Mapped[str] = mapped_column(String(200), nullable=False, index=True)
    manufacturer: Mapped[str] = mapped_column(String(200), nullable=False, default="", server_default="")
    category: Mapped[str] = mapped_column(String(120), nullable=False, index=True)
    category_major: Mapped[str | None] = mapped_column(String(120), nullable=True)
    category_mid: Mapped[str | None] = mapped_column(String(120), nullable=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    image_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    search_keywords: Mapped[list | None] = mapped_column(JSONB, nullable=True)
    volume_options: Mapped[list] = mapped_column(JSONB, nullable=False, default=list, server_default="[]")
    reference_variants: Mapped[list] = mapped_column(
        JSONB, nullable=False, default=list, server_default="[]"
    )
    price_unit: Mapped[str] = mapped_column(String(10), nullable=False, server_default="ml")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    offers = relationship("Product", back_populates="catalog_product")
    aliases = relationship(
        "CatalogProductAlias",
        back_populates="canonical",
        cascade="all, delete-orphan",
        foreign_keys="CatalogProductAlias.canonical_id",
    )


class CatalogProductAlias(Base):
    """옛 catalog UUID → 생존 대표 상품. 상세 URL·판매자 연결 호환용."""

    __tablename__ = "catalog_product_aliases"

    alias_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    canonical_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("catalog_products.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    original_title: Mapped[str | None] = mapped_column(String(200), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    canonical = relationship(
        "CatalogProduct",
        back_populates="aliases",
        foreign_keys=[canonical_id],
    )
