#!/usr/bin/env bash
# CI: OpenAPI codegen + Flutter web build (S3 mall/ 업로드용).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_BASE_URL="${API_BASE_URL:-https://mall-api.anoveli.com}"
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
  --base-href=/mall/ \
  --pwa-strategy=none \
  --dart-define="API_BASE_URL=$API_BASE_URL"

echo "Built: apps/flutter/build/web"
