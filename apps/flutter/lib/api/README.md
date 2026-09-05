# OpenAPI codegen (Wave 2)

Contract SSOT: `apps/api/app/schemas/` (Pydantic) → `scripts/openapi.json` → `lib/api/generated/` (dart-dio).

## Pipeline

1. Export OpenAPI from the FastAPI app (no running server required):

   ```bash
   python scripts/export_openapi.py
   # or: pnpm codegen:openapi
   ```

2. Generate the Flutter client:

   ```bash
   bash scripts/generate-flutter-api.sh
   # or: pnpm codegen:flutter  (export + generate)
   ```

   On Windows without Bash, use PowerShell (Docker fallback):

   ```powershell
   .\scripts\generate-flutter-api.ps1
   ```

   Output: `lib/api/generated/` (`anoveli_api` package). CI uses Docker (`openapitools/openapi-generator-cli`) on `ubuntu-latest`.

3. Resolve serializers and the path dependency:

   ```bash
   cd apps/flutter/lib/api/generated && dart pub get && dart run build_runner build
   cd ../../.. && flutter pub get
   ```

## Git policy

| Path | Policy |
|------|--------|
| `scripts/openapi.json` | **Committed** — `deploy.yml` `test-api` runs `export_openapi.py` then `git diff --exit-code` (drift → fail) |
| `lib/api/generated/` | **Gitignored** — regenerate locally or in CI before `flutter pub get` |

## Troubleshooting

**IDE에 오류가 수천 개 보일 때**

1. `lib/api/generated/`는 gitignore — clone 직후 비어 있거나 `*.g.dart`가 없을 수 있습니다.
2. 한 번에 복구:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts/codegen-flutter-full.ps1
   ```

   (OpenAPI export → Docker codegen → `build_runner` → **모든 generated `*.dart`에 동일 `// @dart=`** → `flutter pub get`)

   codegen만 다시 돌린 뒤에도 오류가 남으면 `@dart` 불일치일 수 있습니다:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts/fix-generated-dart-parts.ps1
   cd apps/flutter; flutter pub get
   ```

3. `apps/flutter/pubspec.yaml`의 Dart SDK는 설치된 Flutter에 맞아야 합니다 (`^3.12.0` 기준). `flutter pub get` 실패 시 Problems가 연쇄적으로 폭증합니다.

4. **Docker로 `flutter pub get` / `flutter test`를 돌린 뒤** `package_config.json`에 `file:///root/.pub-cache` 경로가 들어가면 Windows IDE가 패키지를 전부 못 찾아 오류가 폭증합니다. 로컬에서 다시:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\repair-flutter-ide.ps1
   ```

   또는 `cd apps/flutter; flutter pub get` 후 **Dart: Restart Analysis Server** (Cursor/VS Code).

**원인 요약:** `lib/api/generated/`는 gitignore라 clone·pull 직후 비어 있거나, codegen/`@dart=`/Docker `pub get`이 어긋나면 `package:anoveli_api` 해석이 깨지며 연쇄 오류가 납니다. 위 복구 절차는 동일합니다.

## Hand-written facade (Wave 2–4)

`ApiClient` keeps its public API; shared `Dio` + JWT interceptor delegates to generated APIs. DTOs map to app models in `lib/core/network/api_mappers.dart`.

| Wave | Delegated endpoints |
|------|---------------------|
| 2a | auth (`login`, `register`, `me`, preferences) |
| 2b | feed read (`bots`, `bot`, `episodes`, `episode`, `readingProgress`) |
| 2c | credits balance, episode unlock, `myForks`, worldline read (`myWorldlines`, `canonicalWorldline`, `worldlineTree`) |
| 4 / 2d | studio/bots write (`myBots`, create/patch/delete/enrich/meter/preview/publish), episode write (generate/regenerate/publish/patch/delete), worldline write (`forkWorldline`, `deleteWorldline`), `episodeLengthTiers`, `saveReadingProgress`, chat/sessions (`chat`, `sessions`, `sessionMessages`, `chatModels`), admin (`adminStats`, `adminUsers`, grant/promote/dbReset) |

All `ApiClient` methods use `_generatedCall` (no hand `_request`).
