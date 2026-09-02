import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/fulfillment/fulfillment_labels.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/page_form_scaffold.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) ref.invalidate(ordersProvider);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(ordersProvider);

    return PageFormScaffold(
      child: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('주문 내역을 불러오지 못했습니다: $e')),
        data: (orders) {
          if (orders.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('주문', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 24),
                const Center(child: Text('주문 내역이 없습니다.')),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('주문', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              ...orders.map(
                (order) => Card(
                  child: ExpansionTile(
                    title: Text('주문 #${order.id.substring(0, 8)}'),
                    subtitle: Text(
                      '${_statusLabel(order.status)} · 💎 ${order.totalCredits}',
                    ),
                    children: order.items
                        .map(
                          (item) => ListTile(
                            dense: true,
                            title: Text(item.productTitle),
                            subtitle: Text(
                              '${shippingOwnerLabel(item.sellerType)} · '
                              '${item.shopName} · '
                              '${fulfillmentStatusLabel(item.fulfillmentStatus)}',
                            ),
                            trailing: Text('${item.qty} × 💎${item.unitPriceCredits}'),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _statusLabel(String status) {
    return switch (status) {
      'paid' => '결제완료',
      'pending' => '대기',
      'cancelled' => '취소',
      _ => status,
    };
  }
}
