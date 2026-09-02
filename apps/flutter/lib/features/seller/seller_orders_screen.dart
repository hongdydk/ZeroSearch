import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/price_format.dart';
import '../../core/fulfillment/fulfillment_labels.dart';
import '../../core/models/models.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/page_form_scaffold.dart';

class SellerOrdersScreen extends ConsumerStatefulWidget {
  const SellerOrdersScreen({super.key});

  @override
  ConsumerState<SellerOrdersScreen> createState() => _SellerOrdersScreenState();
}

class _SellerOrdersScreenState extends ConsumerState<SellerOrdersScreen> {
  List<SellerOrderItemModel> _items = [];
  bool _loading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final items = await ref.read(apiClientProvider).sellerOrders();
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _advance(SellerOrderItemModel item) async {
    final next = nextFulfillmentStatus(item.fulfillmentStatus);
    if (next == null) return;

    try {
      await ref.read(apiClientProvider).sellerUpdateOrderStatus(item.id, next);
      await _load(silent: true);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageFormScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('주문 관리', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_items.isEmpty)
            const Center(child: Text('주문이 없습니다.'))
          else
            ..._items.map(
              (item) => Card(
                child: ListTile(
                  title: Text(item.productTitle),
                  subtitle: Text(
                    '${item.qty}개 · ${formatWon(item.lineTotalCredits)} · '
                    '${fulfillmentStatusLabel(item.fulfillmentStatus)}',
                  ),
                  trailing: nextFulfillmentStatus(item.fulfillmentStatus) == null
                      ? null
                      : TextButton(
                          onPressed: () => _advance(item),
                          child: Text(nextFulfillmentActionLabel(item.fulfillmentStatus)),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
