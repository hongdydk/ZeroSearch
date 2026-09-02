#!/usr/bin/env bash
# EC2 /opt/shopping-mall 에서 실행 — GitHub Actions SSH 배포용.
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/opt/shopping-mall}"
BRANCH="${DEPLOY_BRANCH:-main}"

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
    exit 0
  fi
  echo "waiting for mall-api ($attempt/$MAX_ATTEMPTS)..."
  sleep 2
done

echo "mall-api health check failed" >&2
docker logs mall-api --tail 40 >&2 || true
exit 1
