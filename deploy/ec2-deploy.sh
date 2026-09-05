#!/usr/bin/env bash
# EC2 /opt/shopping-mall 에서 실행 — GitHub Actions SSH 배포용.
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/opt/shopping-mall}"
BRANCH="${DEPLOY_BRANCH:-main}"
CATALOG_CSV="${CATALOG_CSV:-$DEPLOY_DIR/data/aihub-catalog.csv}"

cd "$DEPLOY_DIR"

if [[ ! -f docker-compose.prod.yml ]]; then
  echo "docker-compose.prod.yml not found in $DEPLOY_DIR" >&2
  exit 1
fi

if [[ ! -f .env.prod ]]; then
  echo ".env.prod missing — copy from .env.prod.example on the server first" >&2
  exit 1
fi

git fetch origin "$BRANCH"
git checkout "$BRANCH"
git pull --ff-only origin "$BRANCH"

docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build

HEALTH_URL="http://127.0.0.1:8001/health"
MAX_ATTEMPTS=30
for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  if curl -sf "$HEALTH_URL" >/dev/null; then
    curl -sf "$HEALTH_URL"
    echo
    echo "mall-api health OK"
    break
  fi
  echo "waiting for mall-api ($attempt/$MAX_ATTEMPTS)..."
  sleep 2
  if [[ "$attempt" -eq "$MAX_ATTEMPTS" ]]; then
    echo "mall-api health check failed" >&2
    docker logs mall-api --tail 40 >&2 || true
    exit 1
  fi
done

# CSV unchanged AND same normalization rule → skip upsert.
# FORCE_CATALOG_IMPORT=1 forces re-import.
CACHE_DIR="$DEPLOY_DIR/.cache"
HASH_FILE="$CACHE_DIR/aihub-catalog.sha256"
FORCE_CATALOG_IMPORT="${FORCE_CATALOG_IMPORT:-0}"
# Keep in sync with app.services.catalog_identity.NORMALIZATION_VERSION
CATALOG_NORM_VERSION="${CATALOG_NORM_VERSION:-v2}"
REMERGE_MARKER="$CACHE_DIR/catalog-remerge-${CATALOG_NORM_VERSION}.done"
VOLUME_TITLE_REPAIR_MARKER="$CACHE_DIR/catalog-volume-title-repair-${CATALOG_NORM_VERSION}.done"

# One-time production rollout: back up first, inspect the dry-run, then apply.
# The marker makes subsequent deployments idempotent.
if [[ ! -f "$REMERGE_MARKER" ]]; then
  BACKUP_DIR="$DEPLOY_DIR/backups"
  BACKUP_FILE="$BACKUP_DIR/catalog-before-remerge-$(date -u +%Y%m%dT%H%M%SZ).dump"
  mkdir -p "$BACKUP_DIR" "$CACHE_DIR"
  chmod 700 "$BACKUP_DIR"

  echo "backing up catalog database: $BACKUP_FILE"
  docker exec mall-postgres pg_dump -U mall -d mall -Fc > "$BACKUP_FILE"
  test -s "$BACKUP_FILE"

  echo "catalog remerge dry-run (norm=$CATALOG_NORM_VERSION)"
  docker compose -f docker-compose.prod.yml --env-file .env.prod run --rm \
    api python -m scripts.remerge_catalog

  echo "applying catalog remerge (norm=$CATALOG_NORM_VERSION)"
  docker compose -f docker-compose.prod.yml --env-file .env.prod run --rm \
    api python -m scripts.remerge_catalog --apply

  echo "$CATALOG_NORM_VERSION" > "$REMERGE_MARKER"
  echo "catalog remerge applied; backup=$BACKUP_FILE"
fi

if [[ -f "$CATALOG_CSV" ]]; then
  CSV_HASH="$(sha256sum "$CATALOG_CSV" | awk '{print $1}')"
  NEW_HASH="${CSV_HASH}:${CATALOG_NORM_VERSION}"
  OLD_HASH=""
  if [[ -f "$HASH_FILE" ]]; then
    OLD_HASH="$(tr -d '[:space:]' < "$HASH_FILE")"
  fi
  if [[ "$FORCE_CATALOG_IMPORT" != "1" && -n "$OLD_HASH" && "$NEW_HASH" == "$OLD_HASH" ]]; then
    echo "skip catalog import (unchanged csv+norm=$CATALOG_NORM_VERSION)"
  else
    echo "importing catalog: $CATALOG_CSV (norm=$CATALOG_NORM_VERSION)"
    docker compose -f docker-compose.prod.yml --env-file .env.prod run --rm \
      -v "$CATALOG_CSV:/import/aihub-catalog.csv:ro" \
      api python -m scripts.import_aihub_catalog /import/aihub-catalog.csv
    mkdir -p "$CACHE_DIR"
    echo "$NEW_HASH" > "$HASH_FILE"
    echo "catalog import done"
  fi

  if [[ ! -f "$VOLUME_TITLE_REPAIR_MARKER" ]]; then
    echo "volume-only title repair dry-run (norm=$CATALOG_NORM_VERSION)"
    docker compose -f docker-compose.prod.yml --env-file .env.prod run --rm \
      api python -m scripts.repair_volume_titles

    echo "applying volume-only title repair (norm=$CATALOG_NORM_VERSION)"
    docker compose -f docker-compose.prod.yml --env-file .env.prod run --rm \
      api python -m scripts.repair_volume_titles --apply

    echo "$CATALOG_NORM_VERSION" > "$VOLUME_TITLE_REPAIR_MARKER"
    echo "volume-only title repair applied"
  fi
else
  echo "skip catalog import — missing $CATALOG_CSV" >&2
fi
