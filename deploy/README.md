# EC2 + Cloudflare Pages 배포 (아노벨리와 공존)

아노벨리(`/opt/anoveli`, `api.anoveli.com:8000`, `app.anoveli.com`)는 **건드리지 않고**, 제로 서치(쇼핑몰)만 **추가**한다.

**앱 URL:** `https://mall.anoveli.com/` (아노벨리 `app.anoveli.com` 과 호스트 분리)  
**API URL (브라우저):** `https://mall.anoveli.com/api` → Pages Functions → `mall-api.anoveli.com` (:8001)  
**API URL (원본/Tunnel):** `https://mall-api.anoveli.com`

## 현재 아노벨리 서버 (참고)

| 구분 | 아노벨리 | 쇼핑몰 (이 repo) |
|------|--------|------------------|
| EC2 경로 | `/opt/anoveli` | `/opt/shopping-mall` |
| API 포트 | **8000** | **8001** |
| Tunnel | `api.anoveli.com` → 8000 | `mall-api.anoveli.com` → 8001 (추가) |
| 웹 호스트 | `app.anoveli.com` | **`mall.anoveli.com`** |
| 웹 원본 | (아노벨리 쪽) | **Cloudflare Pages** (S3 sync 안 함) |
| DB | `anoveli-postgres` / chatbot | `mall-postgres` / mall |

---

## 1. EC2 — API

```bash
sudo mkdir -p /opt/shopping-mall
sudo chown ubuntu:ubuntu /opt/shopping-mall
cd /opt/shopping-mall
git clone <ShoppingMall-repo-url> .

cp .env.prod.example .env.prod
# POSTGRES_PASSWORD, JWT_SECRET, ADMIN_PASSWORD, CORS_ORIGINS 등 채우기
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

## 3. Cloudflare Pages — Flutter 웹 (`mall.anoveli.com`)

브라우저에는 **`https://mall.anoveli.com/`** (`base-href=/`). CI가 `main` push 시 Pages에 올린다.

### 3.1 로컬 빌드 (수동 업로드할 때만)

```bash
cd apps/flutter
flutter build web --base-href=/ \
  --pwa-strategy=none \
  --dart-define=API_BASE_URL=https://mall.anoveli.com/api
```

Pages에는 `apps/flutter/build/web/` **내용**을 루트에 올린다 (`web/` 폴더 중첩 금지).  
배포 전 `deploy/cloudflare-pages/functions`·`_routes.json`·`_headers`를 산출물에 붙여 **`/api/*` → mall-api** 프록시와 `index.html`/`flutter_bootstrap.js` no-cache를 켠다 (CI가 자동).  
자동 배포는 §5 GitHub Actions.

### 3.2 커스텀 도메인

Pages 프로젝트에 `mall.anoveli.com` 커스텀 도메인을 붙인다.  
SPA 폴백은 Pages 기본 동작(루트 `404.html` 없음)을 쓴다.  
`/* → /index.html 200` `_redirects`는 `main.dart.js` 등 정적 자산까지 rewrite되어 500/MIME 오류를 낼 수 있어 쓰지 않는다.

접속: `https://mall.anoveli.com/` · 관리자 `…/admin` · 판매자 `…/seller`

---

## 4. 체크리스트

- [ ] `anoveli-api`(8000) / `api.anoveli.com` 정상
- [ ] `mall-api`(8001) / `mall-api.anoveli.com/health` 정상 (프록시 백엔드)
- [ ] Cloudflare Pages + `mall.anoveli.com` 커스텀 도메인
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
| `deploy-pages` | artifact → Cloudflare Pages (`npx wrangler`) |

업로드만 실패하면 Actions에서 **Re-run failed jobs** — `deploy-pages`만 다시 돈다.

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
| `EC2_SSH_KEY` | SSH private key 전체 |
| `CLOUDFLARE_API_TOKEN` | Pages 업로드. 권한: **Account → Cloudflare Pages → Edit** |

토큰: Cloudflare → My Profile → API Tokens → Create.  
웹 원본은 **Cloudflare Pages**다. S3 sync는 쓰지 않는다.

### Repository variables (Settings → Variables)

| Variable | 예시 | 용도 |
|----------|------|------|
| `CLOUDFLARE_ACCOUNT_ID` | 대시보드 오른쪽 Account ID | wrangler 계정 |
| `CLOUDFLARE_PAGES_PROJECT` | Pages 프로젝트 이름 | `pages deploy --project-name` |
| `MALL_API_BASE_URL` | `https://mall.anoveli.com/api` | Flutter 빌드 `--dart-define` (미설정·구 mall-api URL이면 스크립트가 same-origin으로 맞춤) |

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
