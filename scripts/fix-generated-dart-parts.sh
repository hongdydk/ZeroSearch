#!/usr/bin/env bash
# Ensure openapi + build_runner library/part files share the same // @dart= version (dart2js).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GEN="${ROOT}/apps/flutter/lib/api/generated"

if [[ ! -d "$GEN/lib" ]]; then
  exit 0
fi

VERSION="${DART_LANGUAGE_VERSION:-}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(dart --version 2>&1 | sed -E 's/.*Dart SDK version: ([0-9]+\.[0-9]+).*/\1/')"
fi
if [[ -z "$VERSION" ]]; then
  VERSION="3.8"
fi

while IFS= read -r -d '' file; do
  sed -i '/^\/\/ @dart=/d' "$file"
  sed -i "1i // @dart=${VERSION}" "$file"
done < <(find "$GEN/lib" -name '*.dart' -print0)

echo "Set // @dart=${VERSION} on generated Dart sources under lib/"
