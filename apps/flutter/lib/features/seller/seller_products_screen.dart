import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/price_format.dart';
import '../../core/network/api_exception.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/async_busy.dart';
import '../../shared/widgets/portal_workspace.dart';

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
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      final items = await api.sellerProducts();
      var drafts = <IntakeDraftModel>[];
      try {
        drafts = await api.sellerCardDrafts();
      } on ApiException {
        drafts = [];
      }
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
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openRegister() async {
    if (isBusy('register')) return;
    final picked = await showDialog<CatalogProductModel>(
      context: context,
      builder: (ctx) => const _CatalogSearchDialog(),
    );
    if (picked == null || !mounted) return;
    await runBusy('register', () => _registerOffer(picked));
  }

  Future<void> _openCardDraft() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _CardDraftDialog(),
    );
    if (ok == true && mounted) await _load();
  }

  Future<void> _registerOffer(CatalogProductModel catalog) async {
    final options = catalog.volumeOptions;
    String? volume = options.isEmpty ? null : options.first;
    final volumeController = TextEditingController();
    final priceController = TextEditingController(text: '1000');
    final stockController = TextEditingController(text: '10');
    final imageController = TextEditingController();
    final flavorController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(catalog.cardTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${catalog.category} · MD 검수 후 카드에 붙습니다.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (options.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: volume,
                    decoration: const InputDecoration(labelText: '용량'),
                    items: [
                      for (final option in options)
                        DropdownMenuItem(value: option, child: Text(option)),
                    ],
                    onChanged: (v) => setLocal(() => volume = v),
                  )
                else
                  TextField(
                    controller: volumeController,
                    decoration: const InputDecoration(
                      labelText: '용량·팩',
                      hintText: '100g',
                    ),
                  ),
                TextField(
                  controller: flavorController,
                  decoration: const InputDecoration(labelText: '맛 (선택)'),
                ),
                TextField(
                  controller: priceController,
                  decoration: const InputDecoration(labelText: '가격(원)'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: stockController,
                  decoration: const InputDecoration(labelText: '재고'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: imageController,
                  decoration: const InputDecoration(
                    labelText: '사진 URL',
                    hintText: 'https://',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('초안 제출'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;
    final optionLabel = options.isNotEmpty
        ? volume
        : volumeController.text.trim();
    if (optionLabel == null || optionLabel.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('용량을 고르세요.')));
      }
      return;
    }

    try {
      await ref
          .read(apiClientProvider)
          .sellerCreateProduct(
            title: catalog.title,
            priceCredits: int.parse(priceController.text),
            stock: int.parse(stockController.text),
            category: catalog.category,
            status: 'draft',
            catalogProductId: catalog.id,
            optionLabel: optionLabel,
            volumeMl: _volumeMlFromOption(optionLabel),
            flavor: flavorController.text.trim().isEmpty
                ? null
                : flavorController.text.trim(),
            imageUrl: imageController.text.trim().isEmpty
                ? null
                : imageController.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('오퍼 초안을 제출했습니다. MD 검수를 기다립니다.')));
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingOffers = _products.where((p) => p.status == 'draft').toList();
    final pendingCards = _cardDrafts.where((d) => d.isPending).toList();
    final filtered = _products.where((product) {
      return switch (_filter) {
        'published' => product.status == 'published' && product.stock > 0,
        'sold_out' => product.stock <= 0,
        'pending' => product.status == 'draft',
        'hidden' => product.status != 'published' && product.status != 'draft',
        _ => true,
      };
    }).toList();
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
              onPressed: _openCardDraft,
              icon: const Icon(Icons.playlist_add_outlined),
              label: const Text('없는 품목'),
            ),
            FilledButton.icon(
              onPressed: isBusy('register') ? null : _openRegister,
              icon: isBusy('register') ? busyProgress() : const Icon(Icons.add),
              label: Text(isBusy('register') ? '등록 중…' : '오퍼 초안'),
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
                  label: '품절 ${_products.where((p) => p.stock <= 0).length}',
                  selected: _filter == 'sold_out',
                  onSelected: () => setState(() => _filter = 'sold_out'),
                ),
                _OfferFilterChip(
                  label:
                      '숨김 ${_products.where((p) => p.status != 'published' && p.status != 'draft').length}',
                  selected: _filter == 'hidden',
                  onSelected: () => setState(() => _filter = 'hidden'),
                ),
              ],
            ),
            const SizedBox(height: 14),
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
                              '${draft.category} · '
                              '${formatWon(draft.priceCredits)} · '
                              '${draft.optionLabel ?? ''}',
                            ),
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
              child: _loading
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
                            subtitle: Text(
                              '${product.category} · '
                              '${formatWon(product.priceCredits)} · 재고 ${product.stock}',
                            ),
                            trailing: PortalStatusBadge(
                              label: _offerStatusLabel(product),
                              attention:
                                  product.stock <= 0 ||
                                  product.status == 'draft',
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

String _offerStatusLabel(ProductModel product) {
  if (product.stock <= 0) return '품절';
  return switch (product.status) {
    'published' => '공개',
    'draft' => '검수 대기',
    _ => '숨김',
  };
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

int? _volumeMlFromOption(String option) {
  final ml = RegExp(
    r'(\d+(?:\.\d+)?)\s*ml',
    caseSensitive: false,
  ).firstMatch(option);
  if (ml != null) return double.parse(ml.group(1)!).round();
  final liter = RegExp(
    r'(\d+(?:\.\d+)?)\s*l\b',
    caseSensitive: false,
  ).firstMatch(option);
  if (liter != null) return (double.parse(liter.group(1)!) * 1000).round();
  return null;
}

class _CardDraftDialog extends ConsumerStatefulWidget {
  const _CardDraftDialog();

  @override
  ConsumerState<_CardDraftDialog> createState() => _CardDraftDialogState();
}

class _CardDraftDialogState extends ConsumerState<_CardDraftDialog>
    with AsyncBusyState {
  final _manufacturer = TextEditingController();
  final _title = TextEditingController();
  final _category = TextEditingController();
  final _image = TextEditingController();
  final _flavor = TextEditingController();
  final _option = TextEditingController();
  final _price = TextEditingController(text: '1000');
  final _stock = TextEditingController(text: '10');

  @override
  void dispose() {
    _manufacturer.dispose();
    _title.dispose();
    _category.dispose();
    _image.dispose();
    _flavor.dispose();
    _option.dispose();
    _price.dispose();
    _stock.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (isBusy('submit')) return;
    final manufacturer = _manufacturer.text.trim();
    final title = _title.text.trim();
    final category = _category.text.trim();
    final option = _option.text.trim();
    if (manufacturer.isEmpty ||
        title.isEmpty ||
        category.isEmpty ||
        option.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('회사·품목명·종류·용량을 모두 적어 주세요.')),
      );
      return;
    }
    await runBusy('submit', () async {
      try {
        await ref.read(apiClientProvider).sellerCreateCardDraft(
          manufacturer: manufacturer,
          title: title,
          category: category,
          optionLabel: option,
          priceCredits: int.parse(_price.text),
          stock: int.parse(_stock.text),
          imageUrl: _image.text.trim().isEmpty ? null : _image.text.trim(),
          flavor: _flavor.text.trim().isEmpty ? null : _flavor.text.trim(),
          volumeMl: _volumeMlFromOption(option),
        );
        if (!mounted) return;
        Navigator.pop(context, true);
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
    return AlertDialog(
      title: const Text('없는 품목 카드 초안'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '공개 목록에 바로 올라가지 않습니다. MD가 기존 카드에 붙이거나 새 카드로 승격합니다.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              TextField(
                controller: _manufacturer,
                decoration: const InputDecoration(labelText: '회사'),
              ),
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: '품목명'),
              ),
              TextField(
                controller: _category,
                decoration: const InputDecoration(
                  labelText: '종류 (짐작)',
                  hintText: '생수, 떡갈비',
                ),
              ),
              TextField(
                controller: _image,
                decoration: const InputDecoration(labelText: '대표 사진 URL'),
              ),
              TextField(
                controller: _flavor,
                decoration: const InputDecoration(labelText: '맛 (선택)'),
              ),
              TextField(
                controller: _option,
                decoration: const InputDecoration(
                  labelText: '용량·팩',
                  hintText: '500g, 2L',
                ),
              ),
              TextField(
                controller: _price,
                decoration: const InputDecoration(labelText: '가격(원)'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: _stock,
                decoration: const InputDecoration(labelText: '재고'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: isBusy('submit') ? null : () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: isBusy('submit') ? null : _submit,
          child: isBusy('submit') ? busyProgress() : const Text('초안 제출'),
        ),
      ],
    );
  }
}

class _CatalogSearchDialog extends ConsumerStatefulWidget {
  const _CatalogSearchDialog();

  @override
  ConsumerState<_CatalogSearchDialog> createState() =>
      _CatalogSearchDialogState();
}

class _CatalogSearchDialogState extends ConsumerState<_CatalogSearchDialog> {
  final _q = TextEditingController();
  List<CatalogProductModel> _items = [];
  bool _loading = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _q.text.trim();
    if (q.isEmpty || _loading) return;
    setState(() => _loading = true);
    try {
      final items = await ref.read(apiClientProvider).sellerSearchCatalog(q: q);
      setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('품목 찾기'),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _q,
              decoration: const InputDecoration(
                labelText: '품목·제조사·분류',
                hintText: '김치, 만두, 풀무원',
              ),
              onSubmitted: _loading ? null : (_) => _search(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _loading ? null : _search,
                child: Text(_loading ? '검색 중…' : '검색'),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return ListTile(
                          title: Text(item.cardTitle),
                          subtitle: Text(
                            [
                              item.category,
                              if (item.volumeOptions.isNotEmpty)
                                item.volumeOptions.join(', '),
                            ].join(' · '),
                          ),
                          onTap: () => Navigator.pop(context, item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}
