import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/portal_workspace.dart';

class SellerAlertsScreen extends ConsumerStatefulWidget {
  const SellerAlertsScreen({super.key});

  @override
  ConsumerState<SellerAlertsScreen> createState() => _SellerAlertsScreenState();
}

class _SellerAlertsScreenState extends ConsumerState<SellerAlertsScreen> {
  List<SellerOrderItemModel> _orders = const [];
  List<ProductModel> _products = const [];
  List<SellerModerationEventModel> _events = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      final values = await Future.wait([
        api.sellerOrders(),
        api.sellerProducts(limit: 100),
        api.sellerModerationEvents(),
      ]);
      if (mounted) setState(() {
        _orders = values[0] as List<SellerOrderItemModel>;
        _products = (values[1] as SellerProductListPage).items;
        _events = values[2] as List<SellerModerationEventModel>;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final paid = _orders.where((item) => item.fulfillmentStatus == 'paid').length;
    final lowStock = _products.where((item) => item.stock > 0 && item.stock <= 5).toList();
    return PortalWorkspaceScaffold(
      role: PortalWorkspaceRole.seller,
      activePath: '/seller/alerts',
      child: PortalPage(
        eyebrow: '판매자 센터',
        title: '알림',
        trailing: IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text(_error!))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AlertTile(
                    icon: Icons.shopping_bag_outlined,
                    title: '새 주문 처리',
                    message: paid == 0 ? '처리할 새 주문이 없습니다.' : '$paid건이 출고 준비를 기다리고 있습니다.',
                    onTap: () => context.go('/seller/orders'),
                  ),
                  _AlertTile(
                    icon: Icons.inventory_2_outlined,
                    title: '재고 부족',
                    message: lowStock.isEmpty ? '재고 5개 이하인 오퍼가 없습니다.' : '${lowStock.length}건의 재고가 5개 이하입니다.',
                    onTap: () => context.go('/seller/products'),
                  ),
                  if (_events.isNotEmpty)
                    _AlertTile(
                      icon: Icons.campaign_outlined,
                      title: _events.first.actionLabel,
                      message: _events.first.reason,
                      onTap: () => context.go('/seller/activity'),
                    ),
                ],
              ),
      ),
    );
  }
}

class SellerActivityScreen extends ConsumerStatefulWidget {
  const SellerActivityScreen({super.key});

  @override
  ConsumerState<SellerActivityScreen> createState() => _SellerActivityScreenState();
}

class _SellerActivityScreenState extends ConsumerState<SellerActivityScreen> {
  List<SellerModerationEventModel> _events = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final events = await ref.read(apiClientProvider).sellerModerationEvents();
      if (mounted) setState(() => _events = events);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => PortalWorkspaceScaffold(
    role: PortalWorkspaceRole.seller,
    activePath: '/seller/activity',
    child: PortalPage(
      eyebrow: '판매자 센터',
      title: '작업 기록',
      trailing: IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : PortalSection(
              title: '관리자 조치 기록',
              child: _events.isEmpty
                  ? const Padding(padding: EdgeInsets.all(16), child: Text('기록이 없습니다.'))
                  : Column(children: [for (final event in _events) _EventTile(event: event)]),
            ),
    ),
  );
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.icon, required this.title, required this.message, required this.onTap});
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(leading: Icon(icon), title: Text(title), subtitle: Text(message), trailing: const Icon(Icons.chevron_right), onTap: onTap),
  );
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});
  final SellerModerationEventModel event;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.history),
    title: Text(event.actionLabel),
    subtitle: Text(event.reason),
    trailing: event.createdAt == null ? null : Text(event.createdAt!.replaceFirst('T', '\n').split('.').first, textAlign: TextAlign.end),
  );
}
