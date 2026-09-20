import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Seller(Base):
    __tablename__ = "sellers"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, unique=True, index=True
    )
    shop_name: Mapped[str] = mapped_column(String(100), nullable=False)
    slug: Mapped[str] = mapped_column(String(100), nullable=False, unique=True, index=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, server_default="pending")
    seller_type: Mapped[str] = mapped_column(String(20), nullable=False, server_default="merchant")
    store_description: Mapped[str | None] = mapped_column(String(500), nullable=True)
    store_logo_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    store_banner_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    user = relationship("User", back_populates="seller")
    products = relationship("Product", back_populates="seller")
    intake_drafts = relationship("CatalogIntakeDraft", back_populates="seller")
    moderation_events = relationship(
        "SellerModerationEvent",
        back_populates="seller",
        cascade="all, delete-orphan",
    )
