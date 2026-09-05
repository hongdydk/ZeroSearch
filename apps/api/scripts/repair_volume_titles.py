"""v1 정규화로 용량만 남은 대표 카드를 v2 import 결과로 복구한다.

실행 순서:
  python -m scripts.import_aihub_catalog /import/aihub-catalog.csv
  python -m scripts.repair_volume_titles
  python -m scripts.repair_volume_titles --apply
"""

from __future__ import annotations

import argparse
import sys

from app.database import SessionLocal
from app.services.catalog_identity import NORMALIZATION_VERSION
from app.services.catalog_remerge import (
    apply_volume_title_repair,
    format_report,
    plan_volume_title_repair,
)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Repair volume-only catalog titles after canonical v2 import"
    )
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    print(f"normalization={NORMALIZATION_VERSION}")
    db = SessionLocal()
    try:
        if args.apply:
            report = apply_volume_title_repair(db)
            db.commit()
        else:
            _, report = plan_volume_title_repair(db)
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
