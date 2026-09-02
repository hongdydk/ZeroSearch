import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';



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

    final categoryController = TextEditingController(text: 'accessories');



    final ok = await showDialog<bool>(

      context: context,

      builder: (ctx) => AlertDialog(

        title: const Text('상품 등록'),

        content: Column(

          mainAxisSize: MainAxisSize.min,

          children: [

            TextField(controller: titleController, decoration: const InputDecoration(labelText: '상품명')),

            TextField(controller: priceController, decoration: const InputDecoration(labelText: '가격(크레딧)')),

            TextField(controller: stockController, decoration: const InputDecoration(labelText: '재고')),

            TextField(controller: categoryController, decoration: const InputDecoration(labelText: '카테고리')),

          ],

        ),

        actions: [

          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),

          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('등록')),

        ],

      ),

    );



    if (ok != true) return;



    try {

      await ref.read(apiClientProvider).sellerCreateProduct(

            title: titleController.text.trim(),

            priceCredits: int.parse(priceController.text),

            stock: int.parse(stockController.text),

            category: categoryController.text.trim(),

            status: 'published',

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

              Expanded(child: Text('내 상품', style: Theme.of(context).textTheme.headlineSmall)),

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

            const Center(child: Text('등록된 상품이 없습니다.'))

          else

            ..._products.map(

              (p) => ListTile(

                title: Text(p.title),

                subtitle: Text('${p.status} · 💎 ${p.priceCredits} · 재고 ${p.stock}'),

              ),

            ),

        ],

      ),

    );

  }

}


