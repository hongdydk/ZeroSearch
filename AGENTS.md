# Agent 워크플로

**제로 서치 (Zero Search)** — ShoppingMall 저장소에서 Cursor Agent가 따를 흐름과 경로 요약.

## 워크플로

1. **Ask** — 읽기·논의만. 코드·설정 편집 없음.
2. **Plan** — Plan 모드에서 범위·단계·허용 경로·DoD 확정. **승인(Build) 전 구현 금지.**
3. **Agent** — 승인된 Plan 범위 안에서만 구현. 최소 diff, 완료 시 변경 파일·항목별 상태 보고.

## 제품 방향 (요약)

- **제로 서치:** 검색·목록에서 **같은 브랜드** 카드 중복을 줄인다. **브랜드당 대표 1장(최저가)** → 상세 **오퍼 한 줄 비교**.
- **마켓플레이스:** 공식(`platform`) + 입점(`merchant`), 주문 줄별 가게·배송.
- **멤버십:** 제품 범위 밖. 레거시 코드는 건드리지 않는 한 유지.
- **결제:** 목표 토스 PG (Phase 3). 현재 크레딧 스텁.
- **배포:** AWS (S3·CloudFront / EC2 / RDS).

SSOT: [report/프로젝트-컨셉.md](report/프로젝트-컨셉.md)

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

- **제품 컨셉** — [report/프로젝트-컨셉.md](report/프로젝트-컨셉.md)
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
├── report/            # 컨셉, 기획서, mockup/
├── packages/shared/   # 레거시 TypeScript (참조만)
└── docs/              # phase 스펙
```

- API: `apps/api/app/` (routers, services, models, schemas)
- Flutter: `apps/flutter/lib/`
- Phase SSOT: `docs/phaseN-spec.md`
- 화면 목업: `report/mockup/index.html`

## 서브에이전트

Cursor 내장 타입만 사용 (`explore`, `shell`, `generalPurpose` 등).  
구현·리팩터는 **foreground** — 서브에이전트에 구현 위임 금지. 상세: [위임 규칙](.cursor/rules/위임.mdc).
