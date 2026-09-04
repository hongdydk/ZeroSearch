import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/price_format.dart';
import '../../core/network/api_exception.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/page_form_scaffold.dart';

class SellerProductsScreen extends ConsumerStatefulWidget {
  const SellerProductsScreen({super.key});

  @override
  ConsumerState<SellerProductsScreen> createState() => _SellerProductsScreenState();
}

class _SellerProductsScreenState extends ConsumerState<SellerProductsScreen> {
  List<ProductModel> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await ref.read(apiClientProvider).sellerProducts();
      setState(() => _products = items);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openRegister() async {
    final picked = await showDialog<CatalogProductModel>(
      context: context,
      builder: (ctx) => const _CatalogSearchDialog(),
    );
    if (picked == null || !mounted) return;
    await _registerOffer(picked);
  }

  Future<void> _registerOffer(CatalogProductModel catalog) async {
    final options = catalog.volumeOptions;
    String? volume = options.isEmpty ? null : options.first;
    final volumeController = TextEditingController();
    final priceController = TextEditingController(text: '1000');
    final stockController = TextEditingController(text: '10');

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
                Text(catalog.category, style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: 12),
                if (options.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: volume,
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
                    decoration: const InputDecoration(labelText: '용량', hintText: '100g'),
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
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('등록')),
          ],
        ),
      ),
    );

    if (ok != true) return;
    final optionLabel = options.isNotEmpty ? volume : volumeController.text.trim();
    if (optionLabel == null || optionLabel.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('용량을 고르세요.')),
        );
      }
      return;
    }

    try {
      await ref.read(apiClientProvider).sellerCreateProduct(
            title: catalog.title,
            priceCredits: int.parse(priceController.text),
            stock: int.parse(stockController.text),
            category: catalog.category,
            status: 'published',
            catalogProductId: catalog.id,
            optionLabel: optionLabel,
            volumeMl: _volumeMlFromOption(optionLabel),
          );
      await _load();
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
          Row(
            children: [
              Expanded(child: Text('내 오퍼', style: Theme.of(context).textTheme.headlineSmall)),
              FilledButton.icon(
                onPressed: _openRegister,
                icon: const Icon(Icons.add),
                label: const Text('등록'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_products.isEmpty)
            const Center(child: Text('등록된 오퍼가 없습니다. 품목을 찾아 용량을 고르세요.'))
          else
            ..._products.map(
              (p) => ListTile(
                title: Text(p.title),
                subtitle: Text(
                  '${p.status} · ${formatWon(p.priceCredits)} · 재고 ${p.stock}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

int? _volumeMlFromOption(String option) {
  final ml = RegExp(r'(\d+(?:\.\d+)?)\s*ml', caseSensitive: false).firstMatch(option);
  if (ml != null) return double.parse(ml.group(1)!).round();
  final liter = RegExp(r'(\d+(?:\.\d+)?)\s*l\b', caseSensitive: false).firstMatch(option);
  if (liter != null) return (double.parse(liter.group(1)!) * 1000).round();
  return null;
}

class _CatalogSearchDialog extends ConsumerStatefulWidget {
  const _CatalogSearchDialog();

  @override
  ConsumerState<_CatalogSearchDialog> createState() => _CatalogSearchDialogState();
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
    if (q.isEmpty) return;
    setState(() => _loading = true);
    try {
      final items = await ref.read(apiClientProvider).sellerSearchCatalog(q: q);
      setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: _search, child: const Text('검색')),
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기')),
      ],
    );
  }
}
