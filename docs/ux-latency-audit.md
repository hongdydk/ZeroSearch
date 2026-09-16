# UX 지연 감사 (탭이 서버를 기다림)

**범위:** `apps/flutter` — 몰 **구매자**, 판매자 포털 (`/seller*`), 관리자 포털 (`/admin*`).  
조사 시점: `main` + 이 브랜치.  
**Phase:** 구매 UX는 Phase 2 유지. 판매자·관리자 기능 확장은 Phase 3(추후). 결제는 Phase 4. 멤버십은 제품 범위 밖(레거시).  
관련: [ux-issues.md](./ux-issues.md) #1–9(구매자 스피너·폴링 깜빡임은 이미 적용). 이 문서는 **그 이후에도 탭이 네트워크를 기다리는** 지점.

**이 PR**

- **구매자 장바구니:** 항목 1·2·4 + 게스트 로컬 카트. `CartNotifier`가 +/-·삭제를 즉시 그리고, 구매자만 debounce PUT/DELETE 후 실패 시 롤백·스낵바. `/cart` 공개, `/checkout` 인증 게이트 유지. 담기 뱃지(3)·배송지 삭제(8)·검색 첫 입력(5)도 적용.
- **판매자:** S3 주문 상태 낙관적 전진, S6 오퍼 목록 유지+병렬 GET, S1 홈 병렬/점진 로드. S7 검색 목록은 스피너로 비우지 않음. S8 카드 초안은 응답 한 줄 prepend.
- **관리자:** A1 섹션별 fetch(상태 hoist로 remount 시 재조회 없음), A2 로딩 플래그, A3 승인 낙관적 제거, A4 주문 보정 낙관적, A5 주문 섹션만 폴링, A6 초안 한 줄 제거(승격은 서버 확인 후), A9 사용자만 재조회, A10 행 단위 저장·삭제. CSV·DB 리셋·카드 승격 대기는 유지.

각 항목 형식: 화면/액션 → 오늘 → 왜 느린가 → 제안 → 심각도·공수 → 게스트(해당 없으면 N/A) vs 역할.

---

## 가설 검증 (게스트 장바구니 +/-)

요청에 나온 경로:

`updateVisibleCartQty` → guest storage → `invalidate(cartProvider)` → `loadGuestCart`가 줄마다 `api.product()`

**현재 `main`에는 이 코드가 없다.** 검색해도 `GuestCartLine` / `guest_cart.dart` / `loadGuestCart` / `updateVisibleCartQty` 없음.

실제로 (`main`):

- 게스트 장바구니는 **로컬 저장이 없다.** `cartProvider`는 구매자 JWT가 없으면 빈 카트를 메모리에서 바로 반환한다 (`app_providers.dart`).
- `/cart` · `/checkout` · `/orders` · `/settings*` · `/membership` 는 `_requiresAuth` → `/login?next=…` (`app_router.dart`).
- 상세 「담기」는 비로그인이면 `beginGuestAddLogin` — 로그인 화면으로 보내고, 로그인 후 한 번 `addToCart`.
- 장바구니 +/- 는 **로그인 구매자만** 탄다. 느림의 원인은 게스트 product GET 루프가 아니라 아래 **구매자 PUT + invalidate + GET + 전체 스피너**.

이 PR의 구매자 카트 후속이 `main` 가설을 바꿈: 게스트 스냅샷 + `/cart` 공개, 구매자 낙관적 +/-. 판매자·관리자 지연과는 무관.

---

## 반복 패턴

**구매자 (Riverpod)**

1. **응답 바디를 버리고 다시 GET** — `addToCart` / `updateCartItem` / `removeFromCart` 가 이미 `CartModel`을 돌려주는데, 화면은 무시하고 `invalidate(cartProvider)` → `GET me/cart`.
2. **`skipLoadingOnReload` 없음** — 카탈로그·주문만 적용. 장바구니·체크아웃·배송지는 invalidate 시 `when(loading:)` 전체 스피너로 떨어진다.
3. **낙관적 갱신 없음** — 수량·삭제·담기 뱃지 모두 서버 왕복 후.

**판매자·관리자 (로컬 `StatefulWidget`)**

포털은 목록 Riverpod가 거의 없다. `runBusy`로 버튼을 잠근 뒤 `await` mutate, 이어서 **`_load()`로 관련·비관련 GET을 다시** 탄다.

1. **쓰기 후 전체 재조회** — PATCH/POST 응답(또는 void)을 목록에 반영하지 않고 `sellerProducts`+`sellerCardDrafts` 또는 `adminStats`+`adminUsers`+pending sellers+drafts+orders 를 **순차 await**.
2. **섹션 이동 시 위젯 재생성** — `/admin`·`/admin/sellers` 등이 각각 `AdminScreen(section: …)` 새 인스턴스. 사이드바 탭마다 `_load()` 전체. 셸은 유지되지만 본문은 remount.
3. **`_loading = true`가 목록을 비움** — 판매자 홈·오퍼·(비 silent) 주문. 관리자 입점/주문/사용자는 `_loading` 플래그가 없어 **빈 목록이 먼저** 보인다.
4. **폴링** — 판매자 주문 `3s` silent GET. 관리자는 **모든 섹션**에서 `adminOrders` 3초 폴링 (주문 화면이 아니어도).
5. **검색 다이얼로그** — 품목 찾기·붙일 카드 찾기가 목록을 가운데 스피너로 교체. debounce·이전 결과 유지 없음.
6. **찜·PTR** — 없음. 포털 Pull-to-refresh 오남용 이슈 없음.

게스트는 판매자·관리자 포털에 없음 (`PortalAuthGate` → 해당 포털 로그인). **게스트: N/A.**

---

## 구매자 (몰)

### 1. 장바구니 수량 +/-  (우선)

- **화면:** `/cart` `CartScreen` `IconButton` +/- (`QtyStepper` 위젯 아님)
- **오늘 (`main`):** `runBusy`로 버튼 잠금 → `await updateCartItem` (`PUT me/cart`, 응답에 카트 있음) → `invalidate(cartProvider)` → `GET me/cart`. `when()`에 `skipLoadingOnReload` 없음 → 목록 대신 가운데 스피너.
- **왜 느린가:** 탭마다 **쓰기 + 읽기** 두 왕복. 그 사이 화면이 비워짐. 연속 +/- 는 이전 요청이 끝날 때까지 잠김.
- **제안:** (a) PUT 응답 `CartModel`로 `cartProvider`를 바로 채움 (invalidate 금지). (b) 화면 수량을 먼저 올리고 실패 시 롤백. (c) `skipLoadingOnReload: true`. 재고 한도는 서버 에러 메시지로. 라이브 재고/가격은 `/cart` 진입·소프트 새로고침 1회.
- **게스트:** `main`에선 카트 진입 자체가 로그인. +/- 없음.
- **로그인:** 이 경로가 체감 핵심.
- **심각도:** **high** · **공수:** 작음 (응답 재사용 + skipLoading). 낙관적 UI는 중간.
- **상태:** 이 PR에서 적용. 게스트·구매자 모두 즉시 UI. 구매자는 debounce PUT, 실패 시 GET 롤백.

### 2. 장바구니 줄 삭제

- **화면:** `/cart` 휴지통
- **오늘:** +/- 와 동일 — `removeFromCart` 응답 버리고 invalidate + GET + 전체 스피너.
- **왜 느린가:** 1과 같음. 줄이 바로 안 사라짐.
- **제안:** 로컬에서 줄 제거 후 DELETE. 실패 시 복구. 또는 DELETE 응답 카트를 그대로 넣기.
- **게스트/로그인:** 1과 같음.
- **심각도:** **high** · **공수:** 작음 (1과 같이 하는 게 맞음).
- **상태:** 이 PR에서 적용. 낙관적 제거 + 구매자 백그라운드 DELETE.

### 3. 상세 「담기」 / 「장바구니 담기」

- **화면:** `/catalog/:id` 오퍼 줄 `담기`; 과도기 `/products/:id` `장바구니 담기`
- **오늘 (`main`):** 담기 전 수량 스테퍼는 **로컬 `setState`** (즉시). 담기는 `runBusy` → `await addToCart` → `invalidate(cartProvider)` → GET. 성공 스낵바는 POST 이후. 헤더 뱃지는 GET 후 `totalQty`.
- **왜 느린가:** 버튼이 POST(+GET) 동안 잠김. 담은 느낌이 네트워크 RTT만큼 늦음. 뱃지도 한 박자 늦음.
- **제안:** 낙관적으로 뱃지 `totalQty` += qty, 스낵바를 먼저. POST 실패 시 뱃지 롤백 + 에러 스낵바. `cartProvider`는 POST 응답으로 갱신 (GET 생략). 재고 레이스는 서버 거절이 정답.
- **게스트 (`main`):** API 없이 `/login?next=…&addOffer=&addQty=`. 느린 건 카트가 아니라 **로그인 게이트**.
- **로그인:** POST+GET+버튼 잠금. (이 PR: 게스트 담기는 로컬 카트. 로그인 담기는 뱃지를 먼저 올리고 POST 실패 시 롤백.)
- **심각도:** **med** (담기는 한 번, +/- 만큼 반복되지 않음) · **공수:** 작음~중간.
- **상태:** 이 PR에서 적용. 뱃지는 즉시, 버튼은 POST를 기다림. 실패 시 `cartSyncError` 롤백.

### 4. 장바구니·체크아웃 최초 로딩 / invalidate 시 스피너

- **화면:** `/cart`, `/checkout` 가 `cartProvider` `when(loading:)` 전체 스피너
- **오늘:** 셸 뱃지가 이미 cart를 watch 하면 재진입은 데이터가 있을 수 있음. **invalidate 직후**는 이전 값을 그려 주지 않음.
- **왜 느린가:** 실제 왕복보다 **빈 스피너 교체**가 더 거슬림. ux-issues #1과 같은 병.
- **제안:** `skipLoadingOnReload: true` + 인라인 진행만. 에러 재시도만 전체 스피너.
- **게스트:** 체크아웃 인증 게이트 유지 (`_requiresAuth`).
- **심각도:** **med** (1·2를 증폭) · **공수:** 매우 작음. 1과 묶어서.
- **상태:** 이 PR에서 적용 (`skipLoadingOnReload`). 구매자 `/cart` 진입 시 서버 카트 1회 동기.

### 5. 검색 첫 커밋 전체 스피너

- **화면:** 홈/헤더 검색. `CatalogSearchDebounce` 300ms 후 `go(?q=)` → fetch
- **오늘:** 키 입력 debounce·reload 시 목록 유지는 **적용됨**. 랜딩에서 글자를 치기 시작하면 `awaitingFirstSearch` 동안 **가운데 스피너만**.
- **왜 느린가:** 첫 검색 300ms + RTT 동안 랜딩이 사라짐.
- **제안:** 랜딩/이전 그리드를 유지하고 인라인 로딩만.
- **게스트/로그인:** 동일 (공개 목록).
- **심각도:** **med** · **공수:** 작음.
- **상태:** 이 PR에서 적용. `awaitingFirstSearch`여도 랜딩을 유지.

### 6. 생수 맛·용량 칩

- **화면:** 목록 `_FilterChips` (생수 mid/검색일 때만)
- **오늘:** 칩 선택은 즉시. 카드는 서버 GET. reload 시 이전 그리드+얇은 프로그레스 유지.
- **왜 느린가:** 칩은 즉시, 카드는 네트워크 후. 디바운스 없음.
- **제안:** 목록은 지금처럼 previous+인라인. 연속 탭이면 짧은 debounce 또는 in-flight 취소.
- **게스트/로그인:** 동일.
- **심각도:** **low~med** · **공수:** 작음.

### 7. 목록 페이지네이션

- **화면:** 그리드 하단 근접 시 `loadMore`
- **오늘:** 기존 아이템 유지, `loadingMore` 스피너, offset GET append.
- **심각도:** **low** (양호) · **공수:** —

### 8. 배송지 삭제

- **화면:** `/settings/addresses` 휴지통
- **오늘:** `await deleteAddress` → `invalidate(addressesProvider)`. skipLoadingOnReload 없음 → 목록이 스피너로 교체.
- **제안:** 낙관적 제거 + skipLoadingOnReload. 실패 시 되돌림.
- **게스트:** 주소 라우트는 로그인 필수.
- **심각도:** **med** · **공수:** 작음.
- **상태:** 이 PR에서 적용. 낙관적 숨김 + `skipLoadingOnReload`. 실패 시 복구.

- **화면:** `/settings/addresses/new`·`:id` 「저장」, 「주소 찾기」
- **오늘:** 저장은 `runBusy` + create/update + invalidate + pop. 주소 찾기는 다음 우편 위젯.
- **제안:** 저장은 서버 왕복 유지. pop 전 로컬 목록 삽입은 8과 함께.
- **심각도:** **low** · **공수:** 작음.

### 10. 주문서 「토스로 결제하기」

- **화면:** `/checkout` 결제 버튼
- **오늘:** `prepareTossPayment` 동안 `_checkingOut`.
- **제안:** 바꾸지 않음. 낙관적 결제 금지 (Phase 4).
- **게스트:** `/checkout` → 로그인. 게이트 유지.
- **심각도:** **low** (의도된 대기) · **공수:** —

### 11. 주문 목록 3초 폴링

- **화면:** `/orders`
- **오늘:** `Timer.periodic(3s)` → `refresh(ordersProvider)`. `skipLoadingOnReload: true`.
- **제안:** 포커스/가시일 때만, 또는 간격 늘리기.
- **게스트:** 로그인 필수.
- **심각도:** **low** · **공수:** 작음.

### 12. 멤버십 「구독」

- **화면:** `/membership` (제품 범위 밖, 레거시)
- **오늘:** `await subscribe` → invalidate membership + credits.
- **제안:** 우선순위 낮음.
- **게스트:** 로그인 필수.
- **심각도:** **low** · **공수:** 작음.

### 13. 로그인 / 가입 / 부트스트랩

- **화면:** `/login` 「로그인」, `AuthNotifier._bootstrap`, 포털 `PortalAuthGate`
- **오늘:** 로그인 후 `me`. 부트스트랩 중 게이트는 가운데 스피너.
- **제안:** UX 낙관적 로그인 비추천. 로그인 응답에 user가 있으면 `me` 생략은 API 계약.
- **심각도:** **low~med** · **공수:** API면 중간.

### 14. 결제 결과 확인

- **화면:** `/payment/success` 진입 시 `confirmTossPayment`
- **제안:** 낙관적 완료 금지.
- **심각도:** **low** (의도) · **공수:** —

### 15. 상세 진입 fetch

- **화면:** 카탈로그 상세 `catalogProductDetailProvider`; 오퍼 상세 `FutureBuilder` + `api.product`
- **오늘:** 화면 열 때 1회 GET. 목록 카드 데이터가 있어도 다시 GET.
- **심각도:** **low~med** · **공수:** 중간.

---

## 판매자

게스트 **N/A**. 역할: 판매자 JWT (`PortalAuthGate` `LoginPortal.seller`). 입점 전·pending·suspended는 대시보드 본문 대신 안내 문구. Phase 3 착수 전에도 이 화면들이 현재 운영 UI다.

### S1. 운영 홈 최초 로드

- **화면:** `/seller` `SellerScreen._load`
- **오늘:** `_loading = true` → **전체 가운데 스피너**. `sellerMe()` 후 status가 `active`이면 **이어서** `sellerProducts()` · `sellerOrders()` 순차 await. 셸 사이드바는 보이지만 본문은 비움.
- **왜 느린가:** 홈 숫자 카드만 필요한데 오퍼·주문 전체를 직렬로 가져옴. 실패 시 `_seller = null`로 입점 신청 폼이 깜빡일 수 있음.
- **제안:** 메트릭용 요약 API 또는 세 호출 병렬. 이전 스냅샷을 두고 인라인 로딩. `sellerMe`만으로 pending/suspended 분기.
- **역할:** 판매자.
- **심각도:** **med** · **공수:** 작음~중간.
- **상태:** 이 PR에서 적용. `sellerMe` 후 본문 표시, 오퍼·주문은 병렬. 이전 판매자 스냅샷은 실패해도 신청 폼으로 되돌리지 않음.

### S2. 입점 신청

- **화면:** `/seller` 스토어 이름 「입점 신청」
- **오늘:** `_submitting`으로 버튼 「신청 중…」 → `await sellerApply` → 스낵바 → **`_load()` 전체 스피너**.
- **왜 느린가:** 신청 자체는 서버 필수. 이후 홈을 비우고 다시 me/products/orders.
- **제안:** 신청 대기는 유지. 성공 시 로컬 status=`pending` 문구로 바꾸고 `_load`는 silent/`sellerMe`만.
- **역할:** 아직 가게 없는 판매자 포털 계정.
- **심각도:** **low~med** · **공수:** 작음.

### S3. 주문 줄 상태 전진 (출고·배송)

- **화면:** `/seller/orders` 줄 옆 `TextButton` (`nextFulfillmentActionLabel`)
- **오늘:** `runBusy('order:id')`로 버튼만 작은 스피너 → `await sellerUpdateOrderStatus` (void PATCH) → `await _load(silent: true)` GET 전체 주문. UI 배지는 GET 후.
- **왜 느린가:** 탭이 PATCH+목록 GET을 기다림. 줄 상태가 바로 안 바뀜. 필터가 `처리 필요`면 GET 후에야 줄이 사라짐.
- **제안:** 로컬에서 next status로 바꾼 뒤 PATCH. 실패 시 롤백+스낵바. GET은 폴링/진입 1회. 응답 바디가 있으면 그걸로 한 줄만 교체.
- **역할:** 판매자. **낙관적 가능** (실패 시 되돌리면 됨). 최종 배송완료를 구매자 결제처럼 단정하진 말 것.
- **심각도:** **high** · **공수:** 작음.
- **상태:** 이 PR에서 적용. 로컬 next status 후 PATCH. 진행 중 silent GET은 건너뜀.

### S4. 주문 3초 폴링

- **화면:** `/seller/orders` `Timer.periodic(3s)` → `_load(silent: true)`
- **오늘:** `_loading`을 안 켜서 목록이 안 비워짐 (구매자 주문 skipLoading과 유사). 탭이 열려 있으면 3초마다 GET.
- **왜 느린가:** 탭 대기는 아님. 불필요 트래픽·상태 덮어쓰기(진행 중 PATCH와 레이스 가능).
- **제안:** 화면 가시/포커스일 때만. 간격 늘리기. in-flight PATCH 중 silent GET은 건너뛰기.
- **역할:** 판매자.
- **심각도:** **low** · **공수:** 작음.

### S5. 주문 필터 칩

- **화면:** `/seller/orders` 처리 필요 / 준비 중 / 배송 중 / 전체
- **오늘:** `setState(_filter)` **로컬** 필터. 네트워크 없음.
- **제안:** 유지.
- **심각도:** **low** (양호) · **공수:** —

### S6. 내 오퍼 목록 로드·재조회

- **화면:** `/seller/products` `_load`
- **오늘:** 항상 `_loading = true` → 오퍼 섹션을 **가운데 스피너로 교체**. `sellerProducts()` 다음 `sellerCardDrafts()` (실패하면 초안만 빈 배열).
- **왜 느린가:** 초안 제출·다이얼로그 닫힌 뒤에도 목록이 통째로 사라짐. 카드 초안 섹션은 `_loading`과 무관하게 이전 데이터를 그릴 수 있어 오퍼만 깜빡임.
- **제안:** 재조회 시 이전 리스트 유지 + 얇은 프로그레스. 두 GET 병렬. 생성 응답 한 줄을 prepend 하면 GET 생략 가능.
- **역할:** 판매자.
- **심각도:** **high** · **공수:** 작음.
- **상태:** 이 PR에서 적용. 재조회는 이전 리스트+얇은 프로그레스, 두 GET 병렬. 초안 제출 응답을 prepend.

### S7. 「오퍼 초안」 — 품목 찾기 + 제출

- **화면:** `/seller/products` 「오퍼 초안」 → `_CatalogSearchDialog` → 용량/가격 다이얼로그 → `sellerCreateProduct` status=`draft`
- **오늘:** 검색: `_loading`이면 결과 리스트를 스피너로 교체. debounce 없음. 제출은 다이얼로그 `Navigator.pop` 후 `runBusy('register')` + POST + `_load()` (S6 스피너).
- **왜 느린가:** 검색 탭이 목록을 비움. 제출 후 오퍼 리스트가 또 비워짐. 버튼은 POST 동안 「등록 중…」.
- **제안:** 검색은 이전 결과 유지 + 인라인 로딩, 짧은 debounce. 제출 성공 시 로컬 draft 줄 추가, `_load`는 silent. 초안 생성은 서버 필수라 버튼 대기는 허용.
- **역할:** 판매자. UI에 **가격·재고 PATCH / 오퍼 삭제** 는 없음 (Phase 2 API는 있으나 화면 미연결) — CRUD 탭 지연은 생성·목록만.
- **심각도:** **med** · **공수:** 작음.
- **상태:** 이 PR에서 적용. 검색은 이전 결과 유지+인라인 로딩. 제출 후 로컬 prepend + silent refresh.

### S8. 「없는 품목」 카드 초안

- **화면:** `/seller/products` 「없는 품목」 `_CardDraftDialog` → `sellerCreateCardDraft`
- **오늘:** 폼은 로컬. 제출 `runBusy('submit')` → POST → `Navigator.pop(true)` → 부모가 `_load()` (S6).
- **왜 느린가:** MD 검수는 서버 필수. 느린 체감은 닫힌 뒤 오퍼 목록 스피너.
- **제안:** 제출 대기는 유지. 성공 시 `pendingCards`에 한 줄 넣고 silent refresh.
- **역할:** 판매자.
- **심각도:** **med** · **공수:** 작음.
- **상태:** 이 PR에서 적용. 제출 대기는 유지. 성공 시 `pendingCards`에 한 줄 넣고 silent refresh.

- **화면:** `/seller/products` 전체/공개/검수 대기/품절/숨김
- **오늘:** 로컬 `setState`. 네트워크 없음.
- **제안:** 유지.
- **심각도:** **low** (양호) · **공수:** —

### S10. 준비 중 화면 (통계·알림·저장 필터·작업 기록)

- **화면:** `/seller/stats` `/seller/alerts` `/seller/saved-filters` `/seller/activity` — `PortalComingSoonScreen`
- **오늘:** 정적 카피만. API·폴링·mutate 없음. 사이드바 `go`는 즉시.
- **제안:** 손대지 않음 (탭 지연 없음). Phase 3에서 붙일 때 S1·S6 패턴을 복제하지 말 것.
- **역할:** 판매자.
- **심각도:** **low** (해당 없음) · **공수:** —

### S11. 포털 게이트 스피너

- **화면:** `/seller*` `PortalAuthGate` — `auth.isLoading`이면 가운데 스피너 (로그인 폼·본문 대신)
- **오늘:** 부트스트랩 동안 셸+스피너. 세션 없으면 판매자 로그인 화면.
- **제안:** 인증은 서버 필수. 낙관적 입장 금지.
- **역할:** 판매자.
- **심각도:** **low** (의도) · **공수:** —

---

## 관리자

게스트 **N/A**. 역할: 관리자 JWT + `user.isAdmin`. `AdminScreen`이 홈·통계·입점·주문·카탈로그·사용자·도구를 **한 클래스로** 갖고, 라우트마다 `section`만 다름. 알림·저장 필터·감사 로그는 Coming Soon. 목록 상태는 `adminDashboardProvider`로 hoist.

### A1. 섹션 진입마다 전체 `_load()`

- **화면:** `/admin` `/admin/stats` `/admin/sellers` `/admin/orders` `/admin/catalog` `/admin/users` `/admin/tools` — 각각 새 `AdminScreen`
- **오늘:** `initState` → `_load()`: **순차** `adminStats` → `adminUsers(q:)` → `adminSellers(pending)` → `adminCatalogDrafts` → `adminOrders`. 사이드바 탭마다 5호출.
- **왜 느린가:** 입점만 보려 해도 사용자·초안·주문까지 기다림. 통계 화면은 stats만 필요한데 동일.
- **제안:** 섹션별 fetch. 가능하면 셸에서 상태 hoist 또는 `keepAlive`/Riverpod family. 병렬 GET. 사이드바 이동은 이전 본문 유지.
- **역할:** 관리자.
- **심각도:** **high** · **공수:** 중간 (라우트 구조 손봄).
- **상태:** 이 PR에서 적용. 섹션별 fetch + Riverpod hoist. remount 시 이미 로드된 섹션은 재조회하지 않음.

### A2. 로딩 플래그 없는 빈 화면

- **화면:** 입점·주문·카탈로그 초안·사용자. `_stats == null`인 홈/통계만 스피너.
- **오늘:** 첫 페인트가 「대기 중인 입점 신청이 없습니다」 / 「주문 줄이 없습니다」 / 사용자 0명. 데이터 도착 후 채워짐.
- **왜 느린가:** 느린 GET보다 **거짓 빈 상태**가 더 거슬림.
- **제안:** 섹션별 loading/이전 데이터. 빈 카피는 fetch 완료 후에만.
- **역할:** 관리자.
- **심각도:** **high** · **공수:** 작음 (A1과 묶음).
- **상태:** 이 PR에서 적용. 섹션별 loading. 빈 카피는 fetch 완료 후에만.

### A3. 입점 승인

- **화면:** `/admin` 홈 미리보기, `/admin/sellers` 「승인」
- **오늘:** `runBusy('approve:id')` 버튼 스피너 → `await adminApproveSeller` → 스낵바 → **`_load()` 전체 5호출**. 줄은 GET 후에야 사라짐. 정지(suspend) UI는 **없음** (API만 스펙).
- **왜 느린가:** 승인 한 건이 통계·사용자·초안·주문 재조회로 증폭.
- **제안:** 대기 리스트에서 줄을 즉시 제거하고 PATCH. 실패 시 복구. 통계 `pendingSellerCount`만 로컬 -1. 전체 `_load` 금지.
- **역할:** 관리자. 승인 낙관적은 롤백 전제. 정지는 화면이 생긴 뒤 같은 패턴.
- **심각도:** **high** · **공수:** 작음.
- **상태:** 이 PR에서 적용. 대기 리스트에서 즉시 제거 후 PATCH. 실패 시 복구. 전체 `_load` 없음.

### A4. 주문 줄 상태 보정

- **화면:** `/admin/orders` (레거시 비섹션 `/admin` 본문에도 동일 버튼)
- **오늘:** 판매자 S3와 같음 — `runBusy` → `adminUpdateOrderStatus` → `_loadOrders(silent: true)`. 목록은 안 비움. 배지는 GET 후.
- **왜 느린가:** 탭이 PATCH+GET을 기다림.
- **제안:** S3와 동일. 로컬 next status + 실패 롤백. silent GET은 폴링에 맡김.
- **역할:** 관리자 (판매자 대신 상태 보정).
- **심각도:** **high** · **공수:** 작음.
- **상태:** 이 PR에서 적용. 로컬 next status + 실패 롤백. silent GET은 주문 섹션 폴링만.

### A5. 주문 3초 폴링 (전 섹션)

- **화면:** `AdminScreen.initState` `Timer.periodic(3s)` → `_loadOrders(silent: true)`
- **오늘:** **카탈로그·사용자·도구**에 있어도 `adminOrders` GET. 주문 탭이 아니어도.
- **왜 느린가:** 탭 대기는 아님. 운영 도구 트래픽·A4와 레이스.
- **제안:** `section == orders`(또는 홈 미리보기)이고 가시일 때만. 간격 늘리기.
- **역할:** 관리자.
- **심각도:** **med** · **공수:** 매우 작음.
- **상태:** 이 PR에서 적용. `section == orders`일 때만 폴링.

### A6. 카탈로그 초안 붙이기 / 승격

- **화면:** `/admin/catalog` `AdminCatalogDraftsPanel` 「승인」·「기존 카드에 붙이기」·「카드로 승격」
- **오늘:** 붙이기: 카드 초안이면 `_AdminCatalogPickDialog` 검색(A7) 후 `runBusy('draft:id')` → `adminAttachCatalogDraft` → 스낵바 → **`_load()` 전체**. 승격: 다이얼로그(로컬 폼) → `adminPromoteCatalogDraft` → 스낵바 → 다시 `_load()`.
- **왜 느린가:** MD 결정(붙일 카드·종류)은 서버 전 확인이 맞음. 느린 체감은 성공 후 큐가 안 사라지고 통계·사용자까지 재조회.
- **제안:** 성공 시 큐에서 해당 초안만 제거. `_load` 대신 `adminCatalogDrafts`만 silent. **승격은 낙관적 금지** (카탈로그 identity 생성). 붙이기도 실패 롤백이면 큐에서 빼는 정도는 가능.
- **역할:** 관리자 (MD).
- **심각도:** **med** · **공수:** 작음.
- **상태:** 이 PR에서 적용. 붙이기·승격 성공 후 큐에서 해당 초안만 제거. 승격은 서버 확인 후에만 제거. 전체 `_load` 없음.

### A7. 「붙일 카드 찾기」 검색

- **화면:** `_AdminCatalogPickDialog` — `catalogProducts(q:)`
- **오늘:** 판매자 품목 찾기와 동일. 검색 중 리스트 전체 스피너. debounce 없음. 이전 결과 버림.
- **제안:** 이전 히트 유지 + 인라인 로딩. 300ms debounce 또는 검색 버튼만 유지하되 목록은 비우지 않기.
- **역할:** 관리자.
- **심각도:** **med** · **공수:** 작음.
- **상태:** 이 PR에서 적용. 이전 히트 유지 + 인라인 로딩.

### A8. CSV 비상 업로드

- **화면:** `/admin/catalog` · 레거시 홈 `_CatalogImportPanel` → `adminImportCatalog` (업로드 진행률 + processing)
- **오늘:** `runBusy('import')` + `_pageLocked`로 다른 mutate 잠금. 퍼센트·「창을 닫지 마세요」. 완료 후 스낵바. **초안 `_load`는 안 탐**.
- **왜 느린가:** 대량 upsert는 **반드시** 서버. 진행 UI는 이미 있음.
- **제안:** 바꾸지 않음. 낙관적 반영 금지.
- **역할:** 관리자.
- **심각도:** **low** (의도된 대기) · **공수:** —

### A9. 사용자 검색

- **화면:** `/admin/users` 「검색」 / 필드 submit
- **오늘:** `setState(_userQuery)` 후 **`_load()` 전체**. 테이블은 쿼리와 무관한 stats·입점·초안·주문까지 다시.
- **왜 느린가:** 검색 한 번에 5호출. 테이블 갱신 전 이전 행이 남거나(로딩 플래그 없음) 중간에 빈 배열로 덮일 수 있음 (`adminUsers`가 `_load` 마지막 setState에 포함).
- **제안:** `adminUsers(q:)`만. debounce. 이전 테이블 유지 + 인라인 로딩.
- **역할:** 관리자.
- **심각도:** **high** · **공수:** 작음.
- **상태:** 이 PR에서 적용. `adminUsers(q:)`만. 이전 테이블 유지.

### A10. 사용자 역할 저장 · 삭제

- **화면:** 사용자 테이블 관리자 체크박스(로컬 `_adminDraft`) 「저장」 / 「삭제」
- **오늘:** 체크박스는 즉시. 저장: `runBusy` → `adminUpdateUser` → 스낵바 → **`_load()` 전체** (초안 맵을 users로 재구축). 삭제: 확인 다이얼로그 후 동일하게 전체 `_load`.
- **왜 느린가:** 한 행 PATCH/DELETE가 포털 전 리소스 재조회. 저장 전까지 체크박스는 이미 로컬이라, 느린 건 저장 탭과 이후 깜빡임.
- **제안:** 저장은 행 busy 유지(권한 변경은 서버 확인이 맞음). 성공 시 그 행만 갱신. 삭제는 낙관적 제거 + 실패 복구. `_load` 금지.
- **역할:** 관리자. 본인 관리자 해제 등 실패 가능 — 롤백 전제.
- **심각도:** **med** · **공수:** 작음.
- **상태:** 이 PR에서 적용. 저장은 행 busy 후 그 행만 갱신. 삭제는 낙관적 제거 + 실패 복구.

### A11. DB 초기화

- **화면:** `/admin/tools` 「DB 초기화 실행」 (`seed` / truncate)
- **오늘:** wipe는 확인 다이얼로그. `runBusy('reset')` + `_pageLocked` + 「창을 닫지 마세요」 → `adminDbReset` → 스낵바 → **`_load()`**.
- **제안:** 대기는 유지. 낙관적 초기화 금지. 끝난 뒤 섹션별 refresh면 충분.
- **역할:** 관리자 (개발용).
- **심각도:** **low** (의도) · **공수:** —

### A12. 준비 중 화면 (알림·저장 필터·감사 로그)

- **화면:** `/admin/alerts` `/admin/saved-filters` `/admin/audit` — `PortalComingSoonScreen`
- **오늘:** 정적. API 없음. `/admin/audit`는 카피에 입점 승인·카드 연결·주문 보정이 있으나 데이터 없음.
- **제안:** 손대지 않음. Phase 3에서 A1 전체 `_load`를 복제하지 말 것.
- **역할:** 관리자.
- **심각도:** **low** (해당 없음) · **공수:** —

### A13. 포털 게이트 · isAdmin 가드

- **화면:** `/admin*` `PortalAuthGate` + `user.isAdmin != true` 이면 「관리자 권한이 필요합니다.」
- **오늘:** 부트스트랩 스피너(S11과 동일). 세션은 있으나 isAdmin이 아니면 본문 대신 문구 — 추가 API 없음.
- **제안:** 인증·권한 낙관적 입장 금지.
- **역할:** 관리자.
- **심각도:** **low** (의도) · **공수:** —

---

## 이미 괜찮은 것

| 액션 | 역할 | 이유 |
|------|------|------|
| 상세 담기 전 +/- | 구매자 | 로컬 `QtyStepper` / `_qtyByOffer` |
| 식탁 대/중분류 탭 | 구매자 | 로컬 taxonomy. 카드 목록만 fetch |
| 카탈로그 reload 스피너 | 구매자 | `skipLoadingOnReload` + 얇은 프로그레스 |
| 주문 reload 깜빡임 | 구매자 | 동일 |
| 판매자 주문·오퍼 필터 칩 | 판매자 | 로컬 `setState`, GET 없음 |
| 관리자 역할 체크박스 | 관리자 | 저장 전까지 로컬 `_adminDraft` |
| Coming Soon 사이드바 | 판매자·관리자 | 정적 화면, 탭 지연 없음 |
| CSV 업로드 진행률 | 관리자 | 의도된 대기 + 프로그레스 |
| 찜 / PTR | 공통 | 기능 없음 |

---

## 역할 요약

| 흐름 | 게스트 | 구매자 | 판매자 | 관리자 |
|------|--------|--------|--------|--------|
| 목록·상세 | 공개 GET | 동일 | 포털 밖 | 포털 밖 |
| 담기 / 카트 +/- | `main`: 로그인 게이트. 이 PR: 로컬 카트 | PUT+invalidate (`main`) / 낙관적 (이 PR) | N/A | N/A |
| 체크아웃·결제 | 로그인 게이트 유지 | `prepareToss` 필수 | N/A | N/A |
| 주문 상태 변경 | N/A | 목록 폴링만 (변경 UI 없음) | PATCH + 전체 GET (S3) | PATCH + GET (A4) |
| 오퍼·초안 CRUD | N/A | N/A | 생성 POST + 목록 스피너. 수정/삭제 UI 없음 | 붙이기/승격 POST + 전체 `_load` |
| 입점 | N/A | N/A | 신청 POST + `_load` | 승인 POST + 전체 `_load`. 정지 UI 없음 |
| 사용자·도구 | N/A | N/A | N/A | 검색/저장도 전체 `_load`. CSV·DB리셋은 의도 대기 |
| 인증 | 몰 공개 | BuyerAuthGate | PortalAuthGate seller | PortalAuthGate admin + isAdmin |

---

## 손대지 말 것 (낙관적 금지)

- 토스 준비·승인·결제 결과
- 로그인·가입·포털 입장 성공 처리
- 체크아웃 인증 리다이렉트
- 카탈로그 CSV 반영 · DB 초기화
- 카드 **승격**(새 identity). 붙이기는 롤백 전제에서만
- 서버가 거절할 수 있는 재고를 **성공처럼** 결제 단계까지 미는 것
- 입점 승인·주문 배송 완료를 확인 없이 영구 성공으로 단정 (로컬 선반영은 롤백과 같이)

---

## 추천 적용 순서 (구현은 항목별 상태)

구매자 (몰, Phase 2)

1. ~~장바구니 +/- · 삭제~~ — **이 PR에서 적용** (낙관적 + debounce + skipLoading). 체크아웃 게이트 유지.
2. ~~로그인 담기 뱃지~~ — **이 PR에서 적용** (POST 전 뱃지, 실패 롤백). 버튼은 서버 대기.
3. ~~배송지 삭제~~ — **이 PR에서 적용**
4. ~~검색 첫 입력 랜딩 유지~~ — **이 PR에서 적용**

판매자

1. ~~S3 주문 상태 탭~~ — **이 PR에서 적용**
2. ~~S6 오퍼 `_load` 스피너~~ — **이 PR에서 적용**
3. ~~S1 홈 직렬 fetch~~ — **이 PR에서 적용**
4. ~~S7 품목 검색 다이얼로그 스피너~~ — **이 PR에서 적용**
5. S4 폴링 가시/포커스만 (low) — 미적용. PATCH 중 silent GET은 건너뜀.

관리자

1. ~~A1·A2 섹션 `_load` / 거짓 빈 화면~~ — **이 PR에서 적용**
2. ~~A3 입점 승인~~ — **이 PR에서 적용**
3. ~~A9 사용자 검색~~ — **이 PR에서 적용**
4. ~~A4 주문 보정~~ — **이 PR에서 적용**
5. ~~A6 초안 한 줄 제거~~ — **이 PR에서 적용**. 승격은 서버 확인 유지
6. ~~A5 주문 폴링을 주문 섹션으로 제한~~ — **이 PR에서 적용**
7. ~~A7 카드 검색 다이얼로그~~ — **이 PR에서 적용**
8. A8·A11 유지 (의도된 대기)

남은 낮은 우선: 구매자 주문 폴링 간격(11), 상세 진입 fetch(15), 판매자 S4 가시 범위.
