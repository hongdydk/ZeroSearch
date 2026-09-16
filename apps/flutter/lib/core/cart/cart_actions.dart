import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import 'guest_cart.dart';

Future<void> addOfferToCart(
  WidgetRef ref, {
  required String productId,
  required int qty,
  GuestCartLine? snapshot,
}) async {
  final line = snapshot ?? GuestCartLine(productId: productId, qty: qty);
  await ref.read(cartProvider.notifier).addItem(
        productId: productId,
        productTitle: line.productTitle?.trim().isNotEmpty == true
            ? line.productTitle!
            : '상품',
        qty: qty,
        priceCredits: line.priceCredits ?? 0,
        sellerId: line.sellerId ?? '',
        shopName: line.shopName ?? '',
        sellerType: line.sellerType ?? 'merchant',
        maxQty: line.maxQty ?? 99,
      );
}

void updateVisibleCartQty(
  WidgetRef ref, {
  required String productId,
  required int qty,
}) {
  ref.read(cartProvider.notifier).updateQty(productId, qty);
}

void removeVisibleCartItem(
  WidgetRef ref, {
  required String productId,
}) {
  ref.read(cartProvider.notifier).remove(productId);
}
