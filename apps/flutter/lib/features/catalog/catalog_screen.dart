import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/ui_platform.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/routing/app_back_navigation.dart';
import '../../core/theme/mall_tokens.dart';
import '../../shared/widgets/product_image.dart';
import '../../shared/widgets/seller_badge.dart';

class CatalogScreen extends ConsumerWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);
    final search = ref.watch(catalogSearchProvider).trim().toLowerCase();
    final tokens = mallTokensOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final columns = isWebUi
        ? (width < webCompactBreakpoint ? 2 : tokens.productGridColumns)
        : 2;
    final aspectRatio = isWebUi ? (width < webCompactBreakpoint ? 0.85 : 0.72) : 0.68;
    final padding = EdgeInsets.all(isWebUi ? 20 : 16);

    return productsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('상품을 불러오지 못했습니다: $e')),
      data: (products) {
        final filtered = search.isEmpty
            ? products
            : products.where((p) {
                return p.title.toLowerCase().contains(search) ||
                    p.category.toLowerCase().contains(search) ||
                    (p.description?.toLowerCase().contains(search) ?? false);
              }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isWebUi) ...[
              Padding(
                padding: padding.copyWith(bottom: 0),
                child: Text('상품', style: Theme.of(context).textTheme.headlineSmall),
              ),
              Padding(
                padding: padding.copyWith(top: 12, bottom: 0),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: '상품명·카테고리 검색',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => ref.read(catalogSearchProvider.notifier).state = v,
                ),
              ),
            ],
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('표시할 상품이 없습니다.'))
                  : GridView.builder(
                      padding: padding,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        childAspectRatio: aspectRatio,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        return _ProductCard(product: filtered[index]);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});

  final ProductModel product;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openDetailRoute(context, '/products/${product.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ProductImage(imageUrl: product.imageUrl, title: product.title),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    product.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  SellerBadge(
                    shopName: product.seller.shopName,
                    isOfficial: product.isOfficial,
                  ),
                  Text(
                    '💎 ${product.priceCredits}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
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
