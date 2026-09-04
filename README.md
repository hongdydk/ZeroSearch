# 제로 서치 (Zero Search)

**회사+유형+품목으로 카드가 나오는 마켓플레이스** — 공식 스토어 + 입점, 같은 회사의 그 품목만 1장, 상세 한 줄 비교.

## 이 서비스가 하는 일

- **검색·목록** — 「생수」·「떡갈비」처럼 **종류**로 들어가면 그 안 **회사+품목 카드가 쭈르륵**(백산수, 평창수…). 카드에 **단위당 대표가(중위)** — 최저가·「~」 없음
- **옵션 필터** — 맛·용량 필터로 집계 대상 오퍼 좁히기
- **상세** — 용량·판매자·가격 **한 줄 비교**, 숍 전체는 더보기
- **마켓플레이스** — 공식·입점 판매자, 입점 신청·승인
- **장바구니·주문** — 여러 가게 상품, 주문 줄별 가게·배송 상태
- **관리자** — 입점 승인, 통계

사업 모델은 **자체 마켓플레이스**(공식·입점)로 확정. 제품 방향은 [docs/README.md](docs/README.md).

## 아직 없는 것 / 범위 밖

- 실 PG(토스), 웹훅
- 판매자 정산·수수료
- 멤버십 (레거시 스텁만 존재할 수 있음)

**제품 방향:** [docs/README.md](./docs/README.md)  
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
python -m alembic upgrade head
python seed.py
python -m scripts.import_dummyjson_catalog   # optional — DummyJSON demo catalog (~30 products)
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
| 화면 | Flutter → S3 `mall/` prefix · 호스트 `mall.anoveli.com` |
| API | FastAPI → EC2 **8001** (`/opt/shopping-mall`) |
| DB | PostgreSQL 16 → Docker `mall-postgres` |
| 결제 (목표) | 토스페이먼츠 |

아노벨리(`api.anoveli.com`, S3 루트, `app.anoveli.com`)와 **공존**. 상세: [deploy/README.md](./deploy/README.md)

목표 주소: `https://mall.anoveli.com/` · API: `https://mall-api.anoveli.com`

**자동 배포:** `main` push → GitHub Actions ([deploy/README.md](./deploy/README.md) §5) — EC2 API + S3 Flutter `mall/`

## 시드·개발 계정

| 용도 | 이메일 | 비밀번호 |
|------|--------|----------|
| 관리자 | `admin@mall.local` | `admin-dev-only` |

- 신규 가입 크레딧 보너스: `SIGNUP_CREDIT_BONUS`(기본 100)
- 시드: 관리자 + 레거시 상품 8개 + **생수 데모**(백산수·평창수·제주삼다수, 다중 오퍼)
- DummyJSON 추가 카탈로그: `cd apps/api && python -m scripts.import_dummyjson_catalog` (기본 30개, USD×10→크레딧)

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
├── report/         # 사람용 기획·목업 (gitignore)
├── scripts/        # OpenAPI export, codegen
└── docs/           # 제품 SSOT · phase 스펙
```

Agent·규칙: [AGENTS.md](./AGENTS.md), [.cursor/rules/](./.cursor/rules/)
