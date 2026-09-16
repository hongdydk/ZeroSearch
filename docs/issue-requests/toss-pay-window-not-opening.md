# 토스 결제창이 안 열림

**상태:** 적용됨 (`main` `305a9fb`, PR [#6](https://github.com/hongdydk/ZeroSearch/pull/6))  
**Phase:** 4 — 제품 범위 SSOT는 [phase4-spec.md](../phase4-spec.md). 이 문서는 운영에서 창이 안 열리던 **사후 기록**만.  
**호스트:** `mall.anoveli.com` Flutter 웹 토스 **테스트** 결제.

---

## 증상

주문서에서 「토스로 결제하기」를 누르면:

- 「결제창으로 이동 중…」 로딩만 보이다가 **다시 주문서**로 돌아온다. 주문서와 hop 화면 문구가 비슷해서, 실제로는 `/checkout`을 다시 그린 것인지 `/toss-pay` HTML이 실패한 것인지 구분이 어려웠다.
- 정적 hop(`toss-pay.html`)까지 가도 **토스 창이 안 열린다** (빈 페이지·즉시 실패·팝업 차단).

---

## 왜 반복됐는지

한 원인만 고치면 다음 레이어가 같은 증상으로 보였다.

1. **iframe / Flutter 캔버스** — 위젯을 앱 안에 두면 창이 캔버스 뒤에 가려지거나 엔진이 깨진다. 현재 탭 hop으로 바꿈 (`1c7920a`, `5902138`).
2. **배송지 없는 prepare** — 주소 없이 토스를 열려 했다. 주문서에서 배송지 필수 (`93d0c81`).
3. **Cloudflare pretty URL** — `/toss-pay.html?…` 가 **308 → `/toss-pay`** 로 가면서 **쿼리(clientKey·orderId 등)가 떨어진다**. `.html`로 가면 안 된다 (`169ad52`).
4. **Dart `location.replace` / PathUrlStrategy** — dart2js가 replace를 삼켜 hop이 실행되지 않음 (`374fef8`).
5. **go_router vs 정적 HTML** — SPA가 `/toss-pay`를 Flutter 화면으로 그려 Cloudflare의 `toss-pay.html`을 다시 불러오지 않음 (`96deadd`).
6. **SDK·키 종류** — 구버전 `payment()` + `test_ck_`/`test_sk_` 와, 배포된 **주문서형·결제창형** `test_gck_`/`test_gsk_` 가 안 맞음. widgets + gck/gsk (`3f6be33`).
7. **웹 idempotency 난수** — `1 << 32` 가 dart2js에서 0이 되어 prepare가 중단됨 (`3e1a34c`).
8. **hop + SPA URL 레이스 (루트 바운스)** — go_router는 `/toss-pay`를 그렸지만 **실제 `window.location`은 아직 `/checkout`**. `TossPayExitScreen`이 `reload()` 하면 주문서를 다시 받는다 (`7a46b20`).
9. **사용자 제스처** — hop 성공 후 `renderPaymentWindow`를 reload 직후 자동 호출하면 팝업이 막힌다. 최종은 **결제하기 클릭** (`7a46b20`).

배포는 `main`만 올린다. 브랜치 수정이 운영에 바로 안 보이면 같은 증상이 반복된 것처럼 보였다.

---

## 최종 원인 / 최종 수정

**원인:** hop 화면이 pathname이 `/toss-pay`가 아닌데도 `reload()` 해서 주문서로 돌아갔다. 그 위에 자동 결제창 호출은 제스처가 없었다.

**수정 (PR #6, 커밋 `7a46b20`, merge `305a9fb`):**

- `history.replaceState`로 문서 URL을 `/toss-pay?…`에 맞춘 뒤, **pathname이 `/toss-pay`일 때만** `reload`.
- `web/toss-pay.html`은 **주문서형 widgets** + 「결제하기」에서 `requestPayment`.
- 키는 `test_gck_` / `test_gsk_`. `/toss-pay.html`로는 이동하지 않음.

---

## 재발 방지

- `reload`는 **실제** `window.location.pathname`이 `/toss-pay`(또는 trailing slash)일 때만.
- **`/toss-pay.html`로 navigate 금지** — Cloudflare 308이 쿼리를 뗌. pretty path `/toss-pay`만.
- 클라이언트는 **gck/gsk + widgets**. 구버전 `payment()` + ck/sk 혼합 금지.
- 토스 창은 **결제하기 클릭**으로만. reload/자동 스크립트에서 `renderPaymentWindow` 하지 않음.
- 웹 idempotency 난수는 `1 << 32` 쓰지 않음 (`0x100000000` 등 32비트에 안전한 범위).
- 배송지 없이 prepare하지 않음 ([phase4-spec.md](../phase4-spec.md) DoD).

---

## 관련 PR·커밋 (`origin/main`)

| 커밋 | 내용 |
|------|------|
| `98ca70e` | 크레딧 체크아웃 → 토스 웹 카드 테스트 |
| `1c7920a` | iframe 대신 현재 탭 |
| `93d0c81` | 결제 전 배송지 |
| `5902138` | SDK를 Flutter 캔버스 밖에서 |
| `169ad52` | pretty `/toss-pay` (`.html` 308·쿼리 손실 회피) |
| `374fef8` | JS `location.replace` hop |
| `2badbc1` | `web` 패키지 직접 의존 |
| `96deadd` | go_router가 HTML hop을 삼키지 않게 |
| `3f6be33` | widgets + `test_gck_`/`test_gsk_` |
| `3e1a34c` | 웹 `1 << 32` → 0 수정 |
| `7a46b20` | checkout reload 레이스 + 결제하기 클릭 |
| `305a9fb` | PR [#6](https://github.com/hongdydk/ZeroSearch/pull/6) merge |

코드 위치: `apps/flutter/lib/core/payment/toss_payment_bridge_web.dart`, `toss_pay_exit_screen.dart`, `web/toss-pay.html`, `checkout_screen.dart`.
