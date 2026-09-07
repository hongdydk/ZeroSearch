# 후속 작업 (미적용)

**다음 적용:** §1b S3 + CloudFront · `mall-api` 공개 호스트 정리 (AWS 계정 대기). 운영 서브페이즈 A–C는 **적용됨**.

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

### 1b. S3 + CloudFront · `mall-api` 공개 호스트 정리

**상태:** 예정 · **AWS 계정 오류로 대기** · 계정 준비 전 구현·CI 변경 금지

**현재:** Flutter → Cloudflare Pages. 브라우저 `/api`는 Pages Functions → 공개 `mall-api.anoveli.com` → EC2 `:8001`.

**목표 (한 번에):**
- 웹 원본: Pages → **S3 + CloudFront**. 호스트는 `mall.anoveli.com` 유지
- 브라우저 API: 계속 `https://mall.anoveli.com/api` — CloudFront가 `/api`를 EC2 `:8001`로 넘김
- 공개 `mall-api.anoveli.com` DNS·Tunnel hostname 제거 (프록시 origin을 내부로 바꾼 뒤)

**선행:** AWS 계정 사용 가능. 그 전 Pages·Functions·공개 `mall-api` 백엔드는 유지. `mall-api` DNS는 origin 교체·검증 전에 삭제 금지.

**하지 않음(이 항목):** FastAPI를 S3/CloudFront에 올리기, 아노벨리 `api.anoveli.com`과 합치기.


---

## 운영 서브페이즈 (Phase 2 병행·이후)

Phase 2 UX(#1–9)와 **병행 가능**. Phase 3 / 3.5 / 4와 무관. 제품 DoD는 [phase2-spec.md](./phase2-spec.md) — 여기는 운영 부담만.

### A. 배포 부담 완화

**상태:** 적용됨

**증상(이전):** 배포마다 `data/aihub-catalog.csv` 전량 upsert(~1만 행). Flutter `flutter_service_worker.js`가 비거나 SW가 오래되면 캐시 잔존·빈 SW 위험.

**구현:**
- [`deploy/ec2-deploy.sh`](../deploy/ec2-deploy.sh) — CSV `sha256` vs `$DEPLOY_DIR/.cache/aihub-catalog.sha256`; 동일 → skip. 강제: `FORCE_CATALOG_IMPORT=1`
- [`scripts/ci-build-flutter-web.sh`](../scripts/ci-build-flutter-web.sh) — `--pwa-strategy=none` 후에도 Flutter가 빈 `flutter_service_worker.js` stub을 남기므로 삭제; 비어 있지 않으면 fail
- [`deploy/cloudflare-pages/_headers`](../deploy/cloudflare-pages/_headers) — `/index.html`·`/flutter_bootstrap.js` → `Cache-Control: no-cache` (CI가 Pages 산출물에 복사)

### B. 관측 (최소 알림) — Cursor Automations

**상태:** 적용됨 (레포 연동) · **secrets + Automations UI는 사용자 1회 설정**

**증상(이전):** health·배포 실패를 사람이 나중에야 앎.

**구현 (로컬 hooks 아님):**
- [`.github/workflows/health-check.yml`](../.github/workflows/health-check.yml) — ~15분 + `workflow_dispatch` → `curl https://mall.anoveli.com/api/health`
- [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml) — `notify-failure` job (`if: always() && failure()`)
- [`scripts/notify-cursor-automation.sh`](../scripts/notify-cursor-automation.sh) — POST Automations webhook; secret 없으면 skip

| | [`.cursor/hooks.json`](../.cursor/hooks.json) (로컬 Hook) | **Cursor Automations** (웹훅) |
|--|--|--|
| 트리거 | Agent 도구/셸/세션 (에디터 안) | HTTP POST · GitHub · 스케줄 |
| CI/헬스 실패 수신 | **불가** | **가능** |
| 역할 | 정책·감사·후처리 | **수신기** → Cloud Agent 실행 |

로컬 Hook은 Cursor 안에서 Agent가 돌 때만 동작한다. 배포/헬스 실패를 Cursor로 보내는 경로는 **Automations 웹훅**이다.

#### Automations 설정 (사용자 1회)

1. [cursor.com/automations](https://cursor.com/automations)에서 Automation 생성 (Webhook 트리거).
2. **Prompt 의도:** payload의 `run_url`·`event`를 읽고 ZeroSearch 레포에서 배포/헬스 실패 원인을 짧게 진단·요약. 명확한 레포 수정이면 PR 제안; 인프라/비밀/EC2 수동이면 조치 체크리스트만. Sentry 없음.
3. Webhook URL·Key를 GitHub repo secrets에 넣기:

| Secret | 용도 |
|--------|------|
| `CURSOR_AUTOMATION_WEBHOOK_URL` | Automations webhook URL |
| `CURSOR_AUTOMATION_WEBHOOK_KEY` | Bearer 키 |

Payload: `source`, `event` (`health_fail`\|`deploy_fail`), `repo`, `run_url`, `job`, `message`.

Sentry는 **선택·나중** — 필수는 아님.

### C. OpenAPI 계약 습관

**상태:** 적용됨

**증상(이전):** `schemas` ↔ `openapi.json` ↔ Flutter generated가 어긋나면 클라이언트/서버가 따로 논다.

**구현:**
- `deploy.yml` `test-api`: `python scripts/export_openapi.py` → `git diff --exit-code -- scripts/openapi.json` (drift → fail)
- 손대면 체크 — [AGENTS.md](../AGENTS.md) 「API 스키마 변경 시」: `schemas` → `scripts/export_openapi.py` → `pytest` → (필요 시) `pnpm codegen:flutter`. 계약 규칙: [.cursor/rules/openapi-contract.mdc](../.cursor/rules/openapi-contract.mdc)

---

## 적용 순서

1. **same-origin** 프록시 + `API_BASE_URL` + 헬스 확인 (이 문서 §1) — **적용됨**
2. (Phase 2) 구매자·장바구니 UX #1–9 — [ux-issues.md](./ux-issues.md) — **적용됨**
3. **운영 서브페이즈** A → B → C — **적용됨**
4. **§1b** S3 + CloudFront · `mall-api` 공개 제거 (AWS 계정 대기) — **다음**
