# EC2 + S3/CloudFront 배포 (아노벨리와 공존)

아노벨리(`/opt/anoveli`, `api.anoveli.com:8000`, `app.anoveli.com`)는 **건드리지 않고**, 제로 서치(쇼핑몰)만 **추가**한다.

**앱 URL:** `https://mall.anoveli.com/` (아노벨리 `app.anoveli.com` 과 호스트 분리)  
**API URL (브라우저):** `https://mall.anoveli.com/api` → CloudFront → `mall-api.anoveli.com` (:8001)

**API URL (원본/Tunnel):** `https://mall-api.anoveli.com`

## 현재 아노벨리 서버 (참고)

| 구분 | 아노벨리 | 쇼핑몰 (이 repo) |
|------|--------|------------------|
| EC2 경로 | `/opt/anoveli` | `/opt/shopping-mall` |
| API 포트 | **8000** | **8001** |
| Tunnel | `api.anoveli.com` → 8000 | `mall-api.anoveli.com` → 8001 (추가) |
| 웹 호스트 | `app.anoveli.com` | **`mall.anoveli.com`** |
| 웹 원본 | (아노벨리 쪽) | **S3 + CloudFront** |
| DB | `anoveli-postgres` / chatbot | `mall-postgres` / mall |

---

## 1. EC2 — API

```bash
sudo mkdir -p /opt/shopping-mall
sudo chown ubuntu:ubuntu /opt/shopping-mall
cd /opt/shopping-mall
git clone <ShoppingMall-repo-url> .

cp .env.prod.example .env.prod
# POSTGRES_PASSWORD, JWT_SECRET, ADMIN_PASSWORD, CORS_ORIGINS,
# TOSS_CLIENT_KEY, TOSS_SECRET_KEY 등 채우기
# CORS_ORIGINS=https://mall.anoveli.com

docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build
docker ps   # mall-api, mall-postgres 확인
curl -s http://127.0.0.1:8001/health
```

갱신:

```bash
cd /opt/shopping-mall
git pull
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build
```

이미 배포된 서버: `.env.prod`의 `CORS_ORIGINS`를 `https://mall.anoveli.com`으로 바꾼 뒤 API 재시작.

### 1.1 토스 카드 테스트 결제

토스 개발자센터의 같은 테스트 키 세트에서 클라이언트 키와 시크릿 키를 복사해 EC2의 `.env.prod`에만 넣는다.

```dotenv
TOSS_CLIENT_KEY=test_gck_...
TOSS_SECRET_KEY=test_gsk_...
TOSS_API_TIMEOUT=10
```

시크릿 키는 Flutter 빌드·GitHub 변수·로그에 넣지 않는다. 토스 개발자센터 웹훅에는 아래 URL과 `PAYMENT_STATUS_CHANGED` 이벤트를 등록한다.

```text
https://mall.anoveli.com/api/payments/toss/webhook
```

CloudFront `/api*` behavior가 POST 요청을 `mall-api` origin으로 전달해야 한다. 테스트 결제 성공·실패 후 주문, 재고, 장바구니가 함께 맞는지 확인한 뒤에만 라이브 키 전환을 별도 진행한다.

---

## 2. Cloudflare Tunnel (API)

`~/.cloudflared/config.yml` — **ingress 맨 위**에 추가:

```yaml
ingress:
  - hostname: mall-api.anoveli.com
    service: http://127.0.0.1:8001
  - hostname: api.anoveli.com
    service: http://127.0.0.1:8000
  - service: http_status:404
```

Cloudflare DNS에 `mall-api` CNAME → tunnel.  
적용: `sudo systemctl restart cloudflared` (또는 사용 중인 재시작 방법).

---

## 3. S3 + CloudFront — Flutter 웹 (`mall.anoveli.com`)

브라우저에는 **`https://mall.anoveli.com/`** (`base-href=/`). CI가 `main` push 시 S3 버킷 루트에 올리고 CloudFront 캐시를 무효화한다.

### 3.1 로컬 빌드 (수동 업로드할 때만)

```bash
cd apps/flutter
flutter build web --base-href=/ \
  --pwa-strategy=none \
  --dart-define=API_BASE_URL=https://mall.anoveli.com/api
```

S3에는 `apps/flutter/build/web/` **내용**을 버킷 루트에 올린다 (`web/` 폴더 중첩 금지).

CI는 `index.html`·`flutter_bootstrap.js`에 `Cache-Control: no-cache`를 지정하고 나머지 산출물을 동기화한다.
자동 배포는 §5 GitHub Actions.

### 3.2 CloudFront 1회 설정

1. 전용 S3 버킷(예: `mall-web-poc`)은 퍼블릭 액세스를 차단하고 CloudFront OAC만 읽게 한다.
2. ACM 인증서는 `us-east-1`에 `mall.anoveli.com`으로 만들고 Cloudflare DNS에서 검증한다.
3. CloudFront origin:
   - 기본 origin: S3 + OAC
   - API origin: `mall-api.anoveli.com`, HTTPS only
4. cache behavior `/api*`는 API origin, 캐시 비활성, 모든 HTTP method 허용, `Host`를 제외한 요청 헤더·쿠키·쿼리를 전달한다. Viewer request에 [`cloudfront/strip-api-prefix.js`](./cloudfront/strip-api-prefix.js)를 연결한다.
5. 기본 S3 behavior의 Viewer request에 [`cloudfront/spa-route-rewrite.js`](./cloudfront/spa-route-rewrite.js)를 연결한다. 확장자 없는 `/admin`·`/seller`만 `/index.html`로 바꾸므로 없는 API·JS를 HTML로 오인하지 않는다.
6. Alternate domain에 `mall.anoveli.com`과 ACM 인증서를 지정한다.

CloudFront의 전역 403/404 custom error response를 `/index.html`로 매핑하지 않는다. 그 방식은 API 404까지 HTML 200으로 바꿀 수 있다.

### 3.3 DNS 전환

1. CloudFront 배포 도메인에서 `/`, `/admin`, `/api/health`를 먼저 확인한다.
2. Cloudflare DNS `mall` CNAME을 CloudFront 배포 도메인으로 바꾸고 **DNS only(회색 구름)** 로 둔다.
3. 정상 확인 후에만 기존 Pages 프로젝트에서 `mall.anoveli.com` 커스텀 도메인을 제거한다.
4. `mall-api.anoveli.com` DNS·Tunnel은 CloudFront API origin이므로 유지한다.

접속: `https://mall.anoveli.com/` · 관리자 `…/admin` · 판매자 `…/seller`

---

## 4. 체크리스트

- [ ] `anoveli-api`(8000) / `api.anoveli.com` 정상
- [ ] `mall-api`(8001) / `mall-api.anoveli.com/health` 정상 (프록시 백엔드)
- [ ] S3 + CloudFront + `mall.anoveli.com` alternate domain
- [ ] `https://mall.anoveli.com/api/health` 정상 (same-origin)
- [ ] Flutter `API_BASE_URL=https://mall.anoveli.com/api`, **`base-href=/`**
- [ ] EC2 `.env.prod` `CORS_ORIGINS=https://mall.anoveli.com` (직접 mall-api 호출·프리뷰용)
- [ ] `https://mall.anoveli.com/admin` · `/seller` 새로고침 시 쇼핑몰 유지
- [ ] `.env.prod` git 미커밋

---

## 5. GitHub Actions 자동 배포

`main` 브랜치에 **push**하면 [.github/workflows/deploy.yml](../.github/workflows/deploy.yml) 이 실행된다.

| Job | 내용 |
|-----|------|
| `test-api` | pytest |
| `deploy-api` | EC2 SSH → `deploy/ec2-deploy.sh` (git pull + docker rebuild + **aihub CSV import**) |
| `build-flutter` | Flutter web 빌드 → artifact |
| `deploy-web` | artifact → S3 sync → CloudFront invalidation |

업로드만 실패하면 Actions에서 **Re-run failed jobs** — `deploy-web`만 다시 돈다.

수동 실행: GitHub → Actions → **Deploy** → **Run workflow**

### 카탈로그 CSV (배포 시 자동)

대표 상품 SSOT는 repo의 [`data/aihub-catalog.csv`](../data/aihub-catalog.csv).

1. Validation 라벨에서 갱신: `python scripts/extract_aihub_catalog.py`
2. (또는) 엑셀/CSV에 품목 한 줄 추가
3. `main` push → EC2 `ec2-deploy.sh`가 health OK 후  
   CSV `sha256`이 `$DEPLOY_DIR/.cache/aihub-catalog.sha256`과 같으면 **skip**,  
   다르거나 캐시 없으면 `import_aihub_catalog` upsert 후 해시 기록.  
   강제: `FORCE_CATALOG_IMPORT=1 bash deploy/ec2-deploy.sh`

관리자 UI CSV 업로드는 **비상용**. 일상 반영은 위 경로.

수동 import (EC2):

```bash
cd /opt/shopping-mall
docker compose -f docker-compose.prod.yml --env-file .env.prod run --rm \
  -v /opt/shopping-mall/data/aihub-catalog.csv:/import/aihub-catalog.csv:ro \
  api python -m scripts.import_aihub_catalog /import/aihub-catalog.csv
```

### 최초 1회 (서버)

EC2에 repo clone·`.env.prod` 는 기존 §1과 동일. **이 workflow 파일이 repo에 있어야** 이후 push 배포가 동작한다.

### Repository secrets (Settings → Secrets)

| Secret | 용도 |
|--------|------|
| `EC2_HOST` | EC2 호스트 (IP 또는 DNS) |
| `EC2_USER` | SSH 사용자 (예: `ubuntu`) |
| `EC2_SSH_KEY` | EC2 API 배포용 SSH private key |

웹 배포는 GitHub OIDC를 사용하므로 장기 AWS access key를 저장하지 않는다.

### Repository variables (Settings → Variables)

| Variable | 예시 | 용도 |
|----------|------|------|
| `AWS_DEPLOY_ROLE_ARN` | `arn:aws:iam::…:role/github-…` | GitHub OIDC 배포 역할 |
| `S3_BUCKET` | `mall-web-poc` | Flutter 웹 버킷 |
| `CLOUDFRONT_DISTRIBUTION_ID` | `E…` | 배포 후 캐시 무효화 |
| `MALL_API_BASE_URL` | `https://mall.anoveli.com/api` | Flutter 빌드 `--dart-define` (미설정·구 mall-api URL이면 스크립트가 same-origin으로 맞춤) |

OIDC 역할에는 해당 버킷의 `ListBucket`, `GetObject`, `PutObject`, `DeleteObject`와 해당 배포의 `cloudfront:CreateInvalidation`만 허용한다.

DummyJSON 등 **데모 시드**는 자동 배포에 포함하지 않는다. 필요 시 EC2에서:

```bash
cd /opt/shopping-mall
docker compose -f docker-compose.prod.yml --env-file .env.prod exec -T api \
  python -m scripts.import_dummyjson_catalog
```

AI-Hub 카탈로그는 위 §5 「카탈로그 CSV」대로 배포 시 반영(변경 없으면 skip)이다.
---

## 하지 말 것

- `/opt/anoveli` 덮어쓰기 또는 compose 중지
- Tunnel에서 `api.anoveli.com`을 8001로 변경
- 목표 URL을 다시 `app.anoveli.com/mall/` 로 되돌리기 (호스트 겹침·SPA 깨짐)
- CloudFront 확인 전에 Pages 커스텀 도메인 제거
- `mall-api.anoveli.com` Tunnel 삭제 또는 EC2 8001 직접 공개
