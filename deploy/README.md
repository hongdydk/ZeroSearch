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
  --dart-define=API_BASE_URL=https://mall-api.anoveli.com
```

S3 콘솔 `anoveli-web-poc` → **폴더 `mall/`** 생성 → `build/web/` 내용을 **`mall/` prefix**에 업로드.  
**버킷 루트(index.html 등)는 업로드하지 않음.**

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

## 하지 말 것

- `/opt/anoveli` 덮어쓰기 또는 compose 중지
- S3 버킷 루트에 mall 빌드 업로드
- Tunnel에서 `api.anoveli.com`을 8001로 변경
