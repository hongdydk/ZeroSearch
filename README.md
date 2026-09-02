# 제로 서치 (Zero Search)

**검색·목록 중복을 줄이는 마켓플레이스** — 공식 스토어 + 입점, 대표 상품 1장, 상세 한 줄 비교.

## 이 서비스가 하는 일

- **검색·목록** — 카테고리 검색(예: 「생수」) → **브랜드별** 대표 카드(백산수, 평창수…), 카드에 **최저가**
- **상세** — 용량·판매자·가격 **한 줄 비교**, 숍 전체는 더보기
- **마켓플레이스** — 공식·입점 판매자, 입점 신청·승인
- **장바구니·주문** — 여러 가게 상품, 주문 줄별 가게·배송 상태
- **관리자** — 입점 승인, 통계

## 아직 없는 것 / 범위 밖

- 대표 상품·오퍼 분리 (목표 모델 — [docs/phase2-spec.md](./docs/phase2-spec.md) 참고)
- 실 PG(토스), 웹훅
- 판매자 정산·수수료
- 멤버십 (레거시 스텁만 존재할 수 있음)

**제품 방향:** [report/프로젝트-컨셉.md](./report/프로젝트-컨셉.md)  
**활성 스펙:** [docs/phase2-spec.md](./docs/phase2-spec.md)

---

## 사전 요구

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [Node.js](https://nodejs.org/) 20+
- [pnpm](https://pnpm.io/) 9+
- Python 3.11+
- [Flutter](https://flutter.dev/)

## 로컬 실행

### 1. 인프라

```bash
docker compose up -d
```

| 서비스 | 컨테이너 | 호스트 포트 |
|--------|----------|-------------|
| PostgreSQL 16 | `mall-postgres` | **5434** |
| Redis 7 | `mall-redis` | **6380** |

### 2. API

```bash
cd apps/api
cp .env.example .env   # 최초 1회
alembic upgrade head
python seed.py
cd ../..
pnpm install           # 최초 1회
pnpm dev:api           # http://localhost:8001
```

OpenAPI: `http://localhost:8001/docs`

### 3. Flutter

```bash
pnpm dev:flutter       # http://localhost:8080
```

`API_BASE_URL` 기본값: `http://localhost:8001`

## 배포 (AWS)

| 구분 | 구성 |
|------|------|
| 화면 | Flutter → S3 `mall/` prefix (+ CloudFront `/mall/*`) |
| API | FastAPI → EC2 **8001** (`/opt/shopping-mall`) |
| DB | PostgreSQL 16 → Docker `mall-postgres` |
| 결제 (목표) | 토스페이먼츠 |

아노벨리(`api.anoveli.com`, S3 루트)와 **공존**. 상세: [deploy/README.md](./deploy/README.md)

목표 주소: `https://app.anoveli.com/mall/` · API: `https://mall-api.anoveli.com`

## 시드·개발 계정

| 용도 | 이메일 | 비밀번호 |
|------|--------|----------|
| 관리자 | `admin@mall.local` | `admin-dev-only` |

- 신규 가입 크레딧 보너스: `SIGNUP_CREDIT_BONUS`(기본 100)
- 시드: 관리자 + 상품 약 8개 (시연용 생수류·대표 상품 데이터는 추후 확장)

## 개발 명령 (루트)

| 명령 | 설명 |
|------|------|
| `pnpm dev:api` | FastAPI (8001) |
| `pnpm dev:flutter` | Flutter (8080) |
| `pnpm codegen:openapi` | OpenAPI JSON export |
| `pnpm codegen:flutter` | OpenAPI → Flutter generated |

## 프로젝트 구조

```
ShoppingMall/
├── apps/api/       # FastAPI
├── apps/flutter/   # Flutter 클라이언트
├── report/         # 컨셉·기획서·목업
├── scripts/        # OpenAPI export, codegen
└── docs/           # phase 스펙
```

Agent·규칙: [AGENTS.md](./AGENTS.md), [.cursor/rules/](./.cursor/rules/)
