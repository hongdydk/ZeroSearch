import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/price_format.dart';
import '../../core/fulfillment/fulfillment_labels.dart';
import '../../core/models/models.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/async_busy.dart';
import '../../shared/widgets/portal_workspace.dart';

class SellerOrdersScreen extends ConsumerStatefulWidget {
  const SellerOrdersScreen({super.key});

  @override
  ConsumerState<SellerOrdersScreen> createState() => _SellerOrdersScreenState();
}

class _SellerOrdersScreenState extends ConsumerState<SellerOrdersScreen>
    with AsyncBusyState {
  List<SellerOrderItemModel> _items = [];
  bool _loading = true;
  String _filter = 'action';
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _load(silent: true),
    );
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _advance(SellerOrderItemModel item) async {
    final next = nextFulfillmentStatus(item.fulfillmentStatus);
    if (next == null) return;
    await runBusy('order:${item.id}', () async {
      try {
        await ref
            .read(apiClientProvider)
            .sellerUpdateOrderStatus(item.id, next);
        await _load(silent: true);
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _items.where((item) {
      return switch (_filter) {
        'action' => item.fulfillmentStatus == 'paid',
        'preparing' => item.fulfillmentStatus == 'preparing',
        'shipping' => item.fulfillmentStatus == 'shipped',
        'done' => nextFulfillmentStatus(item.fulfillmentStatus) == null,
        _ => true,
      };
    }).toList();
    return PortalWorkspaceScaffold(
      role: PortalWorkspaceRole.seller,
      activePath: '/seller/orders',
      child: PortalPage(
        eyebrow: '판매자 센터',
        title: '주문 관리',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _OrderFilterChip(
                  label:
                      '처리 필요 ${_items.where((item) => item.fulfillmentStatus == 'paid').length}',
                  selected: _filter == 'action',
                  onSelected: () => setState(() => _filter = 'action'),
                ),
                _OrderFilterChip(
                  label:
                      '준비 중 ${_items.where((item) => item.fulfillmentStatus == 'preparing').length}',
                  selected: _filter == 'preparing',
                  onSelected: () => setState(() => _filter = 'preparing'),
                ),
                _OrderFilterChip(
                  label:
                      '배송 중 ${_items.where((item) => item.fulfillmentStatus == 'shipped').length}',
                  selected: _filter == 'shipping',
                  onSelected: () => setState(() => _filter = 'shipping'),
                ),
                _OrderFilterChip(
                  label: '전체 ${_items.length}',
                  selected: _filter == 'all',
                  onSelected: () => setState(() => _filter = 'all'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            PortalSection(
              title: '내가 배송할 주문 줄',
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(22),
                      child: Text('이 조건에 맞는 주문이 없습니다.'),
                    )
                  : Column(
                      children: [
                        for (final item in filtered)
                          ListTile(
                            title: Text(item.productTitle),
                            subtitle: Text(
                              '#${item.orderId} · ${item.qty}개 · '
                              '${formatWon(item.lineTotalCredits)} · '
                              '${shippingOwnerLabel(item.sellerType ?? 'merchant')}',
                            ),
                            trailing:
                                nextFulfillmentStatus(item.fulfillmentStatus) ==
                                    null
                                ? PortalStatusBadge(
                                    label: fulfillmentStatusLabel(
                                      item.fulfillmentStatus,
                                    ),
                                  )
                                : TextButton(
                                    onPressed: isBusy('order:${item.id}')
                                        ? null
                                        : () => _advance(item),
                                    child: isBusy('order:${item.id}')
                                        ? busyProgress()
                                        : Text(
                                            nextFulfillmentActionLabel(
                                              item.fulfillmentStatus,
                                            ),
                                          ),
                                  ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderFilterChip extends StatelessWidget {
  const _OrderFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}
