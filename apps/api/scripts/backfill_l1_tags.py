"""Backfill guest L1 tags on existing catalog_products.

  cd apps/api && python -m scripts.backfill_l1_tags
  cd apps/api && python -m scripts.backfill_l1_tags --force
"""

from __future__ import annotations

import argparse

from sqlalchemy.orm import Session

from app.database import SessionLocal
from app.services.catalog_l1 import backfill_l1_tags
from app.services.guest_l1 import TAGGER_VERSION


def main() -> None:
    parser = argparse.ArgumentParser(description="Backfill catalog_products.l1_tags")
    parser.add_argument(
        "--force",
        action="store_true",
        help="이미 태그가 있는 행도 현재 규칙으로 다시 추론한다.",
    )
    args = parser.parse_args()

    db: Session = SessionLocal()
    try:
        updated = backfill_l1_tags(db, only_if_empty=not args.force)
        db.commit()
        mode = "force" if args.force else "empty-only"
        print(f"l1_tags backfill ({mode}, tagger={TAGGER_VERSION}): {updated} catalog products")
    finally:
        db.close()


if __name__ == "__main__":
    main()
