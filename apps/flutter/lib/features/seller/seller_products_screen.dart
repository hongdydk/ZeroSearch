import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format/price_format.dart';
import '../../core/network/api_exception.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/async_busy.dart';
import '../../shared/widgets/portal_workspace.dart';
import 'seller_offer_format.dart';

class SellerProductsScreen extends ConsumerStatefulWidget {
  const SellerProductsScreen({super.key});

  @override
  ConsumerState<SellerProductsScreen> createState() =>
      _SellerProductsScreenState();
}

class _SellerProductsScreenState extends ConsumerState<SellerProductsScreen>
    with AsyncBusyState {
  List<ProductModel> _products = [];
  List<IntakeDraftModel> _cardDrafts = [];
  bool _loading = true;
  bool _reloading = false;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    final keepList = silent || _products.isNotEmpty || _cardDrafts.isNotEmpty;
    if (mounted) {
      setState(() {
        if (keepList) {
          _reloading = true;
        } else {
          _loading = true;
        }
      });
    }
    try {
      final api = ref.read(apiClientProvider);
      late final List<ProductModel> items;
      var drafts = <IntakeDraftModel>[];
      final draftsFuture = () async {
        try {
          return await api.sellerCardDrafts();
        } on ApiException {
          return <IntakeDraftModel>[];
        }
      }();
      final results = await Future.wait([
        api.sellerProducts(),
        draftsFuture,
      ]);
      items = results[0] as List<ProductModel>;
      drafts = results[1] as List<IntakeDraftModel>;
      if (!mounted) return;
      setState(() {
        _products = items;
        _cardDrafts = drafts;
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _reloading = false;
        });
      }
    }
  }

  Future<void> _openRegister({bool missing = false}) async {
    final path = missing ? '/seller/products/new?missing=1' : '/seller/products/new';
    await context.push(path);
    if (mounted) await _load(silent: true);
  }

  Future<void> _attachDraftPrice(IntakeDraftModel draft) async {
    if (!draft.isPending) return;
    final price = TextEditingController(
      text: draft.hasSellablePrice ? draft.priceCredits.toString() : '',
    );
    final stock = TextEditingController(
      text: draft.hasSellablePrice ? draft.stock.toString() : '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('가격·재고'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(draft.cardTitle),
            TextField(
              controller: price,
              decoration: const InputDecoration(labelText: '가격(원)'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: stock,
              decoration: const InputDecoration(labelText: '재고'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final nextPrice = int.tryParse(price.text.trim());
    final nextStock = int.tryParse(stock.text.trim());
    if (nextPrice == null || nextPrice <= 0 || nextStock == null || nextStock < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('가격과 재고를 숫자로 입력하세요.')),
      );
      return;
    }
    try {
      final updated = await ref.read(apiClientProvider).sellerUpdateCardDraft(
        draft.id,
        priceCredits: nextPrice,
        stock: nextStock,
      );
      if (!mounted) return;
      setState(() {
        _cardDrafts = [
          for (final row in _cardDrafts)
            if (row.id == updated.id) updated else row,
        ];
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _onQuickAction(ProductModel product, String value) async {
    switch (value) {
      case 'edit':
        await _openDetail(product);
      case 'hide':
        await _setHidden(product, hidden: true);
      case 'unhide':
        await _setHidden(product, hidden: false);
      case 'delete':
        await _confirmDelete(product);
    }
  }

  Future<void> _setHidden(ProductModel product, {required bool hidden}) async {
    final key = hidden ? 'hide:${product.id}' : 'unhide:${product.id}';
    if (isBusy(key)) return;
    final nextStatus = hidden ? 'archived' : 'published';
    await runBusy(key, () async {
      try {
        final updated = await ref
            .read(apiClientProvider)
            .sellerUpdateProduct(product.id, status: nextStatus);
        if (!mounted) return;
        setState(() {
          _products = [
            for (final row in _products)
              if (row.id == updated.id) updated else row,
          ];
        });
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    });
  }

  Future<void> _confirmDelete(ProductModel product) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('오퍼 삭제'),
        content: const Text('구매자에게 보이지 않게 숨김으로 옮깁니다. 나중에 숨김 해제로 되돌릴 수 있습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final key = 'delete:${product.id}';
    if (isBusy(key)) return;
    await runBusy(key, () async {
      try {
        await ref.read(apiClientProvider).sellerDeleteProduct(product.id);
        if (!mounted) return;
        setState(() {
          _products = [
            for (final row in _products)
              if (row.id == product.id)
                row.copyWith(status: 'archived')
              else
                row,
          ];
        });
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    });
  }

  Future<void> _openDetail(ProductModel product) async {
    await context.push('/seller/products/${product.id}');
    if (mounted) await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final pendingOffers = _products.where((p) => p.status == 'draft').toList();
    final pendingCards = _cardDrafts.where((d) => d.isPending).toList();
    final filtered = _products
        .where((product) => sellerOfferMatchesFilter(product, _filter))
        .toList();
    return PortalWorkspaceScaffold(
      role: PortalWorkspaceRole.seller,
      activePath: '/seller/products',
      child: PortalPage(
        eyebrow: '판매자 센터',
        title: '내 오퍼',
        trailing: Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _openRegister(missing: true),
              icon: const Icon(Icons.playlist_add_outlined),
              label: const Text('없는 품목'),
            ),
            FilledButton.icon(
              onPressed: () => _openRegister(),
              icon: const Icon(Icons.add),
              label: const Text('오퍼 등록'),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _OfferFilterChip(
                  label: '전체 ${_products.length}',
                  selected: _filter == 'all',
                  onSelected: () => setState(() => _filter = 'all'),
                ),
                _OfferFilterChip(
                  label:
                      '공개 ${_products.where((p) => p.status == 'published' && p.stock > 0).length}',
                  selected: _filter == 'published',
                  onSelected: () => setState(() => _filter = 'published'),
                ),
                _OfferFilterChip(
                  label: '검수 대기 ${pendingOffers.length}',
                  selected: _filter == 'pending',
                  onSelected: () => setState(() => _filter = 'pending'),
                ),
                _OfferFilterChip(
                  label: '품절 ${_products.where((p) => p.stock <= 0 && p.status == 'published').length}',
                  selected: _filter == 'sold_out',
                  onSelected: () => setState(() => _filter = 'sold_out'),
                ),
                _OfferFilterChip(
                  label:
                      '숨김 ${_products.where(sellerOfferIsHidden).length}',
                  selected: _filter == 'hidden',
                  onSelected: () => setState(() => _filter = 'hidden'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_reloading) ...[
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 14),
            ],
            PortalSection(
              title: '카드 초안 ${pendingCards.length}건',
              child: pendingCards.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(22),
                      child: Text('없는 품목 초안이 없습니다. 카탈로그에 없으면 여기서 요청합니다.'),
                    )
                  : Column(
                      children: [
                        for (final draft in pendingCards)
                          ListTile(
                            leading: const Icon(Icons.hourglass_empty),
                            title: Text(draft.cardTitle),
                            subtitle: Text(
                              [
                                draft.category,
                                if ((draft.optionLabel ?? '').isNotEmpty) draft.optionLabel,
                                draft.hasSellablePrice
                                    ? formatWon(draft.priceCredits)
                                    : '가격 미입력',
                              ].join(' · '),
                            ),
                            onTap: () => _attachDraftPrice(draft),
                            trailing: const PortalStatusBadge(
                              label: '검수 대기',
                              attention: true,
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 14),
            PortalSection(
              title: '연결된 오퍼',
              child: _loading && _products.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(22),
                      child: Text('이 조건에 맞는 오퍼가 없습니다.'),
                    )
                  : Column(
                      children: [
                        for (final product in filtered)
                          ListTile(
                            leading: Icon(
                              product.stock <= 0
                                  ? Icons.inventory_outlined
                                  : Icons.inventory_2_outlined,
                            ),
                            title: Text(product.title),
                            subtitle: Text(sellerOfferRowSubtitle(product)),
                            onTap: () => _openDetail(product),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PortalStatusBadge(
                                  label: sellerOfferStatusLabel(product),
                                  attention:
                                      product.stock <= 0 ||
                                      product.status == 'draft' ||
                                      sellerOfferIsHidden(product),
                                ),
                                PopupMenuButton<String>(
                                  tooltip: '관리',
                                  onSelected: (value) =>
                                      _onQuickAction(product, value),
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Text('수정'),
                                    ),
                                    PopupMenuItem(
                                      value: sellerOfferIsHidden(product)
                                          ? 'unhide'
                                          : 'hide',
                                      child: Text(
                                        sellerOfferIsHidden(product)
                                            ? '숨김 해제'
                                            : '숨김',
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Text('삭제'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            Text(
              '오퍼는 기존 카드에 초안으로만 붙입니다. 없는 품목은 카드 초안이며, 목록에는 MD 검수 뒤에 올라갑니다.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferFilterChip extends StatelessWidget {
  const _OfferFilterChip({
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
