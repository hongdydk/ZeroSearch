"""DB 카탈로그 재병합 dry-run / apply.

  cd apps/api
  python -m scripts.remerge_catalog
  python -m scripts.remerge_catalog --apply
"""

from __future__ import annotations

import argparse
import sys

from app.database import SessionLocal
from app.services.catalog_identity import NORMALIZATION_VERSION
from app.services.catalog_remerge import apply_db_remarge, format_report, plan_db_remarge


def main() -> int:
    parser = argparse.ArgumentParser(description="Remerge catalog_products by identity rules")
    parser.add_argument(
        "--apply",
        action="store_true",
        help="실제로 병합한다. 기본은 dry-run.",
    )
    args = parser.parse_args()

    print(f"normalization={NORMALIZATION_VERSION}")
    db = SessionLocal()
    try:
        if args.apply:
            report = apply_db_remarge(db)
            db.commit()
        else:
            _, report = plan_db_remarge(db)
        print(format_report(report))
        if not args.apply:
            print("dry-run only — re-run with --apply to write", file=sys.stderr)
        return 0
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
