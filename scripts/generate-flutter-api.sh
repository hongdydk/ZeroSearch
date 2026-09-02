#!/usr/bin/env bash
# Generate Flutter API client from scripts/openapi.json (dart-dio).
# Uses Docker for a consistent cross-platform toolchain (CI + local).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC="${ROOT}/scripts/openapi.json"
OUT="${ROOT}/apps/flutter/lib/api/generated"

if [[ ! -f "$SPEC" ]]; then
  echo "OpenAPI spec not found at $SPEC. Run: python scripts/export_openapi.py" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"

docker run --rm \
  -v "${ROOT}:/local" \
  openapitools/openapi-generator-cli:v7.11.0 generate \
  -i /local/scripts/openapi.json \
  -g dart-dio \
  -o /local/apps/flutter/lib/api/generated \
  --additional-properties=pubName=shopping_mall_api,pubAuthor=shopping_mall

# Generator container writes as root; restore ownership for dart pub get / build_runner.
if command -v sudo >/dev/null 2>&1; then
  sudo chown -R "$(id -u):$(id -g)" "$OUT"
else
  chown -R "$(id -u):$(id -g)" "$OUT"
fi

echo "Generated client at apps/flutter/lib/api/generated"
echo "Next: cd apps/flutter/lib/api/generated && dart pub get && dart run build_runner build"
