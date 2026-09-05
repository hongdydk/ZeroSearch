# Phase 2 — 제로 서치 마켓플레이스

**SSOT** — 엔티티·API·Flutter 라우트·DoD.

**제품:** [제로 서치](./README.md) — 종류(생수·떡갈비)로 들어가면 **회사+유형+품목 카드가 쭈르륵**. 같은 회사의 그 품목은 용량·판매자만 1장으로 줄인다. 카드 **단위당 대표가(중위)**, 상세 **오퍼 한 줄 비교**.

**사업 모델:** [docs/README.md](./README.md) — **자체 몰** 확정. 크롤링 가격비교는 Phase 2 범위 아님.

## 목표

1. 입점·공식 판매자를 한 마켓플레이스로 통합한다.
2. **검색·목록** — 「생수」·「떡갈비」처럼 **종류**로 들어가면 결과는 그 안의 **회사+품목 카드가 쭈르륵**(백산수, 평창수…). 같은 회사·유형·품목의 오퍼 수만큼 카드를 늘리지 않는다.
3. 목록 카드에는 연결 오퍼 **단위당 대표가(중위, median)** 만 노출한다. **최저가·「~」 표기 없음.**
4. **옵션 필터** — `flavor`, `volume_ml_min/max`로 집계 대상 오퍼를 좁힌다.
5. **상세** — 선택한 대표 상품의 오퍼(맛·용량·가격·가게·배송)를 한 줄 비교. 개별 최저가는 **상세 오퍼 줄**에서만 확인.
6. 주문 줄에 `seller_id`, 배송 상태·주체를 남긴다.

현재 코드는 **대표 상품(`catalog_products`) + 오퍼(`products`)** 분리.

## 엔티티

### 신규: `sellers`

| 필드 | 설명 |
|------|------|
| `user_id` | 1유저 1스토어 |
| `shop_name`, `slug` | 노출명·URL |
| `status` | `pending` / `active` / `suspended` |
| `seller_type` | `platform` (공식) / `merchant` (입점) |

### 신규 (제로 서치): `catalog_products` (대표 상품)

| 필드 | 설명 |
|------|------|
| `title` | 브랜드·제품명. 목록 카드 제목. 예: 「백산수」「평창수」 |
| `category` | 검색·필터용 카테고리. 예: `생수` — **title과 구분** |
| `description`, `image_url` | 대표 설명·이미지 |
| `search_keywords` | 추가 검색어 (브랜드 별칭 등) |
| `price_unit` | UI 라벨용 — `ml` / `each` |

목록 응답(집계): `offer_count`, `median_unit_price`(또는 `median_price_credits`), `price_unit`, `display_price_label` — 하위 오퍼에서 계산, DB 컬럼 필수 아님. **`min_price_credits` 목록 응답·카드 UI에 노출하지 않음.**

**집계 규칙:** 공개 오퍼(`published` + seller `active`)만. `volume_ml > 0` 오퍼가 있으면 `unit_price = price_credits / volume_ml` 목록의 **median** → 카드 유일 가격. 없으면 `price_credits` **median** (전자·패션 fallback).

### 변경: `products` (오퍼)

- `catalog_product_id` FK — 어느 대표 상품에 속하는지
- `seller_id` FK NOT NULL
- `option_label` — 용량 등 (예: `500ml × 20`)
- `volume_ml` — nullable, 팩 총 ml (500×20 → 10000)
- `flavor` — nullable (예: `레몬`, `자몽`)
- `status`: `draft` / `published` / `archived`
- 공개: `published` + 판매자 `active`

### 변경: `order_items`

- `seller_id` FK (체크아웃 스냅샷)
- `fulfillment_status`: `paid` / `preparing` / `shipped` / `delivered`
- 배송 주체: `sellers.seller_type` — `platform`(자사배송) / `merchant`(판매자배송)

## API

### 공개 (제로 서치)

| Method | Path | 설명 |
|--------|------|------|
| GET | `/catalog-products` | **대표 상품** 목록·검색. `q=생수&category=생수&flavor=레몬&volumeMlMin=2000`. 각 row에 **median 대표가만** |
| GET | `/catalog-products/{id}` | 대표 상품 + **오퍼 한 줄** 목록 |
| GET | `/products/{id}` | (과도기) 단일 오퍼 — 장바구니·기존 링크 |

과도기: 기존 `GET /products`는 장바구니 호환용 유지. 제로 서치 DoD는 **`/catalog-products` 기준**.

### 판매자 (`active` seller)

| Method | Path |
|--------|------|
| POST | `/seller/apply` |
| GET | `/seller/me` |
| GET/POST/PATCH/DELETE | `/seller/products` |
| GET | `/seller/orders` |
| PATCH | `/seller/orders/items/{id}/status` |

### 관리자

| Method | Path |
|--------|------|
| GET | `/admin/sellers` |
| POST | `/admin/sellers/{id}/approve` |
| POST | `/admin/sellers/{id}/suspend` |
| GET | `/admin/orders` |
| PATCH | `/admin/orders/items/{id}/status` |

기존 `/admin/stats` — `seller_count`, `pending_seller_count` 추가.

## Flutter 라우트

| Path | 화면 |
|------|------|
| `/` | **대표 상품** 카탈로그·검색·옵션 필터. Browse는 쿼리: `/`, `/?major=…`, `/?major=…&mid=…` |
| `/catalog/:id` | 상세 — **오퍼 한 줄 비교**, 더보기 |
| `/products/:id` | (과도기) 단일 오퍼 — 장바구니 |
| `/cart` | 장바구니 (가게별 묶음) |
| `/orders` | 주문 — 줄별 가게·배송 |
| `/login` | 구매자 로그인 |
| `/seller` | 판매자 로그인부터 · 대시보드 |
| `/seller/products` | 내 오퍼 |
| `/seller/orders` | 내 주문 줄 |
| `/admin` | 관리자 로그인부터 · 입점 승인 |

**로그인 (현재):** 역할별 진입. 구매자 `/login`, 판매자는 `/seller`에서·관리자는 `/admin`에서 **각각 로그인부터**. 도메인 분리 아님. SSOT: [docs/README.md](./README.md) 「호스트·로그인」.

## DoD

- 「생수」·「떡갈비」 검색 → 그 종류 **회사+품목 카드가 여러 장** (백산수 오퍼 12개여도 백산수 카드 1장, **L당 median 대표가만** — 최저가 미노출)
- `flavor=레몬` 필터 시 해당 오퍼만 반영된 집계·상세
- 상세에서 맛·용량·가격·판매자(공식/입점·배송) **한 줄 비교**
- 입점 신청 → 승인 → 오퍼 등록 → 주문에 `seller_id` 반영
- 공식·입점 혼합 장바구니·결제 (크레딧 스텁; 실 PG는 Phase 4)
- `fulfillment_status` 전이 + 구매자 주문 화면 폴링
- pytest·flutter analyze 통과

### 구매자·장바구니 UX 이슈 해소

[docs/ux-issues.md](./ux-issues.md) #1–9를 Phase 2에서 해소한다. **증상·원인·해결방향은 ux-issues만** — 여기서는 DoD 체크리스트만 둔다. UX 적용 순서는 ux-issues 「적용 순서」(#1–9). **same-origin(`/api`)은 DoD 밖이나 UX 구현보다 먼저 적용할 수 있다** — [follow-ups.md](./follow-ups.md). 판매자·관리자 보강은 Phase 3, 토스 PG는 Phase 4.
| # | DoD (요약) |
|---|------------|
| 1 | 검색·필터 시 목록 유지 + debounce |
| 2 | 주문 폴링 시 깜빡임 없음 |
| 3 | 게스트 담기 → 로그인 후 `next` 복귀 |
| 4 | `/cart` 가게별 묶음 |
| 5 | 맛·용량 필터가 현재 종류에만 |
| 6 | 검색 ↔ 식탁 drill 배타/정리 |
| 7 | 상세 back · 배송 라벨 · 좁은 폭 overflow 없음 |
| 8 | 빈·에러 카피 · 주문 empty CTA |
| 9 | 모바일 뒤로가기 · 스크롤 복원 (Browse = URL 쿼리) |

same-origin(`/api` 프록시)은 [follow-ups.md](./follow-ups.md) — Phase 2 DoD 밖.

### 구매·주문 안정화

Phase 2 DoD 이후 구매자 결제 경로 정합성·부하. Phase 3/3.5/4와 섞지 않는다.

| # | 항목 | 상태 |
|---|------|------|
| 1 | **재고 동시성** — 같은 SKU 동시 주문에도 성공 수량 ≤ 재고, 재고 음수 금지 | **적용됨** |
| 2 | **크레딧 동시성** — 테스트 스텁 지갑 잠금 | **Phase 4로 이관** — 실제 결제 중복·상태 정합성으로 대체 |
| 3 | **체크아웃 idempotency** — 재시도·다중 탭 중복 주문/차감 금지 | **적용됨** |
| 4 | **인증 전환 안정성** — bootstrap 로그인 flash, 회원가입 `next` 유실 해소 | **적용됨** |
| 5 | **카탈로그 완결성** — 목록 50개 제한 해소 · 카드 그리드 스크롤 복원 | **적용됨** |
| 6 | **장바구니 최신성** — 품절·판매중지·판매자 정지를 결제 전에 표시 | **적용됨** |
| 7 | **동시 다량 주문 부하 (MVP)** — DB pool 명시 · 서로 다른 상품 50건 기준선 | **적용됨** · 전체(worker/rate limit/큐)는 [load-baseline.md](./load-baseline.md) 문서만 |

## 배포

Flutter → **Cloudflare Pages** (`mall.anoveli.com`). FastAPI → EC2 Docker (`mall-api` :8001). PostgreSQL → EC2 `mall-postgres`.  
대표 상품 SSOT는 `data/aihub-catalog.csv` — `main` 배포 시 EC2에서 upsert.  
브라우저 API: **`https://mall.anoveli.com/api`** (Pages Functions → Tunnel `mall-api.anoveli.com`). 원본 API 호스트는 프록시 백엔드용으로 유지.

### 카탈로그 재병합 (맛·용량 → 대표 카드)

- **병합 단위:** `제조사 + 소분류 + 유사 기본 품목명`. 용량·맛은 변형(`reference_variants`)으로 보존.
- **규칙 버전:** `catalog_identity.NORMALIZATION_VERSION` (배포 fingerprint에 포함 → 규칙 변경 시 재import).
- **고신뢰만 자동 병합.** 중간 신뢰는 dry-run 보고만, 별도 카드 유지.
- **운영 적용 순서 (production):**
  1. DB 백업
  2. Alembic `007` 적용 (`reference_variants`, `catalog_product_aliases`)
  3. `cd apps/api && python -m scripts.remerge_catalog` (dry-run 수치 확인)
  4. `python -m scripts.remerge_catalog --apply`
  5. CSV canonical import (`FORCE_CATALOG_IMPORT=1` 또는 fingerprint 갱신 배포)
  6. smoke: 대표 카드 수·오퍼 수·옛 상세 UUID(alias)·장바구니/주문
- 상세 API는 alias UUID를 생존 대표로 해석. AI-Hub 변형은 구매 불가 `referenceVariants`로만 노출.
- **CSV dry-run (v2, `data/aihub-catalog.csv`):** source 9886 → high-confidence groups 9064 (−822 cards), medium candidates 944 (자동 병합 안 함), 용량-only 제목 0건.
- v1의 괄호 옵션 오인으로 용량만 남았던 카드는 v2 import 후 `repair_volume_titles`로 원본 변형별 canonical 카드와 alias를 복구한다.
