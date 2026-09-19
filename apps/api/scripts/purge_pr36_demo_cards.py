"""One-shot: delete PR #36 demo cards (제주삼다수 / 레쓰비) by manufacturer+title.

Does not run on API startup. Other seller/user catalog rows are left alone.
Alembic 018 runs the same purge once on upgrade.

  cd apps/api && python -m scripts.purge_pr36_demo_cards
  cd apps/api && python -m scripts.purge_pr36_demo_cards --apply
"""

from __future__ import annotations

import argparse
import sys

from sqlalchemy.orm import Session

from app.database import SessionLocal
from app.services.catalog_cleanup import (
    PR36_DEMO_CATALOG_KEYS,
    list_pr36_demo_catalogs,
    purge_pr36_demo_catalog_cards,
)


def _print_matches(db: Session) -> int:
    rows = list_pr36_demo_catalogs(db)
    print("keys: " + ", ".join(f"{maker}/{title}" for maker, title in PR36_DEMO_CATALOG_KEYS))
    if not rows:
        print("no matching catalog rows")
        return 0
    for row in rows:
        print(f"{row.id}  manufacturer={row.manufacturer!r}  title={row.title!r}")
    return len(rows)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Delete PR #36 제주삼다수·레쓰비 demo catalog cards (manufacturer+title only)"
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Delete matching catalog rows and their offers. Default is dry-run.",
    )
    args = parser.parse_args()

    db: Session = SessionLocal()
    try:
        if not args.apply:
            count = _print_matches(db)
            print("dry-run only — re-run with --apply to delete", file=sys.stderr)
            return 0 if count >= 0 else 1

        result = purge_pr36_demo_catalog_cards(db)
        db.commit()
        print(
            "removed_catalogs={removed_catalogs} removed_offers={removed_offers} "
            "skipped_with_orders={skipped_with_orders}".format(**result)
        )
        return 0
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
