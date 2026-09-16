import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import 'guest_cart_storage.dart';

Future<void> addOfferToCart(
  WidgetRef ref, {
  required String productId,
  required int qty,
  GuestCartLine? snapshot,
}) async {
  final isBuyer = ref.read(authStateProvider).valueOrNull?.isMallBuyer == true;
  if (isBuyer) {
    await ref.read(apiClientProvider).addToCart(productId, qty: qty);
  } else {
    await ref.read(guestCartStorageProvider).add(
          productId,
          qty,
          snapshot: snapshot,
        );
  }
  ref.invalidate(cartProvider);
}

Future<void> updateVisibleCartQty(
  WidgetRef ref, {
  required String productId,
  required int qty,
}) async {
  final isBuyer = ref.read(authStateProvider).valueOrNull?.isMallBuyer == true;
  if (isBuyer) {
    await ref.read(apiClientProvider).updateCartItem(productId, qty);
  } else {
    await ref.read(guestCartStorageProvider).updateQty(productId, qty);
  }
  ref.invalidate(cartProvider);
}

Future<void> removeVisibleCartItem(
  WidgetRef ref, {
  required String productId,
}) async {
  final isBuyer = ref.read(authStateProvider).valueOrNull?.isMallBuyer == true;
  if (isBuyer) {
    await ref.read(apiClientProvider).removeFromCart(productId);
  } else {
    await ref.read(guestCartStorageProvider).remove(productId);
  }
  ref.invalidate(cartProvider);
}
