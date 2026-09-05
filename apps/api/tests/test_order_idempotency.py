"""PostgreSQL 주문 idempotency 동시성 테스트.

활성화: RUN_PG_CONCURRENCY=1 과 DATABASE_URL(Postgres).
"""

from __future__ import annotations

import os
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine, select, text
from sqlalchemy.orm import Session, sessionmaker

from app.deps import hash_password
from app.models import CartItem, CatalogProduct, CreditWallet, Order, OrderItem, Product, Seller, User
from app.services.orders import checkout

pytestmark = pytest.mark.skipif(
    os.environ.get("RUN_PG_CONCURRENCY") != "1",
    reason="RUN_PG_CONCURRENCY=1 일 때만 PostgreSQL 동시성 테스트 실행",
)


@pytest.fixture(scope="module")
def pg_engine():
    database_url = os.environ.get("DATABASE_URL")
    if not database_url or "postgresql" not in database_url:
        pytest.skip("DATABASE_URL(postgresql) 필요")
    engine = create_engine(database_url, pool_pre_ping=True, pool_size=25, max_overflow=10)
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
        conn.commit()
    yield engine
    engine.dispose()


@pytest.fixture(scope="module")
def SessionFactory(pg_engine):
    return sessionmaker(autocommit=False, autoflush=False, bind=pg_engine)


def _seed_offer(db: Session, *, stock: int = 100, price: int = 10) -> Product:
    owner = User(
        email=f"seller-{uuid.uuid4().hex[:8]}@test.local",
        password_hash=hash_password("pw"),
        display_name="Seller",
    )
    db.add(owner)
    db.flush()
    seller = Seller(
        user_id=owner.id,
        shop_name=f"shop-{uuid.uuid4().hex[:6]}",
        slug=f"shop-{uuid.uuid4().hex[:8]}",
        status="active",
        seller_type="platform",
    )
    catalog = CatalogProduct(
        title=f"품목-{uuid.uuid4().hex[:6]}",
        manufacturer="테스트제조",
        category="생수",
        price_unit="ml",
    )
    db.add(seller)
    db.add(catalog)
    db.flush()
    product = Product(
        seller_id=seller.id,
        catalog_product_id=catalog.id,
        title="idem-test",
        price_credits=price,
        stock=stock,
        category="생수",
        status="published",
    )
    db.add(product)
    db.flush()
    return product


def _make_buyer_with_cart(db: Session, *, product: Product, qty: int, credits: int) -> User:
    user = User(
        email=f"buyer-{uuid.uuid4().hex[:10]}@test.local",
        password_hash=hash_password("pw"),
        display_name="Buyer",
    )
    db.add(user)
    db.flush()
    db.add(CreditWallet(user_id=user.id, balance=credits))
    db.add(CartItem(user_id=user.id, product_id=product.id, qty=qty))
    db.flush()
    return user


def _checkout_with_key(SessionFactory, user_id: uuid.UUID, key: str) -> tuple[str, str | None]:
    db: Session = SessionFactory()
    try:
        user = db.get(User, user_id)
        assert user is not None
        order, _created = checkout(db, user, idempotency_key=key)
        db.commit()
        return "ok", order.id
    except HTTPException as exc:
        db.rollback()
        if exc.status_code == 409:
            return "conflict", None
        raise
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def test_idempotent_checkout_sequential_same_key(SessionFactory):
    with SessionFactory() as db:
        product = _seed_offer(db, stock=5, price=10)
        buyer = _make_buyer_with_cart(db, product=product, qty=1, credits=100)
        product_id = product.id
        buyer_id = buyer.id
        db.commit()

    key = f"seq-{uuid.uuid4().hex}"
    with SessionFactory() as db:
        user = db.get(User, buyer_id)
        assert user is not None
        first, created = checkout(db, user, idempotency_key=key)
        db.commit()
        assert created is True

    with SessionFactory() as db:
        user = db.get(User, buyer_id)
        assert user is not None
        # 장바구니는 비었지만 같은 키면 paid 주문 replay
        second, created = checkout(db, user, idempotency_key=key)
        db.commit()
        assert created is False
        assert second.id == first.id

    with SessionFactory() as db:
        stock = db.scalar(select(Product.stock).where(Product.id == product_id))
        orders = db.scalars(select(Order).where(Order.user_id == buyer_id)).all()
        assert stock == 4
        assert len(orders) == 1


def test_idempotent_checkout_concurrent_same_key(SessionFactory):
    with SessionFactory() as db:
        product = _seed_offer(db, stock=20, price=5)
        buyer = _make_buyer_with_cart(db, product=product, qty=1, credits=100)
        product_id = product.id
        buyer_id = buyer.id
        db.commit()

    key = f"conc-{uuid.uuid4().hex}"
    results: list[tuple[str, str | None]] = []
    with ThreadPoolExecutor(max_workers=8) as pool:
        futures = [
            pool.submit(_checkout_with_key, SessionFactory, buyer_id, key) for _ in range(8)
        ]
        for fut in as_completed(futures):
            results.append(fut.result())

    oks = [r for r in results if r[0] == "ok"]
    conflicts = [r for r in results if r[0] == "conflict"]
    assert len(oks) >= 1
    assert len(oks) + len(conflicts) == 8
    order_ids = {oid for status, oid in oks if oid}
    assert len(order_ids) == 1

    with SessionFactory() as db:
        stock = db.scalar(select(Product.stock).where(Product.id == product_id))
        orders = list(db.scalars(select(Order).where(Order.user_id == buyer_id)).all())
        items = list(db.scalars(select(OrderItem).where(OrderItem.order_id == orders[0].id)).all())
        assert len(orders) == 1
        assert stock == 19
        assert sum(i.qty for i in items) == 1
