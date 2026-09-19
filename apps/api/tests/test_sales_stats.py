import uuid
from datetime import UTC, datetime
from unittest.mock import MagicMock

from app.services.sales_stats import get_sales_stats


def test_seller_stats_scope_paid_orders_and_include_deleted_offer_sales():
    db = MagicMock()
    db.execute.side_effect = [
        MagicMock(one=lambda: (2, 3, 2, 7, 18000)),
        MagicMock(all=lambda: [(datetime.now(UTC).date(), 2, 12000)]),
        MagicMock(all=lambda: [("paid", 1), ("delivered", 2)]),
        MagicMock(all=lambda: [("published", 4)]),
    ]
    seller_id = uuid.uuid4()
    stats = get_sales_stats(db, seller_id=seller_id)
    assert stats["paid_order_count"] == 2
    assert stats["sold_item_count"] == 2
    assert stats["sold_amount_sum"] == 18000
    assert len(stats["daily_sales"]) == 30
    assert stats["daily_sales"][-1]["amount"] == 12000
    assert stats["fulfillment_counts"] == {"paid": 1, "delivered": 2}
    assert stats["offer_counts"] == {"published": 4}
    sales_sql = str(db.execute.call_args_list[0].args[0]).lower()
    assert "order_items.seller_id" in sales_sql
    assert "orders.status" in sales_sql
    assert "catalog_product_id" in sales_sql


def test_admin_stats_has_no_seller_filter():
    db = MagicMock()
    db.execute.side_effect = [
        MagicMock(one=lambda: (0, 0, 0, 0, 0)),
        MagicMock(all=lambda: []),
        MagicMock(all=lambda: []),
        MagicMock(all=lambda: []),
    ]
    stats = get_sales_stats(db)
    assert stats["daily_sales"][0]["amount"] == 0
    assert "seller_id" not in str(db.execute.call_args_list[0].args[0]).lower()
