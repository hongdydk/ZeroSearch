import uuid
from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Integer, Numeric, String, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class CatalogVariant(Base):
    """A reviewed, sellable configuration beneath one catalog card."""

    __tablename__ = "catalog_variants"
    __table_args__ = (
        CheckConstraint("pack_count >= 1", name="ck_catalog_variants_pack_count_positive"),
        UniqueConstraint(
            "catalog_product_id", "name", "unit_amount", "unit", "pack_count",
            name="uq_catalog_variants_configuration",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    catalog_product_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("catalog_products.id"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(100), nullable=False, default="기본", server_default="기본")
    unit_amount: Mapped[float] = mapped_column(Numeric(12, 3), nullable=False)
    unit: Mapped[str] = mapped_column(String(10), nullable=False)
    pack_count: Mapped[int] = mapped_column(Integer, nullable=False, default=1, server_default="1")
    image_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    catalog_product = relationship("CatalogProduct", back_populates="variants")
    offers = relationship("Product", back_populates="variant")
