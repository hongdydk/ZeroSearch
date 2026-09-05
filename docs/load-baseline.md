# 동시 주문 부하 기준선 (MVP)

Phase 2 「구매·주문 안정화」 #7. **구현은 DB pool 명시 + 50건 수동 기준선**까지.  
다중 worker·rate limit·주문 큐는 실제 서비스 규모가 생길 때만 도입한다.

## 현재 MVP 설정

| 환경 변수 | 기본값 | 의미 |
|-----------|--------|------|
| `DB_POOL_SIZE` | 5 | 상시 연결 |
| `DB_MAX_OVERFLOW` | 10 | 피크 overflow |
| `DB_POOL_TIMEOUT` | 30 | 연결 대기(초) |
| `DB_POOL_RECYCLE` | 1800 | 연결 재생성(초) |

프로세스당 최대 연결 ≈ `pool_size + max_overflow` = **15**.

## 연결 수 계산

```
최대 DB 연결 ≈ worker(또는 uvicorn 프로세스) 수 × (DB_POOL_SIZE + DB_MAX_OVERFLOW)
```

예: worker 2 × 15 = 30. Postgres `max_connections`와 PgBouncer 한도 아래에 둔다.

## 수동 기준선 실행

로컬 PostgreSQL에서:

```bash
cd apps/api
# alembic upgrade head 후
set RUN_LOAD_BASELINE=1
set DATABASE_URL=postgresql+psycopg://mall:mall@localhost:5434/mall
pytest tests/test_order_load_baseline.py -q -s
```

합격 기준(테스트 assert):

- 서로 다른 상품·지갑 **50건** 동시 checkout
- **100% 성공**
- 총 wall time **15초 미만**
- 주문·재고 정합 (상품당 stock 5→4, 주문 50건)
- 출력에 wall·p95·pool status 기록

**CI 매 push에는 넣지 않는다.** (`RUN_LOAD_BASELINE` 미설정 시 skip)

## 규모가 커질 때 (문서만 — 미구현)

도입을 **고려**하는 조건 예:

| 증상 | 후보 |
|------|------|
| pool timeout / DB 연결 고갈 | PgBouncer, pool 조정, read replica |
| 단일 worker CPU·요청 대기 | uvicorn/gunicorn worker 수 증가 (연결 수 재계산) |
| 악의적·버스트 트래픽 | API rate limit (IP·유저) |
| 결제·재고 처리 지연 | 주문 큐(Redis 등) + worker, 클라이언트 idempotency 유지 |

Phase 4 토스 연동 시 결제 승인·웹훅 멱등과 함께 재검토한다.
