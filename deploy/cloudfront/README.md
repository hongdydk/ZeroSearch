# ShoppingMall CloudFront 설정

`mall.anoveli.com`의 정적 Flutter 파일은 S3에서, `/api*`는 기존 `mall-api.anoveli.com` Tunnel에서 제공한다. 브라우저 API 주소는 `https://mall.anoveli.com/api`로 유지한다.

## 1. S3

- 버킷: GitHub variable `S3_BUCKET` (`mall-web-poc`)
- Region: `ap-northeast-2`
- Block Public Access: 전부 활성
- Static website hosting: 비활성
- CloudFront Origin Access Control(OAC)만 `s3:GetObject` 허용

OAC 생성 후 CloudFront가 제시하는 버킷 정책을 적용한다. 정책의 Resource는 `arn:aws:s3:::mall-web-poc/*`, Principal은 `cloudfront.amazonaws.com`, Condition은 생성한 distribution ARN의 `AWS:SourceArn`으로 제한한다.

## 2. 인증서와 origin

- ACM Region: `us-east-1` (CloudFront 필수)
- Domain: `mall.anoveli.com`
- 검증: Cloudflare DNS에 ACM이 제시하는 CNAME 추가
- Default root object: 비워 둔다. SPA Function이 `/`를 `/index.html`로 바꾼다.

Origin:

1. `mall-web-poc.s3.ap-northeast-2.amazonaws.com`
   - Origin access: OAC
   - Origin type: S3
2. `mall-api.anoveli.com`
   - Origin protocol: HTTPS only
   - Origin type: Custom
   - Origin path: 비움

## 3. behavior와 Function

CloudFront Function 두 개를 Runtime 2.0으로 만들고 Publish한다.

- `mall-strip-api-prefix`: [`strip-api-prefix.js`](./strip-api-prefix.js)
- `mall-spa-route-rewrite`: [`spa-route-rewrite.js`](./spa-route-rewrite.js)

Behaviors:

| 우선순위 | Path pattern | Origin | Methods | Cache policy | Origin request policy | Viewer request Function |
|---|---|---|---|---|---|---|
| 0 | `/api*` | `mall-api.anoveli.com` | GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE | Managed-CachingDisabled | Managed-AllViewerExceptHostHeader | `mall-strip-api-prefix` |
| 기본 | `Default (*)` | S3 | GET, HEAD, OPTIONS | Managed-CachingOptimized | 없음 | `mall-spa-route-rewrite` |

두 behavior 모두 Viewer protocol policy는 Redirect HTTP to HTTPS다. `/api*`가 기본 behavior보다 먼저 선택되는지 확인한다.

전역 Custom error response(403/404 → `/index.html`)는 설정하지 않는다. API의 정상적인 404까지 HTML 200으로 바뀌기 때문이다.

Alternate domain name에 `mall.anoveli.com`을 넣고 위 ACM 인증서를 선택한다.

## 4. GitHub OIDC

GitHub variable:

- `AWS_DEPLOY_ROLE_ARN`
- `S3_BUCKET=mall-web-poc`
- `CLOUDFRONT_DISTRIBUTION_ID`
- `MALL_API_BASE_URL=https://mall.anoveli.com/api`

OIDC 역할 trust는 이 저장소의 `main` ref로 제한한다. 권한은 다음 범위만 허용한다.

- 버킷 자체: `s3:ListBucket`
- `mall-web-poc/*`: `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`
- 해당 distribution: `cloudfront:CreateInvalidation`

현재 `AWS_DEPLOY_ROLE_ARN`이 아노벨리 공용 역할을 가리키므로, 위 S3·CloudFront 권한이 없다면 쇼핑몰 전용 역할로 교체한다.

## 5. 전환과 롤백

1. 첫 파일은 수동 업로드하거나 CI의 `deploy-web`로 S3에 배포한다.
2. DNS 전환 전에는 `curl --connect-to mall.anoveli.com:443:<distribution>.cloudfront.net:443 https://mall.anoveli.com/api/health`로 alias·API를 검증한다.
3. `/`, `/admin`, `/seller`, `/main.dart.js`, `/api/health`를 확인한다.
4. Cloudflare DNS의 `mall` CNAME을 distribution domain으로 바꾸고 DNS only로 둔다.
5. `mall.anoveli.com` 확인 후 Pages custom domain을 제거한다.

롤백은 Cloudflare DNS `mall`을 기존 Pages target으로 되돌리는 방식이다. 검증 전에는 Pages project, [`../cloudflare-pages/`](../cloudflare-pages/), `.github/wrangler/`를 삭제하지 않는다.
