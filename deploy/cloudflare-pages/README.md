# Cloudflare Pages 레거시

Flutter 웹 배포는 S3 + CloudFront로 이전한다. 이 디렉터리의 Functions·라우트·헤더는 DNS 전환이 검증될 때까지 롤백 참고용으로만 유지하며 CI에서는 사용하지 않는다.

전환 확인 후 이 디렉터리와 `.github/wrangler/`를 삭제할 수 있다.
