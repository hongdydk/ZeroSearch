# EC2 + S3 배포 (아노벨리와 공존)

아노벨리(`/opt/anoveli`, `api.anoveli.com:8000`, S3 버킷 루트)는 **건드리지 않고**, 제로 서치(쇼핑몰)만 **추가**한다.

## 현재 아노벨리 서버 (참고)

| 구분 | 아노벨리 | 쇼핑몰 (이 repo) |
|------|--------|------------------|
| EC2 경로 | `/opt/anoveli` | `/opt/shopping-mall` |
| API 포트 | **8000** | **8001** |
| Tunnel | `api.anoveli.com` → 8000 | `mall-api.anoveli.com` → 8001 (추가) |
| S3 | `anoveli-web-poc/` 루트 | `anoveli-web-poc/mall/` |
| DB | `anoveli-postgres` / chatbot | `mall-postgres` / mall |

---

## 1. EC2 — API

```bash
sudo mkdir -p /opt/shopping-mall
sudo chown ubuntu:ubuntu /opt/shopping-mall
cd /opt/shopping-mall
git clone <ShoppingMall-repo-url> .

cp .env.prod.example .env.prod
# POSTGRES_PASSWORD, JWT_SECRET, ADMIN_PASSWORD 등 편집

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

---

## 2. Cloudflare Tunnel

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

## 3. S3 — Flutter 웹

로컬:

```bash
cd apps/flutter
flutter build web --base-href=/mall/ \
  --pwa-strategy=none \
  --dart-define=API_BASE_URL=https://mall-api.anoveli.com
```

`--pwa-strategy=none` — Service Worker 미생성. **배포 후 일반 창에서도 바로 반영** (PoC·수동 S3 업로드에 권장).

S3 콘솔 `anoveli-web-poc` → **`mall/`** 에 `build/web/` **내용 전부** 업로드 (`index.html`, `main.dart.js`, `assets/`, `canvaskit/` …).  
**`mall/web/` 중첩 금지.** 버킷 **루트**는 건드리지 않음.

### 업로드했는데 화면이 안 바뀔 때 (시크릿만 될 때)

| 원인 | 설명 |
|------|------|
| **Flutter Service Worker** | 예전 빌드의 `main.dart.js`를 브라우저가 계속 씀. 시크릿은 SW 없음 → 새 파일 |
| **일부 파일만 업로드** | `index.html`만 새로고침되고 `main.dart.js`는 구버전 |
| **Cloudflare 캐시** | `main.dart.js`에 `cf-cache-status: HIT` — CDN에 옛 JS |

**해결 (순서):**

1. 빌드에 **`--pwa-strategy=none`** (위 명령). 기존 `flutter_service_worker.js`는 S3 `mall/`에서 **삭제**해도 됨.
2. S3 **`mall/` 전체**를 한 번에 덮어쓰기 — 특히 **`main.dart.js`** 수정 시각이 `index.html`과 같아야 함.
3. Cloudflare → **Caching → Purge** → `app.anoveli.com/mall/*`
4. 이미 SW가 깔린 브라우저: F12 → Application → Service Workers → **Unregister** → Clear site data → 새로고침.

확인:

```bash
curl -sI https://app.anoveli.com/mall/main.dart.js | grep last-modified
```

CloudFront 사용 시 `/mall/*` → S3 `mall/` 경로 behavior 추가.

접속: `https://app.anoveli.com/mall/`

---

## 4. 체크리스트

- [ ] `anoveli-api`(8000) / `api.anoveli.com` 정상
- [ ] `mall-api`(8001) / `mall-api.anoveli.com/health` 정상
- [ ] S3 루트 아노벨리 파일 유지, `mall/`만 갱신
- [ ] Flutter `API_BASE_URL` = mall API 도메인
- [ ] `.env.prod` git 미커밋

---

## 5. GitHub Actions 자동 배포

`main` 브랜치에 **push**하면 [.github/workflows/deploy.yml](../.github/workflows/deploy.yml) 이 실행된다.

| Job | 내용 |
|-----|------|
| `test-api` | pytest |
| `deploy-api` | EC2 SSH → `deploy/ec2-deploy.sh` (git pull + docker rebuild) |
| `deploy-flutter` | Flutter web 빌드 → S3 `mall/` sync |

수동 실행: GitHub → Actions → **Deploy** → **Run workflow**

### 최초 1회 (서버)

EC2에 repo clone·`.env.prod` 는 기존 §1과 동일. **이 workflow 파일이 repo에 있어야** 이후 push 배포가 동작한다.

### Repository secrets (Settings → Secrets)

| Secret | 용도 |
|--------|------|
| `EC2_HOST` | EC2 호스트 (IP 또는 DNS) |
| `EC2_USER` | SSH 사용자 (예: `ubuntu`) |
| `EC2_SSH_KEY` | SSH private key 전체 |
| `CLOUDFLARE_API_TOKEN` | (선택) 배포 후 캐시 purge |

Access Key는 **사용하지 않음** — 아노벨리와 동일하게 IAM OIDC + Role ARN(Variable).

### Repository variables (Settings → Variables)

| Variable | 예시 | 용도 |
|----------|------|------|
| `AWS_DEPLOY_ROLE_ARN` | `arn:aws:iam::…:role/github-anoveli-deploy` | S3 업로드용 AssumeRole (OIDC) |
| `S3_BUCKET` | `anoveli-web-poc` | Flutter web sync 대상 버킷 |
| `CLOUDFLARE_ZONE_ID` | (선택) | purge 대상 zone |
| `MALL_API_BASE_URL` | `https://mall-api.anoveli.com` | Flutter 빌드 `--dart-define` (미설정 시 스크립트 기본값) |

IAM Role trust policy에 **이 repo**(`ShoppingMall`)가 포함되어야 한다.  
Role 정책은 **`s3://버킷/mall/*`** 만 `s3:PutObject`·`DeleteObject`·`ListBucket` (prefix 조건). 아노벨리 role이 루트만 허용이면 `mall/*` 권한 추가.

DummyJSON import 등 **DB 시드**는 자동 배포에 포함하지 않는다. 필요 시 EC2에서:

```bash
cd /opt/shopping-mall
docker compose -f docker-compose.prod.yml --env-file .env.prod exec -T api \
  python -m scripts.import_dummyjson_catalog
```

---

## 하지 말 것

- `/opt/anoveli` 덮어쓰기 또는 compose 중지
- S3 버킷 루트에 mall 빌드 업로드
- Tunnel에서 `api.anoveli.com`을 8001로 변경
