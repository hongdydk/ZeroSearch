"""PostgreSQL 재고 동시성 통합 테스트.

활성화: RUN_PG_CONCURRENCY=1 과 DATABASE_URL(Postgres).
CI는 alembic upgrade head 후 이 플래그로 실행한다.
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


def _seed_seller_and_catalog(db: Session) -> tuple[Seller, CatalogProduct]:
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
    return seller, catalog


def _make_buyer_with_cart(
    db: Session,
    *,
    product: Product,
    qty: int,
    credits: int,
) -> User:
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


def _checkout_in_own_session(SessionFactory, user_id: uuid.UUID) -> str:
    """별도 세션에서 checkout + commit. 성공 시 'ok', 재고 부족 시 'stock', 그 외 예외 전파."""
    db: Session = SessionFactory()
    try:
        user = db.get(User, user_id)
        assert user is not None
        checkout(db, user)
        db.commit()
        return "ok"
    except HTTPException as exc:
        db.rollback()
        if exc.status_code == 400 and "재고" in str(exc.detail):
            return "stock"
        raise
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def test_concurrent_checkout_respects_stock_cap(SessionFactory):
    stock = 10
    buyers_n = 20

    with SessionFactory() as db:
        seller, catalog = _seed_seller_and_catalog(db)
        product = Product(
            seller_id=seller.id,
            catalog_product_id=catalog.id,
            title="동시성 텀블러",
            price_credits=1,
            stock=stock,
            category="생활",
            status="published",
        )
        db.add(product)
        db.flush()
        product_id = product.id

        buyer_ids: list[uuid.UUID] = []
        for _ in range(buyers_n):
            buyer = _make_buyer_with_cart(db, product=product, qty=1, credits=100)
            buyer_ids.append(buyer.id)
        db.commit()

    results: list[str] = []
    with ThreadPoolExecutor(max_workers=buyers_n) as pool:
        futures = [
            pool.submit(_checkout_in_own_session, SessionFactory, buyer_id)
            for buyer_id in buyer_ids
        ]
        for fut in as_completed(futures):
            results.append(fut.result())

    assert results.count("ok") == stock
    assert results.count("stock") == buyers_n - stock

    with SessionFactory() as db:
        left = db.scalar(select(Product.stock).where(Product.id == product_id))
        paid_n = len(
            list(
                db.scalars(
                    select(OrderItem)
                    .join(Order, OrderItem.order_id == Order.id)
                    .where(OrderItem.product_id == product_id, Order.status == "paid")
                ).all()
            )
        )
        assert left == 0
        assert paid_n == stock
        assert left is not None and left >= 0


def test_partial_stock_failure_rolls_back_prior_reservation(SessionFactory):
    with SessionFactory() as db:
        seller, catalog = _seed_seller_and_catalog(db)
        product_a = Product(
            seller_id=seller.id,
            catalog_product_id=catalog.id,
            title="A-충분",
            price_credits=1,
            stock=5,
            category="생활",
            status="published",
        )
        catalog_b = CatalogProduct(
            title=f"품목-B-{uuid.uuid4().hex[:6]}",
            manufacturer="테스트제조",
            category="생수",
            price_unit="ml",
        )
        db.add(catalog_b)
        db.flush()
        product_b = Product(
            seller_id=seller.id,
            catalog_product_id=catalog_b.id,
            title="B-품절",
            price_credits=1,
            stock=0,
            category="생활",
            status="published",
        )
        db.add(product_a)
        db.add(product_b)
        db.flush()

        # ID 정렬상 A가 먼저 예약되도록 보장하기보다, 둘 다 담은 뒤 실패 시 A도 원복되는지 확인
        user = User(
            email=f"buyer-multi-{uuid.uuid4().hex[:8]}@test.local",
            password_hash=hash_password("pw"),
            display_name="Multi",
        )
        db.add(user)
        db.flush()
        db.add(CreditWallet(user_id=user.id, balance=100))
        db.add(CartItem(user_id=user.id, product_id=product_a.id, qty=1))
        db.add(CartItem(user_id=user.id, product_id=product_b.id, qty=1))
        db.commit()

        a_id, b_id, user_id = product_a.id, product_b.id, user.id

    with SessionFactory() as db:
        user = db.get(User, user_id)
        assert user is not None
        with pytest.raises(HTTPException) as exc_info:
            checkout(db, user)
        assert exc_info.value.status_code == 400
        assert "재고" in str(exc_info.value.detail)
        db.rollback()

    with SessionFactory() as db:
        stock_a = db.scalar(select(Product.stock).where(Product.id == a_id))
        stock_b = db.scalar(select(Product.stock).where(Product.id == b_id))
        assert stock_a == 5
        assert stock_b == 0
        paid = list(
            db.scalars(
                select(Order).where(Order.user_id == user_id, Order.status == "paid")
            ).all()
        )
        assert paid == []
