# Agent 워크플로

**제로 서치 (Zero Search)** — ShoppingMall 저장소에서 Cursor Agent가 따를 흐름과 경로 요약.

## 워크플로

1. **Ask** — 읽기·논의만. 코드·설정 편집 없음.
2. **Plan** — Plan 모드에서 범위·단계·허용 경로·DoD 확정. **승인(Build) 전 구현 금지.**
3. **Agent** — 승인된 Plan 범위 안에서만 구현. 최소 diff, 완료 시 변경 파일·항목별 상태 보고.

## 제품 방향 (요약)

- **제로 서치:** 「생수」·「떡갈비」처럼 **종류**로 찾으면 **회사+유형+품목 카드가 쭈르륵**. 같은 회사의 그 품목은 용량·판매자만 한 장으로 모은다. 카드는 **단위당 대표가(중위)** → 상세 **오퍼 한 줄 비교**.
- **마켓플레이스:** 공식(`platform`) + 입점(`merchant`), 주문 줄별 가게·배송.
- **멤버십:** 제품 범위 밖. 레거시 코드는 건드리지 않는 한 유지.
- **결제:** 목표 토스 PG (Phase 4). 현재 크레딧 스텁. Phase 3은 판매자·관리자 기능 추가.
- **배포:** Cloudflare Pages(Flutter) + EC2(FastAPI·Postgres). 카탈로그는 `data/aihub-catalog.csv` 배포 시 import.

SSOT: [docs/README.md](docs/README.md)

## 계약 SSOT (API ↔ Flutter)

```
apps/api/app/schemas/  →  scripts/openapi.json  →  apps/flutter/lib/api/generated/
         (Pydantic)         (export_openapi.py)         (generate-flutter-api)
```

수기 `api_client.dart`·`models.dart`는 점진 이전 중. **`packages/shared`는 레거시 참조만.**

### API 스키마 변경 시 체크리스트

1. `apps/api/app/schemas/*.py` 수정
2. `python scripts/export_openapi.py` → `scripts/openapi.json` 갱신
3. `cd apps/api && pytest` (관련 테스트)
4. (필요 시) `pnpm codegen:flutter` → Flutter generated 동기화

## 프로젝트 규칙

- **제품 컨셉** — [docs/README.md](docs/README.md)
- **report/** — 사람용, gitignore. 사용자 명시 전에는 읽지 않음 ([규칙](.cursor/rules/report.mdc))
- **계획 범위** — [.cursor/rules/계획-범위.mdc](.cursor/rules/계획-범위.mdc)
- **위임** — [.cursor/rules/위임.mdc](.cursor/rules/위임.mdc)
- **Phase 로드맵** — [.cursor/rules/phase-로드맵.mdc](.cursor/rules/phase-로드맵.mdc)
- **OpenAPI 계약** — [.cursor/rules/openapi-contract.mdc](.cursor/rules/openapi-contract.mdc)
- **API 관례** — [.cursor/rules/api-관례.mdc](.cursor/rules/api-관례.mdc)
- **Flutter 관례** — [.cursor/rules/flutter-관례.mdc](.cursor/rules/flutter-관례.mdc)
- **Flutter UI** — [.cursor/rules/flutter-UI.mdc](.cursor/rules/flutter-UI.mdc)
- **Git 관례** — [.cursor/rules/git-관례.mdc](.cursor/rules/git-관례.mdc)

## 주요 경로

```
ShoppingMall/
├── apps/api/          # FastAPI — auth, products, cart, orders, sellers
├── apps/flutter/      # 카탈로그·장바구니·주문·판매자 UI
├── report/            # 사람용 기획·목업 (gitignore, 요청 없이 읽지 않음)
├── packages/shared/   # 레거시 TypeScript (참조만)
└── docs/              # 제품 SSOT · phase 스펙
```

- API: `apps/api/app/` (routers, services, models, schemas)
- Flutter: `apps/flutter/lib/`
- Phase SSOT: `docs/phaseN-spec.md`
- 제품 SSOT: `docs/README.md`

## 서브에이전트

Cursor 내장 타입만 사용 (`explore`, `shell`, `generalPurpose` 등).  
구현·리팩터는 **foreground** — 서브에이전트에 구현 위임 금지. 상세: [위임 규칙](.cursor/rules/위임.mdc).
