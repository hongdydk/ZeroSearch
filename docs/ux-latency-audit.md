# 구매자 UX 지연 감사 (탭이 서버를 기다림)

**범위:** `apps/flutter` 몰 구매자 흐름. `main` @ 조사 시점. 동작 변경 없음 — 우선순위용 목록.  
**Phase:** 구매 UX는 Phase 2 유지. 결제는 Phase 4. 멤버십은 제품 범위 밖(레거시 화면만).  
관련: [ux-issues.md](./ux-issues.md) #1–9(스피너·폴링 깜빡임은 이미 적용). 이 문서는 **그 이후에도 탭이 네트워크를 기다리는** 지점.

---

## 가설 검증 (게스트 장바구니 +/-)

요청에 나온 경로:

`updateVisibleCartQty` → guest storage → `invalidate(cartProvider)` → `loadGuestCart`가 줄마다 `api.product()`

**현재 `main`에는 이 코드가 없다.** 검색해도 `GuestCartLine` / `guest_cart.dart` / `loadGuestCart` / `updateVisibleCartQty` 없음.

실제로:

- 게스트 장바구니는 **로컬 저장이 없다.** `cartProvider`는 구매자 JWT가 없으면 빈 카트를 메모리에서 바로 반환한다 (`app_providers.dart`).
- `/cart` · `/checkout` · `/orders` · `/settings*` · `/membership` 는 `_requiresAuth` → `/login?next=…` (`app_router.dart`).
- 상세 「담기」는 비로그인이면 `beginGuestAddLogin` — 로그인 화면으로 보내고, 로그인 후 한 번 `addToCart`.
- 장바구니 +/- 는 **로그인 구매자만** 탄다. 느림의 원인은 게스트 product GET 루프가 아니라 아래 **구매자 PUT + invalidate + GET + 전체 스피너**.

게스트 로컬 카트를 **새로** 만들 계획이면, 처음부터 스냅샷(제목·가격·수량)으로 UI를 그리고 product GET은 `/cart` 진입 1회로 제한해야 한다. 지금 느린 +/- 를 고치려면 구매자 경로가 1순위다.

---

## 반복 패턴

1. **응답 바디를 버리고 다시 GET** — `addToCart` / `updateCartItem` / `removeFromCart` 가 이미 `CartModel`을 돌려주는데, 화면은 무시하고 `invalidate(cartProvider)` → `GET me/cart`.
2. **`skipLoadingOnReload` 없음** — 카탈로그·주문만 적용. 장바구니·체크아웃·배송지는 invalidate 시 `when(loading:)` 전체 스피너로 떨어진다.
3. **`FutureProvider.autoDispose`** — 헤더/탭 `CartCountBadge`가 `cartProvider`를 watch 해서 셸이 있으면 보통 살아 있다. 그래도 invalidate 하면 reload loading 처리가 허술하면 체감이 크다.
4. **낙관적 갱신 없음** — 수량·삭제·담기 뱃지 모두 서버 왕복 후.
5. **찜·Pull-to-refresh** — 없음. PTR 오남용 이슈 없음.

---

## 인벤토리

각 항목: 화면/액션 → 오늘 → 왜 느린가 → 제안 → 심각도·공수. 게스트 vs 로그인 차이는 항목 안에.

### 1. 장바구니 수량 +/-  (우선)

- **화면:** `/cart` `CartScreen` `IconButton` +/- (`QtyStepper` 위젯 아님)
- **오늘:** `runBusy`로 버튼 잠금 → `await updateCartItem` (`PUT me/cart`, 응답에 카트 있음) → `invalidate(cartProvider)` → `GET me/cart`. `when()`에 `skipLoadingOnReload` 없음 → 목록 대신 가운데 스피너. 재고/이슈 재계산은 GET 응답 기준.
- **왜 느린가:** 탭마다 **쓰기 + 읽기** 두 왕복. 그 사이 화면이 비워짐. 연속 +/- 는 이전 요청이 끝날 때까지 잠김.
- **제안:** (a) PUT 응답 `CartModel`로 `cartProvider`를 바로 채움 (invalidate 금지). (b) 화면 수량을 먼저 올리고 실패 시 롤백. (c) `skipLoadingOnReload: true`. 재고 한도는 서버 에러 메시지로. 라이브 재고/가격은 `/cart` 진입·소프트 새로고침 1회.
- **게스트:** 카트 화면 진입 자체가 로그인. +/- 없음.
- **로그인:** 이 경로가 체감 핵심.
- **심각도:** **high** · **공수:** 작음 (응답 재사용 + skipLoading). 낙관적 UI는 중간.

### 2. 장바구니 줄 삭제

- **화면:** `/cart` 휴지통
- **오늘:** +/- 와 동일 — `removeFromCart` 응답 버리고 invalidate + GET + 전체 스피너.
- **왜 느린가:** 1과 같음. 줄이 바로 안 사라짐.
- **제안:** 로컬에서 줄 제거 후 DELETE. 실패 시 복구. 또는 DELETE 응답 카트를 그대로 넣기.
- **게스트/로그인:** 1과 같음.
- **심각도:** **high** · **공수:** 작음 (1과 같이 하는 게 맞음).

### 3. 상세 「담기」 / 「장바구니 담기」

- **화면:** `/catalog/:id` 오퍼 줄 `담기`; 과도기 `/products/:id` `장바구니 담기`
- **오늘:** 담기 전 수량 스테퍼는 **로컬 `setState`** (즉시). 담기는 `runBusy` → `await addToCart` → `invalidate(cartProvider)` → GET. 성공 스낵바는 POST 이후. 헤더 뱃지는 GET 후 `totalQty`.
- **왜 느린가:** 버튼이 POST(+GET) 동안 잠김. 담은 느낌이 네트워크 RTT만큼 늦음. 뱃지도 한 박자 늦음.
- **제안:** 낙관적으로 뱃지 `totalQty` += qty, 스낵바를 먼저. POST 실패 시 뱃지 롤백 + 에러 스낵바. `cartProvider`는 POST 응답으로 갱신 (GET 생략). 재고 레이스는 서버 거절이 정답.
- **게스트:** API 없이 `/login?next=…&addOffer=&addQty=`. 느린 건 카트가 아니라 **로그인 게이트**. 로그인 후 `consumePendingCartAddIfBuyer`가 `addToCart`+invalidate — 한 번이라 낮음.
- **로그인:** POST+GET+버튼 잠금.
- **심각도:** **med** (담기는 한 번, +/- 만큼 반복되지 않음) · **공수:** 작음~중간.

### 4. 장바구니·체크아웃 최초 로딩 / invalidate 시 스피너

- **화면:** `/cart`, `/checkout` 가 `cartProvider` `when(loading:)` 전체 스피너
- **오늘:** 셸 뱃지가 이미 cart를 watch 하면 재진입은 데이터가 있을 수 있음. **invalidate 직후**는 이전 값을 그려 주지 않음. 에러 재시도도 invalidate.
- **왜 느린가:** 실제 왕복보다 **빈 스피너 교체**가 더 거슬림. ux-issues #1과 같은 병.
- **제안:** `skipLoadingOnReload: true` + 인라인 진행만. 에러 재시도만 전체 스피너.
- **게스트:** `/cart`·`/checkout` 접근 시 로그인으로 보냄 (체크아웃 인증 게이트 유지).
- **심각도:** **med** (1·2를 증폭) · **공수:** 매우 작음. 1과 묶어서.

### 5. 검색 첫 커밋 전체 스피너

- **화면:** 홈/헤더 검색. `CatalogSearchDebounce` 300ms 후 `go(?q=)` → fetch
- **오늘:** 키 입력 debounce·reload 시 목록 유지는 **적용됨** (ux-issues #1, `skipLoadingOnReload`, 상단 `LinearProgressIndicator`). 랜딩에서 글자를 치기 시작하면 `awaitingFirstSearch` 동안 **가운데 스피너만**.
- **왜 느린가:** 첫 검색 300ms + RTT 동안 랜딩이 사라짐.
- **제안:** 랜딩/이전 그리드를 유지하고 인라인 로딩만. 결과는 커밋 후 교체. 칩·drill은 이미 로컬.
- **게스트/로그인:** 동일 (공개 목록).
- **심각도:** **med** · **공수:** 작음.

### 6. 생수 맛·용량 칩

- **화면:** 목록 `_FilterChips` (생수 mid/검색일 때만)
- **오늘:** 탭이 `catalogFlavorFilterProvider` / volume을 즉시 바꿈 → `catalogProductsProvider`가 offset 0부터 다시 GET. reload 시 이전 그리드+얇은 프로그레스는 유지.
- **왜 느린가:** 칩은 즉시 선택돼 보이지만 카드는 네트워크 후. 디바운스 없음 (연속 탭 시 요청 폭주 가능).
- **제안:** 칩 선택은 로컬 유지. 목록은 지금처럼 previous+인라인 로딩. 빠른 연속 탭이면 짧은 debounce 또는 in-flight 취소. 클라이언트 필터는 오퍼 집계가 서버라 부적합.
- **게스트/로그인:** 동일.
- **심각도:** **low~med** · **공수:** 작음.

### 7. 목록 페이지네이션

- **화면:** 그리드 하단 근접 시 `loadMore`
- **오늘:** 기존 아이템 유지, `loadingMore` 스피너, offset GET append. 실패 시 이전 목록 복구.
- **왜 느린가:** 하단 스피너만. 탭 대기는 아님.
- **제안:** 유지. keepAlive/캐시는 재방문 최적화용 (선택).
- **심각도:** **low** (양호) · **공수:** —

### 8. 배송지 삭제

- **화면:** `/settings/addresses` 휴지통
- **오늘:** `await deleteAddress` → `invalidate(addressesProvider)`. busy 가드 없음(연타 가능). `when()`에 skipLoadingOnReload 없음 → 목록이 스피너로 교체.
- **왜 느린가:** 줄이 바로 안 사라지고 화면이 비워짐.
- **제안:** 낙관적 제거 + skipLoadingOnReload. 실패 시 되돌림. 폼 저장은 서버 확인 후 pop이 맞음 (낙관적 이득 적음).
- **게스트:** 주소 라우트는 로그인 필수.
- **심각도:** **med** · **공수:** 작음.

### 9. 배송지 저장 · 주소 찾기

- **화면:** `/settings/addresses/new`·`:id` 「저장」, 「주소 찾기」
- **오늘:** 저장은 `runBusy` + create/update + invalidate + pop. 주소 찾기는 다음 우편 위젯 (로컬 네트워크).
- **왜 느린가:** 저장 버튼 「저장 중…」는 적절. 다음 우편은 외부 UI.
- **제안:** 저장은 서버 왕복 유지. pop 전 로컬 목록에 삽입하면 목록 재진입 스피너만 줄어듦 (8과 함께).
- **심각도:** **low** · **공수:** 작음.

### 10. 주문서 「토스로 결제하기」

- **화면:** `/checkout` 결제 버튼
- **오늘:** `prepareTossPayment` 동안 `_checkingOut`. 성공 시 토스 URL로 `go`. 카트 줄 수량은 주문서에서 못 바꿈.
- **왜 느린가:** intent 생성은 **반드시** 서버. 낙관적 결제는 금지 (Phase 4).
- **제안:** 바꾸지 않음. 「결제 준비 중…」 유지. 카트 invalidate 없음.
- **게스트:** `/checkout` → 로그인. 게이트 유지.
- **심각도:** **low** (의도된 대기) · **공수:** —

### 11. 주문 목록 3초 폴링

- **화면:** `/orders`
- **오늘:** `Timer.periodic(3s)` → `refresh(ordersProvider)`. `skipLoadingOnReload: true` (ux-issues #2). 탭 액션 없음.
- **왜 느린가:** 깜빡임은 고침. 탭이 열려 있으면 3초마다 GET.
- **제안:** 포커스/가시일 때만, 또는 간격 늘리기. 탭 체감과는 별개.
- **게스트:** 로그인 필수.
- **심각도:** **low** · **공수:** 작음.

### 12. 멤버십 「구독」

- **화면:** `/membership` (제품 범위 밖, 레거시)
- **오늘:** `await subscribe` → `invalidate(myMembershipProvider)` + `creditsProvider`. 구독 카드 `when(loading:)` 가 LinearProgressIndicator (skipLoading 없음).
- **제안:** 우선순위 낮음. 손대면 skipLoading + 응답으로 구독 상태 채우기.
- **게스트:** 로그인 필수.
- **심각도:** **low** · **공수:** 작음.

### 13. 로그인 / 가입 / 부트스트랩

- **화면:** `/login` 「로그인」, 앱 시작 `AuthNotifier._bootstrap`
- **오늘:** 로그인: `login` 후 `me` (연속 2회). 가입은 `authState` 전체 loading. 부트스트랩은 포털 슬롯마다 `me`. `BuyerAuthGate`는 bootstrap 중 스피너 — 카트 flash 방지용.
- **왜 느린가:** 인증은 서버 필수. 게스트 담기 왕복은 여기 포함.
- **제안:** 로그인 응답에 user를 넣으면 `me` 생략 가능 (API 계약). UX 낙관적은 비추천.
- **심각도:** **low~med** (담기→로그인 흐름에서만 두드러짐) · **공수:** API면 중간, 아니면 손대지 않음.

### 14. 결제 결과 확인

- **화면:** `/payment/success` 진입 시 `confirmTossPayment`
- **오늘:** 승인 GET/POST 후 cart·orders invalidate. 의도된 대기 카피.
- **제안:** 낙관적 완료 금지.
- **심각도:** **low** (의도) · **공수:** —

### 15. 상세 진입 fetch

- **화면:** 카탈로그 상세 `catalogProductDetailProvider`; 오퍼 상세 `FutureBuilder` + `api.product`
- **오늘:** 화면 열 때 1회 GET. 오퍼 상세는 Riverpod 캐시 없음 (Future 필드). 목록→상세는 카드 데이터가 있어도 다시 GET.
- **왜 느린가:** 탭(담기)이 아니라 페이지 로드.
- **제안:** 목록 카드를 상세 스켈레톤에 쓰고 오퍼 줄을 fetch. 오퍼 상세도 family provider. 담기 낙관적과는 별개.
- **게스트/로그인:** 동일.
- **심각도:** **low~med** · **공수:** 중간.

---

## 이미 괜찮은 것

| 액션 | 이유 |
|------|------|
| 상세 담기 전 +/- | 로컬 `QtyStepper` / `_qtyByOffer` |
| 식탁 대/중분류 탭 | 로컬 taxonomy + `go` URL. 중분류 그리드는 로컬. 카드 목록만 fetch |
| 카탈로그 reload 스피너 | `skipLoadingOnReload` + 얇은 프로그레스 |
| 주문 reload 깜빡임 | 동일 |
| 뱃지 구독 | 셸이 cart를 살려 둬 재진입 GET을 줄임 (invalidate만 문제) |
| 찜 | 기능 없음 |
| Pull-to-refresh | 없음 |

판매자·관리자 화면도 `runBusy`+await API가 많지만 운영 도구라 이 목록 밖 (Phase 3).

---

## 게스트 vs 로그인 (요약)

| 흐름 | 게스트 | 로그인 구매자 |
|------|--------|----------------|
| 목록·상세 보기 | 공개 GET | 동일 |
| 담기 | 로그인으로 보냄 (`next`+pending add). 로컬 카트 없음 | POST cart + invalidate GET |
| `/cart` +/-·삭제 | 진입 시 로그인. 가설의 product GET 루프 없음 | PUT/DELETE + invalidate GET + 전체 스피너 |
| 체크아웃 | 로그인 게이트 유지 (`_requiresAuth`). 깨지 말 것 | `prepareToss` 필수 대기 |
| 주문·주소·멤버십 | 로그인 | 위 8–12 |
| 로그인 후 병합 | pending **한 줄** add만. 게스트 카트 merge-on-login 없음 | n/a |

게스트 로컬 카트+로그인 병합을 넣을 때: SharedPreferences 스냅샷으로 UI, product GET은 열 때 1회, +/- 는 로컬, 로그인 시 서버 카트에 merge. 체크아웃·담기 게이트는 유지.

---

## 손대지 말 것 (낙관적 금지)

- 토스 준비·승인·결제 결과
- 로그인·가입 성공 처리
- 체크아웃 인증 리다이렉트
- 서버가 거절할 수 있는 재고를 **성공처럼** 결제 단계까지 밀어 넣는 것 (담기/수량 낙관적은 롤백 전제)

---

## 추천 적용 순서 (구현은 아직 하지 않음)

1. **장바구니 +/- · 삭제:** PUT/DELETE 응답으로 provider 갱신, invalidate+GET 제거, `skipLoadingOnReload`. (high, 작은 diff)
2. 같은 패턴으로 **담기** 뱃지/목록 (med)
3. **배송지 삭제** 낙관적 + skipLoading (med)
4. 검색 첫 입력 때 랜딩을 스피너로 바꾸지 않기 (med)
5. (제품 결정) 게스트 로컬 카트 — 지금 느린 +/- 의 원인이 아님. 로그인 없이 `/cart`를 열려면 별도 Plan

`cartProvider`를 `AsyncNotifier`로 바꿔 `state = AsyncData(updated)` 하는 편이 `FutureProvider`+invalidate보다 맞다. 구현 전에 Plan 승인.
