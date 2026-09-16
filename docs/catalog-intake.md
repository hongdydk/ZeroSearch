# 카탈로그 등록·분류 (판매자 초안 → MD 검수)

**상태:** MVP 구현. 활성 CSV 운영(`data/aihub-catalog.csv`)은 그대로 두고, 판매자 등록 구멍을 초안 큐로 막는다.
고신뢰 자동 붙이기·canonical 종류 목록·`price_unit` 재설계는 이 범위에 넣지 않았다.

판매자·관리자 포털 보강 방향은 [phase3-spec.md](./phase3-spec.md). 카드 identity 원칙은 [README](./README.md) 「대표 상품은 누가 만드나」.

---

## 허용 경로 (이번 구현)

- `apps/api/app/models/catalog_intake.py`
- `apps/api/alembic/versions/011_catalog_intake_drafts.py`
- `apps/api/app/schemas/catalog_intake.py`
- `apps/api/app/services/catalog_intake.py`
- `apps/api/app/services/products.py` (오퍼 생성은 항상 `draft`, 판매자 공개 금지)
- `apps/api/app/routers/seller.py` (`POST /seller/products`, `/seller/card-drafts`)
- `apps/api/app/routers/admin.py` (`/admin/catalog/drafts`, attach, promote)
- `apps/api/tests/test_catalog_intake.py`
- `apps/flutter/lib/features/seller/seller_products_screen.dart`
- `apps/flutter/lib/features/admin/admin_screen.dart`
- `apps/flutter/lib/core/network/api_client.dart`
- `apps/flutter/lib/core/models/models.dart`
- `scripts/openapi.json`

---

## 짧은 DoD

- [x] 있는 품목: 판매자는 기존 카드에 **오퍼 초안**(가격·재고·팩·사진). `published`로 바로 카드에 안 붙음
- [x] 없는 품목: 판매자는 **카드 초안** + 오퍼 1줄. `catalog_products` insert 없음
- [x] MD(`/admin` 카탈로그): 큐에서 **기존 카드에 붙이기** 또는 **초안을 카드로 승격**(종류 선택)
- [x] 공개 목록·상세는 승인된 `catalog_products` + `status=published` 오퍼만
- [x] 제목만으로 카탈로그를 만들거나 없는 품목을 공개 목록에 넣는 경로 없음
- [x] OpenAPI export · 게이트 테스트

---

## 방향 (합의)

플랫폼이 **카드 identity·종류·비교 단위**를 가진다. 판매자는 그 위에 **오퍼**를 붙인다. 없는 품목의 **첫 입력은 판매자**, **목록에 올리는 확정은 MD**다. 공식 판매자와 MD가 한 사람이어도 단계를 합치지 않는다. 입력은 판매자 모드, 승격은 운영 모드.

| 상황 | 판매자 | MD | 공개 |
|------|--------|----|------|
| 있는 품목 | 기존 카드에 오퍼 초안 (가격·재고·팩·사진) | 후보가 맞는지, 애매하면 큐 | 카드에 붙은 뒤 |
| 없는 품목 | **카드 초안** + 자기 오퍼 1줄 (회사·품목명·종류 짐작·대표 사진·맛/용량) | 기존 카드에 붙일지 / 초안을 카드로 승격할지 | 승격 다음 |

엔진은 전 품목 분류기가 아니라 **기존 카드 후보 / 신규 큐**만 만든다. MD가 할 결정은 (1) 종류 (2) 이 회사의 이 품목을 한 장으로 둘지 뿐이다. AI-Hub 455 소분류를 맞추는 일은 MD 일이 아니다.

종류·비교 단위는 쇼핑몰용 canonical 목록을 작게 두고, AI-Hub 대·중·소는 힌트·감사 필드로 남긴다. 병합 키를 틀린 소분류에 묶어두면 같은 품목이 두 장이 된다. 매핑·충돌 override(`catalog-category-conflicts.csv` 등)는 이 게이트와 같이 설계한다.

---

## 하지 않음 (유지)

- 판매자 제목·HTML이 곧 상품 페이지 (전통 PDP)
- 판매자 등록이 곧바로 `catalog_products` insert · 목록 노출
- 사후 카테고리 태그만 달고 identity는 판매자 제목에 맡김
- 상세 칩마다 다른 묶음의 최저가를 대표가로 보여 주기
- 영양·퀴즈·합리적 소비 코치로 제품 한 줄을 바꾸기
- 고신뢰 자동 붙이기, canonical 종류 목록, `price_unit` 재설계 (추후)

겸직(공식 `platform` 판매자 = MD)이어도 승격 규칙은 입점과 같다. 대기만 짧게 할 수 있다.
