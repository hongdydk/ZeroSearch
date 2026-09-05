import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format/price_format.dart';
import '../../core/fulfillment/fulfillment_labels.dart';
import '../../core/models/models.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/async_busy.dart';
import '../../shared/widgets/page_form_scaffold.dart';

List<List<CartItemModel>> _groupCartBySeller(List<CartItemModel> items) {
  final groups = <String, List<CartItemModel>>{};
  final order = <String>[];
  for (final item in items) {
    final existing = groups[item.sellerId];
    if (existing == null) {
      order.add(item.sellerId);
      groups[item.sellerId] = [item];
    } else {
      existing.add(item);
    }
  }
  return [for (final id in order) groups[id]!];
}

String _newIdempotencyKey() {
  final rand = Random.secure().nextInt(1 << 32).toRadixString(16);
  return '${DateTime.now().toUtc().microsecondsSinceEpoch}-$rand';
}

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> with AsyncBusyState {
  bool _checkingOut = false;
  String? _checkoutKey;

  void _invalidateCheckoutKey() {
    _checkoutKey = null;
  }

  Future<void> _updateQty(String productId, int qty) async {
    _invalidateCheckoutKey();
    await runBusy('cart:$productId', () async {
      try {
        await ref.read(apiClientProvider).updateCartItem(productId, qty);
        ref.invalidate(cartProvider);
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    });
  }

  Future<void> _remove(String productId) async {
    _invalidateCheckoutKey();
    await runBusy('cart:$productId', () async {
      try {
        await ref.read(apiClientProvider).removeFromCart(productId);
        ref.invalidate(cartProvider);
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    });
  }

  Future<void> _checkout() async {
    setState(() {
      _checkingOut = true;
      _checkoutKey ??= _newIdempotencyKey();
    });
    final key = _checkoutKey!;
    try {
      await ref.read(apiClientProvider).checkout(idempotencyKey: key);
      _checkoutKey = null;
      ref.invalidate(cartProvider);
      ref.invalidate(ordersProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('주문이 완료되었습니다.')),
      );
      context.go('/orders');
    } on ApiException catch (e) {
      // timeout/네트워크는 같은 키 재사용. 확정 4xx(타임아웃 메시지 제외)는 새 키.
      final retryable = e.message.contains('시간') || e.message.contains('연결');
      if (!retryable) {
        _invalidateCheckoutKey();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Theme.of(context).colorScheme.error),
      );
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartAsync = ref.watch(cartProvider);

    return PageFormScaffold(
      child: cartAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('장바구니를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.'),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => ref.invalidate(cartProvider),
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
        data: (cart) {
          if (cart.items.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('장바구니', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 24),
                const Center(child: Text('아직 담은 상품이 없어요.')),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => context.go('/'),
                  child: const Text('상품 둘러보기'),
                ),
              ],
            );
          }

          final canCheckout = !cart.checkoutBlocked && !_checkingOut && !isBusy();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('장바구니', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              ..._groupCartBySeller(cart.items).expand((group) {
                final header = group.first;
                return [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    child: Text(
                      '${header.shopName} · ${shippingOwnerLabel(header.sellerType)}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  ...group.map((item) {
                    final rowBusy = isBusy('cart:${item.productId}') || _checkingOut;
                    final muted = !item.isAvailable;
                    final canIncrease = !muted && item.qty < item.maxQty;
                    return Opacity(
                      opacity: muted ? 0.55 : 1,
                      child: Card(
                        child: ListTile(
                          title: Text(item.productTitle),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(formatWonLine(item.priceCredits, item.qty)),
                              if (item.issueMessage != null)
                                Text(
                                  item.issueMessage!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                          isThreeLine: item.issueMessage != null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove),
                                onPressed: rowBusy || item.qty <= 1
                                    ? null
                                    : () => _updateQty(item.productId, item.qty - 1),
                              ),
                              Text('${item.qty}'),
                              IconButton(
                                icon: const Icon(Icons.add),
                                onPressed: rowBusy || !canIncrease
                                    ? null
                                    : () => _updateQty(item.productId, item.qty + 1),
                              ),
                              IconButton(
                                icon: rowBusy ? busyProgress() : const Icon(Icons.delete_outline),
                                onPressed: rowBusy ? null : () => _remove(item.productId),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ];
              }),
              const SizedBox(height: 16),
              Text(
                '합계: ${formatWon(cart.totalCredits)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (cart.checkoutBlocked) ...[
                const SizedBox(height: 8),
                Text(
                  '구매할 수 없는 상품이 있어 주문할 수 없습니다. 수량 조정 또는 삭제가 필요합니다.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: canCheckout ? _checkout : null,
                child: Text(_checkingOut ? '결제 중…' : '주문하기'),
              ),
            ],
          );
        },
      ),
    );
  }
}
