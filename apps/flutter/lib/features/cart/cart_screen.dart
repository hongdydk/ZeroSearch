import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/page_form_scaffold.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  bool _checkingOut = false;

  Future<void> _updateQty(String productId, int qty) async {
    try {
      await ref.read(apiClientProvider).updateCartItem(productId, qty);
      ref.invalidate(cartProvider);
      ref.invalidate(creditsProvider);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }

  Future<void> _remove(String productId) async {
    try {
      await ref.read(apiClientProvider).removeFromCart(productId);
      ref.invalidate(cartProvider);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }

  Future<void> _checkout() async {
    setState(() => _checkingOut = true);
    try {
      await ref.read(apiClientProvider).checkout();
      ref.invalidate(cartProvider);
      ref.invalidate(creditsProvider);
      ref.invalidate(ordersProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('주문이 완료되었습니다.')),
      );
      context.go('/orders');
    } on ApiException catch (e) {
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
        error: (e, _) => Center(child: Text('장바구니를 불러오지 못했습니다: $e')),
        data: (cart) {
          if (cart.items.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('장바구니', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 24),
                const Center(child: Text('장바구니가 비어 있습니다.')),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => context.go('/'),
                  child: const Text('쇼핑 계속하기'),
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('장바구니', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              ...cart.items.map(
                (item) => Card(
                  child: ListTile(
                    title: Text(item.productTitle),
                    subtitle: Text('💎 ${item.priceCredits} × ${item.qty}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: item.qty > 1
                              ? () => _updateQty(item.productId, item.qty - 1)
                              : null,
                        ),
                        Text('${item.qty}'),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () => _updateQty(item.productId, item.qty + 1),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _remove(item.productId),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '합계: 💎 ${cart.totalCredits}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _checkingOut ? null : _checkout,
                child: Text(_checkingOut ? '결제 중…' : '크레딧으로 주문하기'),
              ),
            ],
          );
        },
      ),
    );
  }
}
