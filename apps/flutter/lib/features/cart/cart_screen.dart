import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format/price_format.dart';
import '../../core/fulfillment/fulfillment_labels.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_providers.dart';
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

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(cartProvider.notifier).refreshAuthoritative());
    });
  }

  Future<void> _goCheckout() async {
    await ref.read(cartProvider.notifier).flushPending();
    if (!mounted) return;
    context.push('/checkout');
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(cartSyncErrorProvider, (prev, next) {
      if (next == null || next.isEmpty) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      ref.read(cartSyncErrorProvider.notifier).state = null;
    });

    final cartAsync = ref.watch(cartProvider);

    return PageFormScaffold(
      child: cartAsync.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('장바구니를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.'),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () =>
                    unawaited(ref.read(cartProvider.notifier).refreshAuthoritative()),
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

          final canCheckout = !cart.checkoutBlocked;

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
                                tooltip: '수량 줄이기',
                                icon: const Icon(Icons.remove),
                                onPressed: item.qty <= 1
                                    ? null
                                    : () => ref
                                          .read(cartProvider.notifier)
                                          .updateQty(
                                            item.productId,
                                            item.qty - 1,
                                          ),
                              ),
                              Text('${item.qty}'),
                              IconButton(
                                tooltip: '수량 늘리기',
                                icon: const Icon(Icons.add),
                                onPressed: !canIncrease
                                    ? null
                                    : () => ref
                                          .read(cartProvider.notifier)
                                          .updateQty(
                                            item.productId,
                                            item.qty + 1,
                                          ),
                              ),
                              IconButton(
                                tooltip: '삭제',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => ref
                                    .read(cartProvider.notifier)
                                    .remove(item.productId),
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
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (cart.checkoutBlocked) ...[
                const SizedBox(height: 8),
                Text(
                  '구매할 수 없는 상품이 있어 주문할 수 없습니다. 수량 조정 또는 삭제가 필요합니다.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: canCheckout ? _goCheckout : null,
                child: const Text('주문하기'),
              ),
            ],
          );
        },
      ),
    );
  }
}
