import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../network/api_exception.dart';
import '../providers/app_providers.dart';
import '../routing/login_location.dart';
import '../routing/safe_next_path.dart';
import 'cart_feedback.dart';
import 'pending_cart_add.dart';

void listenForPendingCartAdd(WidgetRef ref, BuildContext context) {
  ref.listen<AsyncValue<AuthState>>(authStateProvider, (prev, next) {
    final wasBuyer = prev?.valueOrNull?.isMallBuyer == true;
    final isBuyer = next.valueOrNull?.isMallBuyer == true;
    if (!isBuyer || wasBuyer) return;
    unawaited(consumePendingCartAddIfBuyer(ref: ref, context: context));
  });
}

void beginGuestAddLogin(
  BuildContext context,
  WidgetRef ref, {
  required String productId,
  required int qty,
  required Uri fallbackLocation,
}) {
  final pending = PendingCartAdd(productId: productId, qty: qty.clamp(1, 99));
  ref.read(pendingCartAddProvider.notifier).state = pending;
  final here = GoRouter.maybeOf(context)?.state.uri ?? fallbackLocation;
  context.go(
    buyerLoginLocation(
      withPendingCartAdd(here, productId: pending.productId, qty: pending.qty),
    ),
  );
}

Future<void> consumePendingCartAddIfBuyer({
  required WidgetRef ref,
  required BuildContext context,
}) async {
  if (ref.read(authStateProvider).valueOrNull?.isMallBuyer != true) return;
  if (ref.read(pendingCartAddClaimedProvider)) return;
  var pending = ref.read(pendingCartAddProvider);
  if (pending == null) {
    final loc = GoRouter.maybeOf(context)?.state.uri;
    if (loc != null && (loc.path == '/login' || loc.path == '/register')) {
      final next = safeNextPath(loc.queryParameters['next']);
      if (next != null) pending = PendingCartAdd.tryParse(Uri.parse(next));
    }
  }
  if (pending == null) return;

  ref.read(pendingCartAddClaimedProvider.notifier).state = true;
  ref.read(pendingCartAddProvider.notifier).state = null;
  try {
    final cart = await ref.read(apiClientProvider).addToCart(
          pending.productId,
          qty: pending.qty,
        );
    ref.read(cartProvider.notifier).replaceWith(cart);
    if (context.mounted) showAddedToCartSnackBar(context);
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('장바구니에 담지 못했습니다.')),
      );
    }
  } finally {
    ref.read(pendingCartAddClaimedProvider.notifier).state = false;
  }
}
