"""Import slim MFDS catalog CSV into catalog_products.

    cd apps/api
    python -m alembic upgrade head
    python -m scripts.import_mfds_catalog ../../data/mfds-catalog.csv
"""

from __future__ import annotations

import argparse
from pathlib import Path

from app.database import SessionLocal
from app.services.catalog_import import import_catalog_csv


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("csv_path", type=Path)
    args = parser.parse_args()
    if not args.csv_path.is_file():
        raise SystemExit(f"not found: {args.csv_path}")
    db = SessionLocal()
    try:
        result = import_catalog_csv(db, args.csv_path.read_bytes())
        db.commit()
        print(f"source_rows={result['source_rows']} upserted={result['upserted']}")
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


if __name__ == "__main__":
    main()
