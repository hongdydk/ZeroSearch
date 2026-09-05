"""동시 다량 주문 MVP 기준선 (수동).

활성화: RUN_LOAD_BASELINE=1 과 DATABASE_URL(Postgres).
CI 매 push에는 넣지 않는다. 기록 방법은 docs/load-baseline.md.
"""

from __future__ import annotations

import os
import statistics
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed

import pytest
from sqlalchemy import create_engine, select, text
from sqlalchemy.orm import Session, sessionmaker

from app.deps import hash_password
from app.models import CartItem, CatalogProduct, CreditWallet, Order, OrderItem, Product, Seller, User
from app.services.orders import checkout

pytestmark = pytest.mark.skipif(
    os.environ.get("RUN_LOAD_BASELINE") != "1",
    reason="RUN_LOAD_BASELINE=1 일 때만 수동 부하 기준선 실행",
)

BUYERS = 50
MAX_TOTAL_SECONDS = 15.0


@pytest.fixture(scope="module")
def pg_engine():
    database_url = os.environ.get("DATABASE_URL")
    if not database_url or "postgresql" not in database_url:
        pytest.skip("DATABASE_URL(postgresql) 필요")
    engine = create_engine(
        database_url,
        pool_pre_ping=True,
        pool_size=5,
        max_overflow=10,
        pool_timeout=30,
        pool_recycle=1800,
    )
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
        conn.commit()
    yield engine
    engine.dispose()


@pytest.fixture(scope="module")
def SessionFactory(pg_engine):
    return sessionmaker(autocommit=False, autoflush=False, bind=pg_engine)


def _checkout_timed(SessionFactory, user_id: uuid.UUID) -> float:
    db: Session = SessionFactory()
    started = time.perf_counter()
    try:
        user = db.get(User, user_id)
        assert user is not None
        checkout(db, user)
        db.commit()
        return time.perf_counter() - started
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def test_fifty_concurrent_checkouts_baseline(SessionFactory, pg_engine):
    buyer_ids: list[uuid.UUID] = []
    product_ids: list[uuid.UUID] = []

    with SessionFactory() as db:
        owner = User(
            email=f"load-seller-{uuid.uuid4().hex[:8]}@test.local",
            password_hash=hash_password("pw"),
            display_name="LoadSeller",
        )
        db.add(owner)
        db.flush()
        seller = Seller(
            user_id=owner.id,
            shop_name=f"load-{uuid.uuid4().hex[:6]}",
            slug=f"load-{uuid.uuid4().hex[:8]}",
            status="active",
            seller_type="platform",
        )
        db.add(seller)
        db.flush()

        for i in range(BUYERS):
            catalog = CatalogProduct(
                title=f"load-item-{i}-{uuid.uuid4().hex[:4]}",
                manufacturer="LoadCo",
                category="생수",
                price_unit="ml",
            )
            db.add(catalog)
            db.flush()
            product = Product(
                seller_id=seller.id,
                catalog_product_id=catalog.id,
                title=f"load-offer-{i}",
                price_credits=1,
                stock=5,
                category="생수",
                status="published",
            )
            db.add(product)
            db.flush()
            buyer = User(
                email=f"load-buyer-{i}-{uuid.uuid4().hex[:8]}@test.local",
                password_hash=hash_password("pw"),
                display_name=f"Buyer{i}",
            )
            db.add(buyer)
            db.flush()
            db.add(CreditWallet(user_id=buyer.id, balance=50))
            db.add(CartItem(user_id=buyer.id, product_id=product.id, qty=1))
            buyer_ids.append(buyer.id)
            product_ids.append(product.id)
        db.commit()

    durations: list[float] = []
    errors: list[BaseException] = []
    wall_start = time.perf_counter()
    with ThreadPoolExecutor(max_workers=BUYERS) as pool:
        futures = [pool.submit(_checkout_timed, SessionFactory, uid) for uid in buyer_ids]
        for fut in as_completed(futures):
            try:
                durations.append(fut.result())
            except BaseException as exc:  # noqa: BLE001 — 기준선 집계
                errors.append(exc)
    wall = time.perf_counter() - wall_start

    assert not errors, f"실패 {len(errors)}건: {errors[:3]!r}"
    assert len(durations) == BUYERS
    assert wall < MAX_TOTAL_SECONDS, f"총 소요 {wall:.2f}s > {MAX_TOTAL_SECONDS}s"
    p95 = statistics.quantiles(durations, n=20)[18] if len(durations) >= 20 else max(durations)

    with SessionFactory() as db:
        order_count = len(
            list(db.scalars(select(Order).where(Order.user_id.in_(buyer_ids))).all())
        )
        assert order_count == BUYERS
        for pid in product_ids:
            stock = db.scalar(select(Product.stock).where(Product.id == pid))
            assert stock == 4
        item_count = len(
            list(
                db.scalars(
                    select(OrderItem).where(OrderItem.product_id.in_(product_ids))
                ).all()
            )
        )
        assert item_count == BUYERS

    # 풀 timeout 카운터 (SQLAlchemy 2)
    status = pg_engine.pool.status()
    print(
        f"LOAD_BASELINE buyers={BUYERS} wall={wall:.3f}s "
        f"p95={p95:.3f}s pool={status}"
    )
