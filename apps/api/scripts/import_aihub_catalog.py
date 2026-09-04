"""Import AI-Hub catalog CSV into catalog_products.

Deploy (EC2):
  docker compose -f docker-compose.prod.yml --env-file .env.prod run --rm \\
    -v /opt/shopping-mall/data/aihub-catalog.csv:/import/aihub-catalog.csv:ro \\
    api python -m scripts.import_aihub_catalog /import/aihub-catalog.csv

Local:
  cd apps/api
  python -m scripts.import_aihub_catalog ../../data/aihub-catalog.csv
"""

from __future__ import annotations

import argparse
from pathlib import Path

from app.database import SessionLocal
from app.services.catalog_import import import_catalog_csv

REPO_DEFAULT = Path(__file__).resolve().parents[3] / "data" / "aihub-catalog.csv"


def main() -> None:
    parser = argparse.ArgumentParser(description="AI-Hub CSV → catalog_products upsert")
    parser.add_argument(
        "csv_path",
        type=Path,
        nargs="?",
        default=REPO_DEFAULT,
        help="path to aihub-catalog.csv",
    )
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
