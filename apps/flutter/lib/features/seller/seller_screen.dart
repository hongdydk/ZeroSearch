import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/fulfillment/fulfillment_labels.dart';
import '../../core/models/models.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/page_form_scaffold.dart';
import '../../shared/widgets/portal_workspace.dart';

class SellerScreen extends ConsumerStatefulWidget {
  const SellerScreen({super.key});

  @override
  ConsumerState<SellerScreen> createState() => _SellerScreenState();
}

class _SellerScreenState extends ConsumerState<SellerScreen> {
  final _shopController = TextEditingController();
  SellerModel? _seller;
  List<ProductModel> _products = [];
  List<SellerOrderItemModel> _orders = [];
  bool _loading = true;
  bool _metricsLoading = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _shopController.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final firstPaint = _seller == null && !silent;
    if (firstPaint && mounted) setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      final seller = await api.sellerMe();
      if (!mounted) return;
      setState(() {
        _seller = seller;
        _loading = false;
      });
      if (seller?.status != 'active') {
        setState(() {
          _products = [];
          _orders = [];
          _metricsLoading = false;
        });
        return;
      }
      setState(() => _metricsLoading = true);
      final results = await Future.wait([
        api.sellerProducts(),
        api.sellerOrders(),
      ]);
      if (!mounted) return;
      setState(() {
        _products = results[0] as List<ProductModel>;
        _orders = results[1] as List<SellerOrderItemModel>;
        _metricsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _metricsLoading = false;
      });
    }
  }

  Future<void> _apply() async {
    final name = _shopController.text.trim();
    if (name.length < 2) return;
    setState(() => _submitting = true);
    try {
      await ref.read(apiClientProvider).sellerApply(name);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('입점 신청이 접수되었습니다.')));
      await _load(silent: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final seller = _seller;
    if (seller == null) return _buildApplication();
    if (seller.status == 'pending') {
      return const Center(child: Text('입점 승인 대기 중입니다.'));
    }
    if (seller.status == 'suspended') {
      return const Center(child: Text('정지된 판매자 계정입니다.'));
    }

    final published = _products
        .where((item) => item.status == 'published')
        .length;
    final soldOut = _products.where((item) => item.stock <= 0).length;
    final needsAction = _orders
        .where((item) => item.fulfillmentStatus == 'paid')
        .length;
    return PortalWorkspaceScaffold(
      role: PortalWorkspaceRole.seller,
      activePath: '/seller',
      child: PortalPage(
        eyebrow: seller.sellerType == 'platform' ? '공식 스토어' : '입점 스토어',
        title: '${seller.shopName} 운영 홈',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_metricsLoading) const LinearProgressIndicator(minHeight: 2),
            if (_metricsLoading) const SizedBox(height: 12),
            PortalMetricGrid(
              children: [
                PortalMetricCard(
                  label: '처리할 주문 줄',
                  value: '$needsAction',
                  hint: needsAction == 0 ? '처리 완료' : '출고 준비 필요',
                  attention: needsAction > 0,
                ),
                PortalMetricCard(
                  label: '전체 주문 줄',
                  value: '${_orders.length}',
                  hint: '현재 조회 기준',
                ),
                PortalMetricCard(
                  label: '공개 오퍼',
                  value: '$published',
                  hint: '전체 ${_products.length}개',
                ),
                PortalMetricCard(
                  label: '품절 오퍼',
                  value: '$soldOut',
                  hint: soldOut == 0 ? '재고 정상' : '재고 확인 필요',
                  attention: soldOut > 0,
                ),
              ],
            ),
            const SizedBox(height: 18),
            PortalSection(
              title: '최근 주문',
              trailing: TextButton(
                onPressed: () => context.go('/seller/orders'),
                child: const Text('전체 보기'),
              ),
              child: _orders.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('주문이 없습니다.'),
                    )
                  : Column(
                      children: [
                        for (final item in _orders.take(4))
                          ListTile(
                            title: Text(item.productTitle),
                            subtitle: Text(
                              '${item.qty}개 · '
                              '${fulfillmentStatusLabel(item.fulfillmentStatus)}',
                            ),
                            trailing: PortalStatusBadge(
                              label: fulfillmentStatusLabel(
                                item.fulfillmentStatus,
                              ),
                              attention: item.fulfillmentStatus == 'paid',
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

  Widget _buildApplication() {
    return PageFormScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('판매자 센터', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          const Text('스토어를 등록하고 상품을 판매해 보세요.'),
          const SizedBox(height: 16),
          TextField(
            controller: _shopController,
            decoration: const InputDecoration(labelText: '스토어 이름'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _apply,
            child: Text(_submitting ? '신청 중…' : '입점 신청'),
          ),
        ],
      ),
    );
  }
}
