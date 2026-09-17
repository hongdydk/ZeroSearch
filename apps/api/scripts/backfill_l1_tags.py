"""Backfill guest L1 tags on existing catalog_products.

  cd apps/api && python -m scripts.backfill_l1_tags
"""

from sqlalchemy.orm import Session

from app.database import SessionLocal
from app.services.catalog_l1 import backfill_l1_tags


def main() -> None:
    db: Session = SessionLocal()
    try:
        updated = backfill_l1_tags(db, only_if_empty=True)
        db.commit()
        print(f"l1_tags backfill: {updated} catalog products")
    finally:
        db.close()


if __name__ == "__main__":
    main()
