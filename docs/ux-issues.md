# UI/UX 이슈 (미적용)

**소유:** 아래 1–9는 **Phase 2** (구매자·장바구니). DoD·범위 SSOT는 [phase2-spec.md](./phase2-spec.md) 「구매자·장바구니 UX 이슈 해소」.  
제품·라우트 SSOT는 [README.md](./README.md) · [phase2-spec.md](./phase2-spec.md).  
증상·원인·해결방향의 SSOT는 **이 문서만**. same-origin 인프라는 Phase 2 밖 — [follow-ups.md](./follow-ups.md).

검증된 항목만 적는다. 추측·미확인 이슈는 넣지 않는다.

---

## HIGH

### 1. 검색·필터 시 목록 전체가 스피너

**증상:** 검색어·필터를 바꿀 때마다 목록 크롬까지 사라지고 스피너만 보인다. 입력 중에도 매 키마다 로딩이 돈다.

**원인:** `catalogSearchProvider` 변경이 곧바로 비동기 fetch를 타고, `AsyncValue.when`의 loading 분기가 목록 UI 전체를 교체한다. debounce 없음. (`catalog_screen.dart`, `catalogSearchProvider`)

**해결방향:**

- 검색 입력에 debounce (300ms 전후)
- reload 시 `skipLoadingOnReload` / `previous`로 기존 목록·필터 칩을 유지하고 인라인 로딩만 표시
- 첫 진입(이전 데이터 없음)만 전체 스피너

**심각도:** HIGH  
**상태:** 미적용  
**Phase:** 2

---

### 2. 주문 화면 3초마다 깜빡임

**증상:** 주문 목록이 약 3초 간격으로 통째로 리프레시되며 깜빡인다.

**원인:** `orders_screen.dart` 폴링이 `ordersProvider`를 `invalidate`하고, reload loading이 이전 데이터를 쓰지 않아 UI가 빈 로딩으로 떨어진다.

**해결방향:**

- invalidate 대신 refresh, 또는 `AsyncValue`에서 `skipLoadingOnReload` / previous 유지
- 폴링 중에는 목록을 유지하고 상단·인라인 표시만 갱신

**심각도:** HIGH  
**상태:** 미적용  
**Phase:** 2

---

### 3. 게스트 장바구니 담기 → 로그인 후 상세로 안 돌아옴

**증상:** 상세에서 비로그인 담기 → 로그인 화면으로 간 뒤, 로그인 성공해도 홈(`/`)으로 가고 상세·담기 흐름이 끊긴다.

**원인:** `catalog_detail_screen.dart`가 `go('/login')`만 호출하고 `next`(복귀 URL)를 넘기지 않는다. 로그인 성공 리다이렉트도 `/` 고정.

**해결방향:**

- `/login?next=/catalog-products/:id` (또는 동등 쿼리) 전달
- 로그인 성공 시 `next` 검증 후 `go(next)`, 없으면 `/`
- (선택) 로그인 직후 의도했던 오퍼 담기 재시도

**심각도:** HIGH  
**상태:** 미적용  
**Phase:** 2

---

### 4. 장바구니가 가게별로 안 묶임

**증상:** 장바구니가 평평한 줄 목록이다. Phase 2 라우트 기대는 `/cart` **가게별 묶음**.

**원인:** `CartItemModel`·`cart_screen`에 판매자/가게 필드·섹션 헤더가 없다. API 응답에 seller가 있어도 UI가 그룹핑하지 않는다.

**해결방향:**

- 카트 항목에 `seller_id`·가게명·`seller_type`(공식/입점) 노출에 필요한 필드 확보 (스키마·codegen 포함 시 OpenAPI 계약 준수)
- UI에서 가게별 섹션 + 배송 주체 힌트
- SSOT: [phase2-spec.md](./phase2-spec.md) 라우트 `/cart`

**심각도:** HIGH  
**상태:** 미적용  
**Phase:** 2

---

## MED

### 5. 맛·용량 필터가 모든 종류에 노출

**증상:** 레몬·자몽·2L 같은 칩이 종류와 무관하게 보인다. 떡갈비 목록에도 생수형 필터가 나올 수 있다.

**원인:** 필터 칩이 현재 보고 있는 종류(카테고리)에 바인딩되지 않았다.

**해결방향:**

- 필터는 **지금 종류**에만 묶는다 ([README.md](./README.md) 「종류마다 비교 단위가 다르다」)
- 종류별 허용 필터 메타(또는 카탈로그 속성)로 칩을 조건부 렌더
- 해당 속성이 없는 종류에서는 칩 숨김

**심각도:** MED  
**상태:** 미적용  
**Phase:** 2

---

### 6. 검색과 식탁 drill이 겹침

**증상:** 중분류까지 drill한 상태에서 헤더/목록 검색을 치면, 검색은 돌아가는데 major/mid 컨텍스트가 안 지워져 결과·크롬이 어긋난다.

**원인:** 검색 `onChanged`가 `catalogSearchProvider`만 갱신하고 major/mid를 clear하지 않는다. drill 중에도 헤더 검색이 살아 있다.

**해결방향:**

- 검색 시작 시 major/mid 초기화, 또는 검색 모드와 drill 모드를 배타적으로
- drill 중 검색 UX를 명시(검색 시 식탁으로 복귀 vs drill 범위 내 검색)하고 한쪽으로 통일
- (히스토리 적용 시) URL 쿼리와도 맞출 것 — 아래 §9

**심각도:** MED  
**상태:** 미적용  
**Phase:** 2

---

### 7. 상세: 앱 내 뒤로가기·오퍼 줄·좁은 폭

**증상:** 상세에 앱 내 뒤로가기가 약하거나 없다. 오퍼 줄에서 자사배송/판매자배송·판매자 구분이 약하다. 좁은 화면에서 overflow 위험이 있다.

**원인:** `catalog_detail_screen` 네비·오퍼 행 레이아웃이 Phase 2 「한 줄 비교」(맛·용량·가격·가게·배송) 밀도에 못 미친다.

**해결방향:**

- AppBar/선두에 앱 내 back (`pop`, 없으면 목록)
- 오퍼 행에 배송 주체 라벨(`platform`→자사배송, `merchant`→판매자배송)과 가게명을 읽히게
- 좁은 폭: 줄바꿈·말줄임·가로 스크롤 중 하나로 overflow 방지

**심각도:** MED  
**상태:** 미적용  
**Phase:** 2

---

## LOW

### 8. 빈·에러 카피 거침 · 주문 빈 화면 CTA 없음

**증상:** 목록/주문 등의 빈·에러 문구가 거칠다. 주문 빈 화면에 홈·장보기 등 CTA가 없다.

**원인:** 공통 empty/error 패턴·카피가 없고, 주문 empty가 안내만 하거나 최소 텍스트다.

**해결방향:**

- 구매자 언어로 짧은 안내 + (가능하면) 재시도
- 주문 empty → 홈/식탁으로 가는 CTA

**심각도:** LOW  
**상태:** 미적용  
**Phase:** 2

---

## HIGH (네비)

### 9. 모바일 뒤로가기 · 스크롤 복원

**증상:** 식탁 drill이 Riverpod만 바꿔 URL이 `/` 고정 → 휴대폰 브라우저 뒤로가기 시 사이트 이탈. 면류→식탁 복귀 시 Landing `ListView` dispose로 스크롤 리셋.

**원인:** Browse 상태가 URL에 없고 앱 상태만 바뀐다. 랜딩·중분류 스크롤 offset을 복원하지 않는다.

**해결방향:**

- Browse SSOT = 쿼리 + `push`: `/`, `/?major=…`, `/?major=…&mid=…` (중분류명 `/` 때문에 path segment 비사용)
- 앱 내 뒤로/`식탁` = `pop` (없으면 `go('/')`)
- 랜딩·중분류 스크롤 offset Provider 저장·복원
- 네이티브 백: `/`여도 쿼리 있으면 단계 pop, 루트에서만 종료 확인

**허용 경로(적용 시):** `catalog_screen.dart`, `app_providers.dart`, `app_back_navigation.dart`, `web_naver_header.dart`, `phase2-spec.md` 라우트 표

**심각도:** HIGH (네비)  
**상태:** 미적용  
**Phase:** 2

---

## 관련 인프라 (UX 본문 아님)

`mall` + `mall-api` 동일 호스트(same-origin `/api` 프록시)는 배포·CORS 이슈다. UX 문서 범위 밖이나 **적용은 UX #1–9보다 먼저** — [follow-ups.md](./follow-ups.md).

---

## 적용 순서

0. **same-origin** (`mall` + `/api`) — [follow-ups.md](./follow-ups.md) (Phase 2 DoD 밖, **먼저**)

그다음 UX #1–9 (제안 순서):

1. 검색·필터 스피너 (체감 최상, 순수 Flutter)
2. 주문 폴링 깜빡임 (동일 패턴)
3. 게스트 담기 → 로그인 `next` 복귀
4. 모바일 히스토리·스크롤 (§9)
5. 장바구니 가게별 묶음 (모델·UI, Phase 2 기대)
6. 검색 ↔ drill 배타/정리
7. 종류 묶인 맛·용량 필터
8. 상세 back · 오퍼 줄 · overflow
9. 빈·에러 카피 · 주문 empty CTA
