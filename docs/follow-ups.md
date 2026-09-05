# 후속 작업 (미적용)

**다음 적용:** 운영 서브페이즈 A (배포 부담 완화). Phase 2 UX #1–9·same-origin(§1)은 적용됨.

구매자·장바구니 UX(#1–9)는 **Phase 2** — [ux-issues.md](./ux-issues.md) · DoD [phase2-spec.md](./phase2-spec.md) — **적용됨**.  
이 문서는 Phase 2 DoD에 아직 안 넣은 **인프라·운영**만 둔다. 운영 서브페이즈 A–C가 SSOT.

로드맵: 판매자·관리자 보강은 Phase 3, 배송지·취소/환불은 Phase 4 직전·병행, 토스 PG는 Phase 4 (`docs/phase3-spec.md` · `docs/phase4-spec.md`).

---

## 1. `mall` + `mall-api` 동일 호스트

**상태:** 적용됨 — `https://mall.anoveli.com/api/health` → JSON ok (Pages Functions `/api` → mall-api)

**현상(이전):** UI `https://mall.anoveli.com`, API `https://mall-api.anoveli.com` (CORS).

**구현:**
- [`deploy/cloudflare-pages/functions/`](../deploy/cloudflare-pages/functions/) — `/api/*` → `https://mall-api.anoveli.com/*` (`/api` prefix strip)
- CI가 Flutter web 산출물에 `functions/` + `_routes.json`을 붙여 Pages에 배포
- `scripts/ci-build-flutter-web.sh` 기본·구 `mall-api` 직접 URL → `https://mall.anoveli.com/api`
- 백엔드(Tunnel `mall-api.anoveli.com` → :8001)는 유지. 브라우저는 same-origin만 사용

**확인:** `https://mall.anoveli.com/api/health` → `{"status":"ok",...}` · 사이트 로그인·목록 정상

**하지 않음(당시):** 아노벨리 `api.anoveli.com`과 합치기, Pages에 FastAPI 올리기, `mall-api` DNS 즉시 삭제

### 1b. `mall-api` 공개 호스트 정리 (나중)

**상태:** 미적용 · §1 이후

**목표:** 브라우저·문서에서 `mall-api.anoveli.com`을 없앤다. Pages Functions(또는 Tunnel)가 **비공개/내부 origin**으로만 :8001에 붙게 한 뒤, 공개 DNS·Tunnel hostname `mall-api` 제거.

**선행:** 프록시 `MALL_API_ORIGIN`을 공개 `mall-api`가 아닌 경로로 변경·검증. 그 전 삭제 금지.

**오류 감소:** same-origin(§1)이 이미 CORS·이중 URL 혼선을 줄인 상태. 공개 `mall-api` 제거는 **추가 공개 엔드포인트·잘못된 직접 호출**을 줄이는 쪽에 가깝고, EC2/배포 瞬时 장애 자체는 A·B(배포·관측)가 더 효과적이다.


---

## 운영 서브페이즈 (Phase 2 병행·이후)

Phase 2 UX(#1–9)와 **병행 가능**. Phase 3 / 3.5 / 4와 무관. 제품 DoD는 [phase2-spec.md](./phase2-spec.md) — 여기는 운영 부담만.

### A. 배포 부담 완화

**증상:** 배포마다 `data/aihub-catalog.csv` 전량 upsert(~1만 행). Flutter `flutter_service_worker.js`가 비거나 SW가 오래되면 캐시 잔존·빈 SW 위험.

**방향:** CSV 해시·mtime 등으로 **변경 없을 때 import skip**. SW/캐시 무효화·빈 워커 방지 점검. (구현 Plan 시 `deploy/`·시드 스크립트만)

### B. 관측 (최소 알림)

**증상:** health·배포 실패를 사람이 나중에야 앎. 네트워크 오류와 UI 버그가 한 덩어리로 보임.

**방향:** health/deploy 실패 **최소 알림**부터. 원인 구분은 네트워크 vs UI. Sentry류는 **선택·나중** — 필수는 아님.

### C. OpenAPI 계약 습관

**증상:** `schemas` ↔ `openapi.json` ↔ Flutter generated가 어긋나면 Phase 2 장바구니·API UX 수정 때 클라이언트/서버가 따로 노는다.

**방향:** 손대면 체크 — [AGENTS.md](../AGENTS.md) 「API 스키마 변경 시」: `schemas` → `scripts/export_openapi.py` → `pytest` → (필요 시) `pnpm codegen:flutter`. 계약 규칙: [.cursor/rules/openapi-contract.mdc](../.cursor/rules/openapi-contract.mdc)

---

## 적용 순서

1. **same-origin** 프록시 + `API_BASE_URL` + 헬스 확인 (이 문서 §1) — **적용됨**
2. (Phase 2) 구매자·장바구니 UX #1–9 — [ux-issues.md](./ux-issues.md) — **적용됨**
3. **운영 서브페이즈** A → B → C — **다음: A** (병행 가능; UX와 겹치면 C를 해당 PR에 묶음)
4. **§1b** `mall-api` 공개 호스트 정리 (프록시 origin 교체 후)
