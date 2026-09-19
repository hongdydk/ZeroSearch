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
import 'seller_visibility_row.dart';

class SellerProductsScreen extends ConsumerStatefulWidget {
  const SellerProductsScreen({super.key});

  @override
  ConsumerState<SellerProductsScreen> createState() =>
      _SellerProductsScreenState();
}

class _SellerProductsScreenState extends ConsumerState<SellerProductsScreen>
    with AsyncBusyState {
  static const _pageSize = 20;

  final _search = TextEditingController();
  List<ProductModel> _products = [];
  List<IntakeDraftModel> _cardDrafts = [];
  SellerProductCounts _counts = const SellerProductCounts();
  int _total = 0;
  int _offset = 0;
  bool _loading = true;
  bool _reloading = false;
  String _filter = 'all';
  String _sort = 'newest';
  String _appliedQuery = '';
  final Set<String> _selectedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
      final draftsFuture = () async {
        try {
          return await api.sellerCardDrafts();
        } on ApiException {
          return <IntakeDraftModel>[];
        }
      }();
      final results = await Future.wait([
        api.sellerProducts(
          q: _appliedQuery.isEmpty ? null : _appliedQuery,
          filter: _filter,
          sort: _sort,
          offset: _offset,
          limit: _pageSize,
        ),
        draftsFuture,
      ]);
      final page = results[0] as SellerProductListPage;
      final drafts = results[1] as List<IntakeDraftModel>;
      if (!mounted) return;
      setState(() {
        _products = page.items;
        _total = page.total;
        _counts = page.counts;
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

  void _applySearch() {
    final next = _search.text.trim();
    if (next == _appliedQuery && _offset == 0) {
      _load(silent: true);
      return;
    }
    setState(() {
      _appliedQuery = next;
      _offset = 0;
    });
    _load(silent: true);
  }

  void _setFilter(String filter) {
    if (_filter == filter) return;
    setState(() {
      _filter = filter;
      _offset = 0;
    });
    _load(silent: true);
  }

  void _setSort(String sort) {
    if (_sort == sort) return;
    setState(() {
      _sort = sort;
      _offset = 0;
    });
    _load(silent: true);
  }

  void _goPage(int offset) {
    if (offset < 0 || offset == _offset) return;
    setState(() => _offset = offset);
    _load(silent: true);
  }

  void _toggleSelected(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedIds.add(id);
      } else {
        _selectedIds.remove(id);
      }
    });
  }

  Future<bool> _confirmBulk(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('적용'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _bulkSetPrice() async {
    if (_selectedIds.isEmpty) return;
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('가격 일괄'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${_selectedIds.length}건의 가격을 같은 값으로 바꿉니다.'),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: '가격(원)'),
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
            child: const Text('적용'),
          ),
        ],
      ),
    );
    final text = controller.text.trim();
    if (ok != true || !mounted) return;
    final price = int.tryParse(text);
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('가격을 숫자로 입력하세요.')),
      );
      return;
    }
    await _applyBulk(priceCredits: price);
  }

  Future<void> _bulkSoldOut() async {
    if (_selectedIds.isEmpty) return;
    final ok = await _confirmBulk(
      '품절',
      '${_selectedIds.length}건의 재고를 0으로 바꿀까요?',
    );
    if (!ok || !mounted) return;
    await _applyBulk(stock: 0);
  }

  Future<void> _bulkHide() async {
    if (_selectedIds.isEmpty) return;
    final ok = await _confirmBulk('숨김', '${_selectedIds.length}건을 숨길까요?');
    if (!ok || !mounted) return;
    await _applyBulk(status: 'archived');
  }

  Future<void> _bulkUnhide() async {
    if (_selectedIds.isEmpty) return;
    final ok = await _confirmBulk(
      '숨김 해제',
      '${_selectedIds.length}건의 숨김을 해제할까요?',
    );
    if (!ok || !mounted) return;
    await _applyBulk(status: 'published');
  }

  Future<void> _applyBulk({
    int? priceCredits,
    int? stock,
    String? status,
  }) async {
    if (_selectedIds.isEmpty || isBusy('bulk')) return;
    final ids = _selectedIds.toList();
    if (ids.length > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('한 번에 100건까지 적용할 수 있습니다.')),
      );
      return;
    }
    await runBusy('bulk', () async {
      try {
        final result = await ref.read(apiClientProvider).sellerBulkUpdateProducts(
          ids: ids,
          priceCredits: priceCredits,
          stock: stock,
          status: status,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              sellerOfferBulkSummary(
                successCount: result.successCount,
                failDetails: [for (final row in result.failed) row.detail],
              ),
            ),
          ),
        );
        setState(_selectedIds.clear);
        await _load(silent: true);
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    });
  }

  Widget _buildBulkBar() {
    final pageIds = _products.map((p) => p.id).toSet();
    final selectedOnPage = pageIds.intersection(_selectedIds);
    final bool? pageValue;
    if (pageIds.isEmpty || selectedOnPage.isEmpty) {
      pageValue = false;
    } else if (selectedOnPage.length == pageIds.length) {
      pageValue = true;
    } else {
      pageValue = null;
    }
    final selectedCount = _selectedIds.length;
    final bulkBusy = isBusy('bulk');
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    key: const ValueKey('select-offer-page'),
                    tristate: true,
                    value: pageValue,
                    onChanged: bulkBusy
                        ? null
                        : (_) {
                            setState(() {
                              if (pageValue == true) {
                                _selectedIds.removeAll(pageIds);
                              } else {
                                _selectedIds.addAll(pageIds);
                              }
                            });
                          },
                  ),
                  const Text('이 페이지'),
                ],
              ),
              if (selectedCount > 0) Text('$selectedCount건 선택'),
              if (selectedCount > 0)
                TextButton(
                  onPressed: bulkBusy
                      ? null
                      : () => setState(_selectedIds.clear),
                  child: const Text('선택 해제'),
                ),
            ],
          ),
          if (selectedCount > 0) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: bulkBusy ? null : _bulkSetPrice,
                  child: const Text('가격'),
                ),
                OutlinedButton(
                  onPressed: bulkBusy ? null : _bulkSoldOut,
                  child: const Text('품절'),
                ),
                OutlinedButton(
                  onPressed: bulkBusy ? null : _bulkHide,
                  child: const Text('숨김'),
                ),
                OutlinedButton(
                  onPressed: bulkBusy ? null : _bulkUnhide,
                  child: const Text('숨김 해제'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
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
    var isPublic = draft.isPublic;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
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
              SellerVisibilityRow(
                isPublic: isPublic,
                onChanged: (value) => setDialogState(() => isPublic = value),
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
        visibility: isPublic ? 'public' : 'hidden',
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
        await _load(silent: true);
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
        content: const Text('오퍼를 영구 삭제합니다. 되돌릴 수 없습니다. 기존 주문과 판매 기록은 유지됩니다.'),
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
          _products = [for (final row in _products) if (row.id != product.id) row];
          _selectedIds.remove(product.id);
        });
        await _load(silent: true);
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
    final pendingCards = _cardDrafts.where((d) => d.isPending).toList();
    final emptyCopy = sellerOffersEmptyCopy(
      hasAnyOffers: _filter != 'all' || _appliedQuery.isNotEmpty || _total > 0,
      hasQuery: _appliedQuery.isNotEmpty || _filter != 'all',
    );
    return PortalWorkspaceScaffold(
      role: PortalWorkspaceRole.seller,
      activePath: '/seller/products',
      child: PortalPage(
        eyebrow: '판매자 센터',
        title: '내 카탈로그',
        trailing: Wrap(
          spacing: 8,
          children: [
            IconButton(
              tooltip: '새로고침',
              onPressed: () => _load(silent: true),
              icon: const Icon(Icons.refresh),
            ),
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
            Material(
              type: MaterialType.transparency,
              child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 280,
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      labelText: '제목·용량 검색',
                      hintText: '백산수, 500ml',
                    ),
                    onSubmitted: (_) => _applySearch(),
                  ),
                ),
                FilledButton(
                  onPressed: _applySearch,
                  child: const Text('검색'),
                ),
                DropdownButton<String>(
                  value: _sort,
                  onChanged: (value) {
                    if (value == null) return;
                    _setSort(value);
                  },
                  items: const [
                    DropdownMenuItem(value: 'newest', child: Text('최신순')),
                    DropdownMenuItem(value: 'price', child: Text('가격순')),
                    DropdownMenuItem(value: 'stock', child: Text('재고순')),
                  ],
                ),
              ],
            ),
            ),
            const SizedBox(height: 12),
            Material(
              type: MaterialType.transparency,
              child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _OfferFilterChip(
                  label: '전체 ${_counts.all}',
                  selected: _filter == 'all',
                  onSelected: () => _setFilter('all'),
                ),
                _OfferFilterChip(
                  label: '공개 ${_counts.published}',
                  selected: _filter == 'published',
                  onSelected: () => _setFilter('published'),
                ),
                _OfferFilterChip(
                  label: '검수 대기 ${_counts.pending}',
                  selected: _filter == 'pending',
                  onSelected: () => _setFilter('pending'),
                ),
                _OfferFilterChip(
                  label: '품절 ${_counts.soldOut}',
                  selected: _filter == 'sold_out',
                  onSelected: () => _setFilter('sold_out'),
                ),
                _OfferFilterChip(
                  label: '숨김 ${_counts.hidden}',
                  selected: _filter == 'hidden',
                  onSelected: () => _setFilter('hidden'),
                ),
              ],
            ),
            ),
            const SizedBox(height: 14),
            if (_reloading) ...[
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 14),
            ],
            PortalSection(
              title: '카드 초안 ${pendingCards.length}건',
              trailing: IconButton(
                tooltip: '검수 상태 새로고침',
                onPressed: () => _load(silent: true),
                icon: const Icon(Icons.refresh),
              ),
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
                  : _products.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(22),
                      child: Text(emptyCopy),
                    )
                  : Column(
                      children: [
                        _buildBulkBar(),
                        for (final product in _products)
                          ListTile(
                            leading: Checkbox(
                              key: ValueKey('select-offer-${product.id}'),
                              value: _selectedIds.contains(product.id),
                              onChanged: isBusy('bulk')
                                  ? null
                                  : (value) => _toggleSelected(
                                      product.id,
                                      value ?? false,
                                    ),
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
                        if (_total > _products.length || _offset > 0)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                            child: Row(
                              children: [
                                Text(
                                  '${_offset + 1}–${_offset + _products.length} / $_total',
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: _offset > 0
                                      ? () => _goPage(
                                          (_offset - _pageSize).clamp(0, _offset),
                                        )
                                      : null,
                                  child: const Text('이전'),
                                ),
                                TextButton(
                                  onPressed:
                                      _offset + _products.length < _total
                                      ? () => _goPage(_offset + _pageSize)
                                      : null,
                                  child: const Text('다음'),
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
