# Phase 4 — 실 PG (토스)

**상태:** 활성 — Flutter 웹 토스 카드 테스트 결제.

**제품:** [제로 서치](./README.md) — 지금 크레딧 스텁 결제를 **토스페이먼츠**로 교체. 웹훅·결제 상태 정합이 핵심.

## 이번 범위

1. `mall.anoveli.com` Flutter 웹에서 토스 카드 테스트 결제를 연다.
2. 서버가 결제 intent의 금액·장바구니 스냅샷을 만들고 토스 승인·조회·자동 취소를 담당한다.
3. 결제 성공 때만 주문·재고 차감·장바구니 비움을 한 번 수행한다.
4. 웹훅은 본문을 신뢰하지 않고 토스 조회 API로 재검증하며 중복 요청은 같은 결과에 수렴한다.

## 엔티티

`payment_intents`: 사용자, 토스 `order_id`/`payment_key`, 금액(KRW), 상태, 장바구니 JSON 스냅샷, 연계 주문, 실패 정보, 요청·승인 시각.

카드번호·토스 secret은 저장하지 않는다. 기존 `*_credits` 가격 필드는 이번 과도기에 KRW 정수로 사용한다.

## API

- `POST /payments/toss/prepare`
- `POST /payments/toss/confirm`
- `POST /payments/toss/webhook`
- `GET /payments/toss/{order_id}`

기존 `POST /me/orders` 크레딧 체크아웃은 비활성화한다. 주문 조회 API는 유지한다.

## Flutter 라우트

- `/payment/success`
- `/payment/fail`

## 선행/병행: 배송지·주문 취소·환불

“산다”를 닫기 위한 슬롯. Phase 3(판매자·관리자) 이후, 토스 PG **직전 또는 병행**. 엔티티·라우트는 착수 시 Plan에서 채운다. 택배사 API는 범위 밖 ([README](./README.md) 「범위 밖」).

## 범위에 넣지 않음

- 판매자·관리자 포털 확장 → [phase3-spec.md](./phase3-spec.md)
- 라이브 키·계좌이체·가상계좌, 멤버십, 입점 정산
- 구매자 임의 취소·환불 UI, 배송지, 앱 딥링크

## DoD

- 서버 계산 금액과 callback 금액 불일치 시 승인하지 않는다.
- 성공 시에만 `paid` 주문이 한 번 생성되고 판매자 주문 줄에 노출된다.
- 실패·이탈·재고 부족 시 장바구니를 유지하고 과금됐으면 자동 취소한다.
- 웹훅 재전송·success 새로고침이 중복 주문·중복 재고 차감을 만들지 않는다.
- secret은 API 환경변수에만 둔다.
