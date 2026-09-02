# Phase 1 — 쇼핑몰 골격

**SSOT** — 엔티티·API·Flutter 라우트·DoD. Plan·구현은 이 문서를 따른다.

**제품:** [제로 서치](../report/프로젝트-컨셉.md) — Phase 1은 인증·상품·장바구니·주문 **골격**만 만든다. 대표 상품·오퍼 분리는 Phase 2 이후.

## 목표

Anoveli 인프라(인증·크레딧 지갑·Flutter 셸)를 재사용해 상품·장바구니·주문 골격을 만든다. LLM·소설 도메인은 포함하지 않는다.

## 엔티티

### 유지 (Anoveli 포크)

| 테이블 | 설명 |
|--------|------|
| `users` | 계정 (`episode_language` 등 소설 필드 제거) |
| `credit_wallets` | 사용자별 크레딧 잔액 |
| `credit_transactions` | grant / debit / refund 이력 |

### 신규

| 테이블 | 주요 필드 |
|--------|-----------|
| `products` | title, description, price_credits, stock, category, image_url(스텁) |
| `cart_items` | user_id, product_id, qty |
| `orders` | user_id, status(`pending`\|`paid`\|`cancelled`), total_credits |
| `order_items` | order_id, product_id, qty, unit_price_credits |
| `membership_plans` | slug, name, price_credits, interval(`month`) — **레거시, 제로 서치 범위 밖** |
| `subscriptions` | user_id, plan_id, status, current_period_end — **레거시, 제로 서치 범위 밖** |

## API 라우트

### 공통·인증·관리

| Method | Path | 설명 |
|--------|------|------|
| GET | `/health` | 헬스체크 |
| GET | `/health/ready` | DB 준비 여부 |
| POST | `/auth/register` | 가입 (+ 가입 보너스 크레딧) |
| POST | `/auth/login` | 로그인 |
| GET | `/auth/me` | 내 프로필 |
| PATCH | `/auth/me/preferences` | 프로필·환경 설정 |
| GET | `/me/credits` | 크레딧 잔액 |
| GET | `/admin/stats` | 관리자 통계 |
| GET | `/admin/users` | 사용자 목록 |
| POST | `/admin/users/{user_id}/promote` | 관리자 승격 |
| POST | `/admin/users/{user_id}/credits` | 크레딧 지급 |
| POST | `/admin/db/reset` | DB 리셋 (dev) |

### 상품·장바구니·주문

| Method | Path | 설명 |
|--------|------|------|
| GET | `/products` | 상품 목록 |
| GET | `/products/{id}` | 상품 상세 |
| GET | `/me/cart` | 장바구니 조회 |
| PUT | `/me/cart` | 담기·수량 변경 |
| DELETE | `/me/cart` | 항목 삭제(또는 비우기) |
| POST | `/me/orders` | 체크아웃: debit → `paid` → 장바구니 비움 |
| GET | `/me/orders` | 주문 목록 |
| GET | `/me/orders/{id}` | 주문 상세 |

### 멤버십 (레거시 — 제로 서치 Plan·DoD 제외)

| Method | Path | 설명 |
|--------|------|------|
| GET | `/membership/plans` | 플랜 목록 |
| POST | `/me/membership/subscribe` | 구독(크레딧 차감 스텁) |
| GET | `/me/membership` | 내 구독 상태 |

## Flutter 라우트

| Path | 화면 |
|------|------|
| `/` | 홈 — 상품 카탈로그 |
| `/products/:id` | 상품 상세 (+ 담기) |
| `/cart` | 장바구니 |
| `/orders` | 주문 목록 |
| `/membership` | 멤버십 (레거시) |
| `/settings` | 설정 |
| `/admin` | 관리자 |
| `/login`, `/register` | 인증 (비로그인) |

### 셸 IA

- **앱 탭**: 홈 / 장바구니 / 주문 / MY (멤버십 탭은 레거시)
- **웹 헤더**: 브랜드 · 검색(홈) · 장바구니 · 로그인/크레딧 · ≡(주문·설정·관리자)

## 시드

- 관리자: `admin@mall.local` / `admin-dev-only`
- 상품 약 8개
- 가입 보너스 크레딧으로 주문 동작 확인

## Definition of Done

- [ ] `docker compose up -d` 후 `alembic upgrade head` + `python seed.py` 성공
- [ ] `pytest` — auth, products, cart checkout 통과
- [ ] Flutter `analyze` 통과
- [ ] 카탈로그 → 담기 → 주문 화면 라우트 동작
- [ ] OpenAPI export·Flutter codegen 파이프라인 유지
- [ ] LLM·소설·Ollama 코드·설정 없음

## 후속 Phase (참고)

- **Phase 2** — 마켓플레이스·제로 서치 목록(대표 상품)
- **Phase 3** — 토스 PG·웹훅
