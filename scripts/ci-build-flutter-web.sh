#!/usr/bin/env bash
# CI: OpenAPI codegen + Flutter web build (Cloudflare Pages 사이트 루트).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_BASE_URL="${API_BASE_URL:-https://mall.anoveli.com/api}"
# Same-origin 이행: 예전 mall-api 직접 URL이면 Pages /api 프록시로 맞춤
case "$API_BASE_URL" in
  https://mall-api.anoveli.com|https://mall-api.anoveli.com/)
    API_BASE_URL="https://mall.anoveli.com/api"
    echo "API_BASE_URL migrated → $API_BASE_URL"
    ;;
esac
GEN="$ROOT/apps/flutter/lib/api/generated"

cd "$ROOT"

python scripts/export_openapi.py
bash scripts/generate-flutter-api.sh

cd "$GEN"
dart pub get
dart run build_runner build --delete-conflicting-outputs

bash "$ROOT/scripts/fix-generated-dart-parts.sh"

cd "$ROOT/apps/flutter"
flutter pub get
flutter build web \
  --base-href="/" \
  --pwa-strategy=none \
  --dart-define="API_BASE_URL=$API_BASE_URL"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("build/web/index.html")
text = p.read_text(encoding="utf-8")
new, n = re.subn(r'<base href="[^"]*"', '<base href="/"', text, count=1)
if n != 1:
    raise SystemExit(f"could not set base href in {p}")
p.write_text(new, encoding="utf-8", newline="\n")
print('Forced <base href="/">')
PY

echo "Built: apps/flutter/build/web"
