# 현재 데이터 모델 ERD

조사 기준: SQLAlchemy 모델 (`apps/api/app/models/`) + Alembic `001`–`010`. Postgres. 코드에 없는 엔티티는 그리지 않았다.

저장소: FastAPI + PostgreSQL. Flutter는 JWT·포털 이탈 시각만 기기에 두고, 도메인 테이블은 서버 DB가 SSOT다.

---

## Mermaid

```mermaid
erDiagram
    users ||--o| sellers : "1 user 1 shop"
    users ||--o| credit_wallets : "1 wallet"
    users ||--o{ shipping_addresses : "saved addresses"
    users ||--o{ cart_items : "cart"
    users ||--o{ orders : "orders"
    users ||--o{ subscriptions : "legacy membership"
    users ||--o{ payment_intents : "toss intents"
    credit_wallets ||--o{ credit_transactions : "ledger"
    membership_plans ||--o{ subscriptions : "plan"
    catalog_products ||--o{ products : "offers"
    catalog_products ||--o{ catalog_product_aliases : "merged ids"
    sellers ||--o{ products : "lists offers"
    sellers ||--o{ order_items : "fulfills line"
    products ||--o{ cart_items : "in cart"
    products ||--o{ order_items : "ordered"
    orders ||--o{ order_items : "lines"
    orders |o--o| payment_intents : "optional 1:1"

    users {
        uuid id PK
        string email UK
        string password_hash
        string display_name
        bool is_admin
        timestamptz created_at
    }

    sellers {
        uuid id PK
        uuid user_id FK_UK
        string shop_name
        string slug UK
        string status
        string seller_type
        timestamptz created_at
        timestamptz updated_at
    }

    catalog_products {
        uuid id PK
        string title
        string manufacturer
        string category
        string category_major
        string category_mid
        text description
        string image_url
        jsonb search_keywords
        jsonb volume_options
        jsonb reference_variants
        string price_unit
        timestamptz created_at
        timestamptz updated_at
    }

    catalog_product_aliases {
        uuid alias_id PK
        uuid canonical_id FK
        string original_title
        timestamptz created_at
    }

    products {
        uuid id PK
        uuid seller_id FK
        uuid catalog_product_id FK
        string title
        string option_label
        int volume_ml
        string flavor
        text description
        int price_credits
        int stock
        string category
        string image_url
        string status
        timestamptz created_at
        timestamptz updated_at
    }

    cart_items {
        uuid id PK
        uuid user_id FK
        uuid product_id FK
        int qty
        timestamptz created_at
        timestamptz updated_at
    }

    shipping_addresses {
        uuid id PK
        uuid user_id FK
        string recipient_name
        string phone
        string zonecode
        string address
        string detail_address
        bool is_default
        timestamptz created_at
        timestamptz updated_at
    }

    orders {
        uuid id PK
        uuid user_id FK
        string status
        int total_credits
        string idempotency_key
        jsonb shipping_snapshot
        timestamptz created_at
        timestamptz updated_at
    }

    order_items {
        uuid id PK
        uuid order_id FK
        uuid product_id FK
        uuid seller_id FK
        int qty
        int unit_price_credits
        string product_title
        string fulfillment_status
    }

    payment_intents {
        uuid id PK
        uuid user_id FK
        uuid order_id FK_UK
        string provider_order_id UK
        string idempotency_key
        string payment_key UK
        int amount
        string order_name
        string status
        jsonb cart_snapshot
        jsonb shipping_snapshot
        string failure_code
        text failure_message
        timestamptz requested_at
        timestamptz approved_at
        timestamptz updated_at
    }

    credit_wallets {
        uuid id PK
        uuid user_id FK_UK
        int balance
        timestamptz created_at
        timestamptz updated_at
    }

    credit_transactions {
        uuid id PK
        uuid wallet_id FK
        string type
        int amount
        int balance_after
        string ref_type
        uuid ref_id
        string note
        timestamptz created_at
    }

    membership_plans {
        uuid id PK
        string slug UK
        string name
        int price_credits
        string interval
        timestamptz created_at
    }

    subscriptions {
        uuid id PK
        uuid user_id FK
        uuid plan_id FK
        string status
        timestamptz current_period_end
        timestamptz created_at
        timestamptz updated_at
    }
```

복합 UNIQUE (다이어그램 UK와 별도):

- `catalog_products`: `(manufacturer, category, title)` → `uq_catalog_products_maker_category_title`
- `cart_items`: `(user_id, product_id)` → `uq_cart_items_user_product`
- `orders`: `(user_id, idempotency_key)` → `uq_orders_user_idempotency_key`
- `payment_intents`: `(user_id, idempotency_key)` → `uq_payment_intents_user_key`

CHECK: `products.stock >= 0` (`ck_products_stock_nonnegative`).

FK `ON DELETE`: `catalog_product_aliases.canonical_id`만 `CASCADE`. 나머지는 미지정(Postgres 기본 `NO ACTION`).

---

## 엔티티 범례 (발표용)

**users**  
로그인 계정이다. 이메일·비밀번호 해시·표시 이름·관리자 여부만 가진다. 역할 테이블은 없고 `is_admin` 플래그로 관리자를 구분한다.

**sellers**  
한 사용자당 가게 하나(`user_id` UNIQUE). `platform`(공식몰) 또는 `merchant`(입점)이고, 승인 전 `pending` → 운영 중 `active` → `suspended`다.

**catalog_products**  
제로 서치 목록 카드다. identity는 **회사(manufacturer) + 종류(category) + 품목(title)** 이고, 이 세 값 조합이 UNIQUE다. 용량·맛 변형은 자식 테이블이 아니라 JSON(`volume_options`, `reference_variants`)으로 붙는다.

**catalog_product_aliases**  
카탈로그를 합친 뒤, 사라진 옛 UUID를 살아 있는 대표 상품으로 돌려주는 호환 표다. `alias_id`는 옛 카드 id이지, 현재 `catalog_products` 행을 가리키는 FK가 아니다.

**products**  
판매자가 그 대표 상품에 붙인 **오퍼(용량·맛·가격·재고·가게)** 다. 구매·장바구니 단위는 이 행이다. 목록 카드가 아니다.

**cart_items**  
구매자 장바구니 한 줄이다. 같은 사용자·같은 오퍼는 한 행만 둔다.

**shipping_addresses**  
구매자가 저장한 배송지다. 주문 FK는 없고, 결제·주문 시점에는 JSON 스냅샷으로만 복사한다. 기본지(`is_default`) UNIQUE는 DB에 없다(앱이 한 건만 켜 둔다). 사용자당 최대 10개는 앱 제한이다.

**orders**  
결제 확정 주문 헤더다. 금액은 `total_credits`(현재 KRW 정수로 사용). `shipping_snapshot`은 결제 시점 주소 복사본이다.

**order_items**  
주문 한 줄이다. 가게·배송 주체용 `seller_id`, 당시 제목·단가를 복사해 두고, 배송 상태(`fulfillment_status`)는 줄 단위로 간다.

**payment_intents**  
토스 결제 요청이다. 장바구니·배송지를 JSON으로 고정한 뒤 승인되면 `orders` 한 건과 1:1로 묶인다(`order_id` UNIQUE, 승인 전엔 NULL). 카드번호·시크릿은 저장하지 않는다.

**credit_wallets**  
사용자 원(크레딧) 잔액 한 줄이다. 가입 시 보너스로 만들어질 수 있다.

**credit_transactions**  
지갑 원장이다. `type`은 grant / debit / refund, 금액은 양수다. `ref_id`는 주문·구독 등을 가리키는 **다형 참조**라 FK가 없다.

**membership_plans**  
멤버십 요금제(seed: free / basic / pro). 제품 범위 밖 레거시이지만 테이블은 남아 있다.

**subscriptions**  
어떤 사용자가 어떤 플랜을 쓰는지다. 활성 구독 1건 UNIQUE는 DB에 없고, 서비스가 기존 active를 cancelled로 바꾼다.

---

## 관계 요약

| 관계 | 카디널리티 | 비고 |
|------|------------|------|
| users → sellers | 1 : 0..1 | `sellers.user_id` UNIQUE |
| users → credit_wallets | 1 : 0..1 | `credit_wallets.user_id` UNIQUE |
| users → shipping_addresses / cart_items / orders / payment_intents / subscriptions | 1 : N | |
| catalog_products → products | 1 : N | 카드 하나에 오퍼 여러 줄 |
| catalog_products → catalog_product_aliases | 1 : N | 병합된 옛 id |
| sellers → products | 1 : N | |
| sellers → order_items | 1 : N | 체크아웃 시 복사 |
| products → cart_items / order_items | 1 : N | |
| orders → order_items | 1 : N | cascade delete-orphan (ORM) |
| orders ↔ payment_intents | 0..1 : 0..1 | `payment_intents.order_id` UNIQUE nullable |
| credit_wallets → credit_transactions | 1 : N | |
| membership_plans → subscriptions | 1 : N | |

개념상 N:M (별도 교차 테이블 없이 위 조인 엔티티로 구현):

- 대표 상품 ↔ 판매자 = `products`
- 사용자 ↔ 오퍼(장바구니) = `cart_items`
- 사용자 ↔ 멤버십 플랜 = `subscriptions`

---

## JSON 스냅샷 (테이블 아님)

**catalog_products.volume_options**  
`string[]` — 예: `["500ml", "2L"]`.

**catalog_products.reference_variants**  
`[{ originalTitle, flavors[], volumes[] }]` — AI-Hub 원본 맛·용량 참고. 구매 불가.

**catalog_products.search_keywords**  
`string[] | null` — 검색 보조.

**payment_intents.cart_snapshot**  
`[{ productId, sellerId, title, qty, unitPrice }]` — prepare 시점 장바구니 고정.

**orders.shipping_snapshot / payment_intents.shipping_snapshot**  
`{ recipientName, phone, zonecode, address, detailAddress }` — `shipping_addresses` 복사. 주소 행을 가리키지 않는다.

---

## 앱에서 쓰는 상태 값 (DB CHECK 없음)

컬럼은 모두 `String`. 아래는 Pydantic·서비스 관례다.

- `sellers.status`: `pending` \| `active` \| `suspended`
- `sellers.seller_type`: `platform` \| `merchant`
- `products.status`: `draft` \| `published` \| `archived`
- `orders.status`: `pending` \| `paid` \| `cancelled`
- `order_items.fulfillment_status`: `paid` → `preparing` → `shipped` → `delivered`
- `payment_intents.status`: `ready` \| `confirming` \| `paid` \| `failed` \| `cancelled` \| `expired`
- `subscriptions.status`: `active` \| `cancelled` \| `expired`
- `credit_transactions.type`: `grant` \| `debit` \| `refund`
- `credit_transactions.ref_type` 예: `signup_bonus`, `admin_grant`, `order`, `subscription`

---

## 저장하지 않는 것 / 모호함

**테이블이 아닌 것**

- 카탈로그 import job: 프로세스 메모리 dict (`catalog_import_jobs.py`). 재시작 시 사라진다.
- JWT 세션·refresh token 테이블 없음. Flutter는 기기 저장소에 access token만 둔다.
- 종류·제조사 lookup 테이블 없음. `category` / `manufacturer`는 문자열.
- `packages/shared`의 Bot·캐릭터 타입은 레거시 TS 계약. 이 Postgres 스키마와 무관.
- 운영 CSV `data/aihub-catalog.csv`는 import 원본이지 DB 테이블이 아니다.

**스키마·코드 어긋남**

- `catalog_products.price_unit` 컬럼 기본값 `ml`, seed/import는 `ml`·`each`도 쓴다. 목록 API의 `priceUnit`(`ml` \| `credits`)은 **오퍼에서 다시 계산**하며 이 컬럼을 그대로 돌려주지 않는다.
- `products.category`는 대표 상품 종류와 별도 문자열로 중복 저장된다. FK/동기 제약은 없다.
- 같은 판매자가 같은 대표 상품에 오퍼를 여러 개 넣을 수 있다. `(seller_id, catalog_product_id, option)` UNIQUE 없음.
- `credit_transactions.ref_id`는 FK가 아니라 다형 UUID. `refund` 타입 함수는 있으나 구매자 취소/환불 흐름은 아직 쓰지 않는다.
- 플랫폼 판매자는 시드/서비스상 한 곳만 두지만, `seller_type` UNIQUE는 없다.
- `orders`/`payment_intents`의 `(user_id, idempotency_key)` UNIQUE는 Postgres에서 NULL 키가 서로 다른 값으로 취급된다(키 없는 행이 여러 개 가능).
- `PaymentIntent`는 FK만 있고 SQLAlchemy `relationship()`은 없다.
- 멤버십 테이블은 살아 있으나 제품 SSOT상 범위 밖이다.
- 가격 컬럼 이름 `*_credits`는 과도기 KRW 정수와 같다(Phase 4).

조사 경로: `apps/api/app/models/*.py`, `apps/api/alembic/versions/001`–`010`.
