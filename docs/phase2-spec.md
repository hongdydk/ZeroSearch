# Phase 2 — 제로 서치 마켓플레이스

**SSOT** — 엔티티·API·Flutter 라우트·DoD.

**제품:** [제로 서치](../report/프로젝트-컨셉.md) — 검색·목록 **중복을 줄인다**. **브랜드(제품명)당 대표 1장** + 카드 **최저가**, 상세는 **오퍼 한 줄 비교**.

## 목표

1. 입점·공식 판매자를 한 마켓플레이스로 통합한다.
2. **검색·목록** — 카테고리 검색(예: 「생수」) 결과는 **브랜드별 대표 상품**(백산수, 평창수…). 오퍼 수만큼 카드를 늘리지 않는다.
3. 목록 카드에는 연결 오퍼 **최저가**(`min_price_credits`)를 노출한다.
4. **상세** — 선택한 대표 상품의 오퍼(용량·가격·가게·배송)를 한 줄 비교.
5. 주문 줄에 `seller_id`, 배송 상태·주체를 남긴다.

현재 코드가 `products` 한 테이블만 쓰는 경우, Plan에서 **대표 상품(`catalog_products`) + 오퍼(`products` 또는 `offers`)** 분리 마이그레이션을 명시한다.

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

목록 응답(집계): `offer_count`, `min_price_credits` — 하위 오퍼에서 계산, DB 컬럼 필수 아님.

### 변경: `products` (오퍼)

- `catalog_product_id` FK — 어느 대표 상품에 속하는지
- `seller_id` FK NOT NULL
- `option_label` — 용량 등 (예: `500ml × 20`)
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
| GET | `/catalog-products` | **대표 상품** 목록·검색. `q=생수` → 백산수·평창수 등. 각 row에 `min_price_credits` |
| GET | `/catalog-products/{id}` | 대표 상품 + **오퍼 한 줄** 목록 |
| GET | `/products/{id}` | (과도기) 단일 오퍼 상세 — 분리 후 `/offers/{id}` 등으로 정리 |

과도기: 기존 `GET /products`는 Plan 승인 전까지 유지 가능. 제로 서치 DoD는 **`/catalog-products` 기준**.

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
| `/` | **대표 상품** 카탈로그·검색 |
| `/catalog/:id` 또는 `/products/:id` | 상세 — **오퍼 한 줄 비교**, 더보기 |
| `/cart` | 장바구니 (가게별 묶음) |
| `/orders` | 주문 — 줄별 가게·배송 |
| `/seller` | 판매자 대시보드 |
| `/seller/products` | 내 오퍼 |
| `/seller/orders` | 내 주문 줄 |
| `/admin` | 입점 승인 |

화면 목업: [report/mockup/index.html](../report/mockup/index.html)

## DoD

- 「생수」 검색 → **백산수·평창수** 등 브랜드별 카드 (백산수 오퍼 12개여도 카드 1장, **최저가** 표시)
- 상세에서 용량·가격·판매자(공식/입점·배송) **한 줄 비교**
- 입점 신청 → 승인 → 오퍼 등록 → 주문에 `seller_id` 반영
- 공식·입점 혼합 장바구니·결제 (크레딧 스텁 또는 토스 Plan 범위)
- `fulfillment_status` 전이 + 구매자 주문 화면 폴링
- pytest·flutter analyze 통과

## 배포

AWS: Flutter(S3·CloudFront), FastAPI(EC2), RDS(PostgreSQL). 주소 `https://app.anoveli.com/mall/`
