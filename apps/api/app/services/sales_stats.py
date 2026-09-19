"""Paid-order statistics shared by seller and admin portals."""

from datetime import UTC, datetime, timedelta
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import Order, OrderItem, Product


def get_sales_stats(db: Session, *, seller_id: UUID | None = None) -> dict:
    filters = [Order.status == "paid"]
    if seller_id is not None:
        filters.append(OrderItem.seller_id == seller_id)
    base = (
        select(
            func.count(func.distinct(OrderItem.order_id)),
            func.count(OrderItem.id),
            func.count(func.distinct(func.coalesce(OrderItem.catalog_product_id, OrderItem.product_id))),
            func.coalesce(func.sum(OrderItem.qty), 0),
            func.coalesce(func.sum(OrderItem.qty * OrderItem.unit_price_credits), 0),
        )
        .select_from(OrderItem)
        .join(Order, OrderItem.order_id == Order.id)
        .where(*filters)
    )
    order_count, line_count, item_count, qty, amount = db.execute(base).one()

    since = datetime.now(UTC).date() - timedelta(days=29)
    day = func.date(Order.created_at)
    daily_rows = db.execute(
        select(day, func.count(OrderItem.id), func.coalesce(func.sum(OrderItem.qty * OrderItem.unit_price_credits), 0))
        .select_from(OrderItem)
        .join(Order, OrderItem.order_id == Order.id)
        .where(*filters, Order.created_at >= since)
        .group_by(day)
        .order_by(day)
    ).all()
    daily_by_date = {str(row[0]): (int(row[1]), int(row[2])) for row in daily_rows}
    daily_sales = [
        {
            "date": (since + timedelta(days=index)).isoformat(),
            "line_count": daily_by_date.get((since + timedelta(days=index)).isoformat(), (0, 0))[0],
            "amount": daily_by_date.get((since + timedelta(days=index)).isoformat(), (0, 0))[1],
        }
        for index in range(30)
    ]

    fulfillment_rows = db.execute(
        select(OrderItem.fulfillment_status, func.count())
        .select_from(OrderItem)
        .join(Order, OrderItem.order_id == Order.id)
        .where(*filters)
        .group_by(OrderItem.fulfillment_status)
    ).all()
    fulfillment_counts = {status: int(count) for status, count in fulfillment_rows}

    offer_query = select(Product.status, func.count()).group_by(Product.status)
    if seller_id is not None:
        offer_query = offer_query.where(Product.seller_id == seller_id)
    offer_counts = {status: int(count) for status, count in db.execute(offer_query).all()}
    return {
        "paid_order_count": int(order_count),
        "sales_line_count": int(line_count),
        "sold_item_count": int(item_count),
        "sold_qty_sum": int(qty),
        "sold_amount_sum": int(amount),
        "daily_sales": daily_sales,
        "fulfillment_counts": fulfillment_counts,
        "offer_counts": offer_counts,
    }
