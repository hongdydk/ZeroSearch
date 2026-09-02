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

  Future<void> _createProduct() async {
    final titleController = TextEditingController();
    final priceController = TextEditingController(text: '10');
    final stockController = TextEditingController(text: '10');
    final categoryController = TextEditingController(text: '생수');
    final catalogIdController = TextEditingController();
    final optionLabelController = TextEditingController();
    final volumeMlController = TextEditingController();
    final flavorController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('오퍼 등록'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: '상품명(브랜드)'),
              ),
              TextField(
                controller: catalogIdController,
                decoration: const InputDecoration(
                  labelText: '대표상품 ID (선택)',
                  hintText: '비우면 상품명으로 매칭/생성',
                ),
              ),
              TextField(
                controller: optionLabelController,
                decoration: const InputDecoration(labelText: '옵션 라벨', hintText: '500ml × 20'),
              ),
              TextField(
                controller: volumeMlController,
                decoration: const InputDecoration(labelText: '총 용량(ml)', hintText: '10000'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: flavorController,
                decoration: const InputDecoration(labelText: '맛 (선택)', hintText: '레몬'),
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
                controller: categoryController,
                decoration: const InputDecoration(labelText: '카테고리'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('등록')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final volumeRaw = volumeMlController.text.trim();
      await ref.read(apiClientProvider).sellerCreateProduct(
            title: titleController.text.trim(),
            priceCredits: int.parse(priceController.text),
            stock: int.parse(stockController.text),
            category: categoryController.text.trim(),
            status: 'published',
            catalogProductId: catalogIdController.text.trim().isEmpty
                ? null
                : catalogIdController.text.trim(),
            optionLabel: optionLabelController.text.trim().isEmpty
                ? null
                : optionLabelController.text.trim(),
            volumeMl: volumeRaw.isEmpty ? null : int.parse(volumeRaw),
            flavor: flavorController.text.trim().isEmpty ? null : flavorController.text.trim(),
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
                onPressed: _createProduct,
                icon: const Icon(Icons.add),
                label: const Text('등록'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_products.isEmpty)
            const Center(child: Text('등록된 오퍼가 없습니다.'))
          else
            ..._products.map(
              (p) => ListTile(
                title: Text(p.title),
                subtitle: Text('${p.status} · ${formatWon(p.priceCredits)} · 재고 ${p.stock}'),
              ),
            ),
        ],
      ),
    );
  }
}
