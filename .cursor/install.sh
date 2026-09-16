#!/usr/bin/env bash
# 제로 서치 (Zero Search) — Cloud Agent 환경 설치.
# 체크아웃 후 1회(빌드 스냅샷) 실행. 멱등하게 다시 실행돼도 안전해야 한다.
#   - 시스템 패키지(postgres/jre) · Flutter SDK · Python venv · DB 마이그레이션/시드
#   - OpenAPI → dart-dio 클라이언트 코드젠 (Docker 대신 openapi-generator-cli npm/Java jar 사용)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

FLUTTER_VERSION="3.47.4"
FLUTTER_HOME="/opt/flutter"
PG_VERSION="16"
export DEBIAN_FRONTEND=noninteractive

echo "==> 시스템 패키지 (postgres, python venv, JRE)"
sudo apt-get update -qq
sudo apt-get install -y -qq \
  postgresql postgresql-client \
  python3-venv python3-pip \
  default-jre-headless

echo "==> Flutter SDK ${FLUTTER_VERSION}"
if [ ! -x "${FLUTTER_HOME}/bin/flutter" ]; then
  curl -fsSL -o /tmp/flutter.tar.xz \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  sudo rm -rf "${FLUTTER_HOME}"
  sudo tar -xf /tmp/flutter.tar.xz -C /opt
  sudo chown -R "$(id -u):$(id -g)" "${FLUTTER_HOME}"
  rm -f /tmp/flutter.tar.xz
fi
export PATH="${FLUTTER_HOME}/bin:${PATH}"
git config --global --add safe.directory "${FLUTTER_HOME}" || true
flutter config --no-analytics >/dev/null 2>&1 || true
flutter config --enable-web >/dev/null 2>&1 || true
flutter precache --web >/dev/null 2>&1 || true

echo "==> PostgreSQL 클러스터 기동 + mall 역할/DB"
sudo pg_ctlcluster "${PG_VERSION}" main start 2>/dev/null || true
for _ in $(seq 1 30); do sudo -u postgres pg_isready -q && break; sleep 1; done
sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='mall'" | grep -q 1 \
  || sudo -u postgres psql -c "CREATE ROLE mall LOGIN PASSWORD 'mall';"
sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='mall'" | grep -q 1 \
  || sudo -u postgres createdb -O mall mall

echo "==> apps/api/.env (없으면 생성, 로컬 postgres 5432로 지정)"
if [ ! -f apps/api/.env ]; then
  cp apps/api/.env.example apps/api/.env
  sed -i 's#^DATABASE_URL=.*#DATABASE_URL=postgresql+psycopg://mall:mall@localhost:5432/mall#' apps/api/.env
fi

echo "==> Python venv + 의존성"
python3 -m venv apps/api/.venv
apps/api/.venv/bin/python -m pip install --upgrade pip -q
apps/api/.venv/bin/pip install -q -r apps/api/requirements.txt

echo "==> DB 마이그레이션 + 시드"
( cd apps/api && ./.venv/bin/python -m alembic upgrade head && ./.venv/bin/python seed.py )

# 데모 카탈로그(생수: 백산수·평창수·제주삼다수 + 다중 오퍼) — 카탈로그가 비었을 때만 1회.
# seed_beverage_demo 는 멱등이 아니라 오퍼를 계속 추가하므로 비어 있을 때만 실행한다.
echo "==> 생수 데모 카탈로그 (비어 있을 때만)"
( cd apps/api && ./.venv/bin/python - <<'PY'
from sqlalchemy import func, select
from app.database import SessionLocal
from app.models import CatalogProduct
from seed import seed_beverage_demo

db = SessionLocal()
try:
    if (db.scalar(select(func.count()).select_from(CatalogProduct)) or 0) == 0:
        seed_beverage_demo(db)
        db.commit()
        print("생수 데모 시드 완료")
    else:
        print("카탈로그가 이미 있어 데모 시드를 건너뜀")
finally:
    db.close()
PY
)

echo "==> pnpm 의존성 (워크스페이스)"
pnpm install --frozen-lockfile || pnpm install

echo "==> OpenAPI export + Flutter dart-dio 클라이언트 코드젠"
apps/api/.venv/bin/python scripts/export_openapi.py
export OPENAPI_GENERATOR_VERSION="7.11.0"
rm -rf apps/flutter/lib/api/generated
mkdir -p apps/flutter/lib/api/generated
npx --yes @openapitools/openapi-generator-cli@2.x generate \
  -i scripts/openapi.json \
  -g dart-dio \
  -o apps/flutter/lib/api/generated \
  --additional-properties=pubName=shopping_mall_api,pubAuthor=shopping_mall
( cd apps/flutter/lib/api/generated && dart pub get && dart run build_runner build )
bash scripts/fix-generated-dart-parts.sh
( cd apps/flutter && flutter pub get )

echo "==> 설치 완료"
