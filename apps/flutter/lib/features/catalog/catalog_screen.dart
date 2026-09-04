import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/price_format.dart';
import '../../core/layout/ui_platform.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/routing/app_back_navigation.dart';
import '../../core/theme/mall_tokens.dart';
import '../../shared/widgets/mall_info_banner.dart';
import '../../shared/widgets/product_image.dart';

class CatalogScreen extends ConsumerWidget {
  const CatalogScreen({super.key});

  static const _flavorOptions = ['레몬', '자몽'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(catalogProductsProvider);
    final search = ref.watch(catalogSearchProvider).trim();
    final flavor = ref.watch(catalogFlavorFilterProvider);
    final volumeMin = ref.watch(catalogVolumeMinFilterProvider);
    final tokens = mallTokensOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final columns = isWebUi
        ? (width < webCompactBreakpoint ? 2 : tokens.productGridColumns)
        : 2;
    final aspectRatio = isWebUi ? (width < webCompactBreakpoint ? 0.82 : 0.76) : 0.68;
    final padding = EdgeInsets.all(isWebUi ? 20 : 16);

    return catalogAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('상품을 불러오지 못했습니다: $e')),
      data: (items) {
        final bannerText = search.isEmpty
            ? '같은 회사·품목은 카드 1장 · L당 대표가(보통)만 표시합니다.'
            : '“$search” 검색 — 같은 회사·품목은 카드 1장, 상세에서 오퍼를 비교합니다.';

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
            if (isWebUi)
              Padding(
                padding: padding.copyWith(bottom: 0),
                child: MallInfoBanner(text: bannerText),
              ),
            Padding(
              padding: padding.copyWith(top: isWebUi ? 12 : 8, bottom: 0),
              child: _FilterChips(
                flavor: flavor,
                volumeMin: volumeMin,
                onFlavor: (v) => ref.read(catalogFlavorFilterProvider.notifier).state = v,
                onVolumeMin: (v) => ref.read(catalogVolumeMinFilterProvider.notifier).state = v,
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('표시할 상품이 없습니다.'))
                  : GridView.builder(
                      padding: padding.copyWith(top: isWebUi ? 16 : padding.top),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        childAspectRatio: aspectRatio,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        return _CatalogCard(item: items[index]);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.flavor,
    required this.volumeMin,
    required this.onFlavor,
    required this.onVolumeMin,
  });

  final String? flavor;
  final int? volumeMin;
  final ValueChanged<String?> onFlavor;
  final ValueChanged<int?> onVolumeMin;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilterChip(
          label: const Text('전체'),
          selected: flavor == null && volumeMin == null,
          onSelected: (_) {
            onFlavor(null);
            onVolumeMin(null);
          },
        ),
        ...CatalogScreen._flavorOptions.map(
          (f) => FilterChip(
            label: Text(f),
            selected: flavor == f,
            onSelected: (selected) => onFlavor(selected ? f : null),
          ),
        ),
        FilterChip(
          label: const Text('2L 이상'),
          selected: volumeMin == 2000,
          onSelected: (selected) => onVolumeMin(selected ? 2000 : null),
        ),
      ],
    );
  }
}

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({required this.item});

  final CatalogProductModel item;

  @override
  Widget build(BuildContext context) {
    final priceLabel = formatCatalogRepresentativePrice(
      priceUnit: item.priceUnit,
      displayPriceLabel: item.displayPriceLabel,
      medianUnitPrice: item.medianUnitPrice,
      medianPriceCredits: item.medianPriceCredits,
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openDetailRoute(context, '/catalog/${item.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _CardThumb(item: item),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.cardTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    priceLabel,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '판매 ${item.offerCount}건',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _CardThumb extends StatelessWidget {
  const _CardThumb({required this.item});

  final CatalogProductModel item;

  @override
  Widget build(BuildContext context) {
    if (item.imageUrl != null && item.imageUrl!.isNotEmpty) {
      return ProductImage(imageUrl: item.imageUrl, title: item.title);
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFDBEAFE), Color(0xFFE0F2FE)],
        ),
      ),
      child: Center(
        child: Text(
          item.title.isNotEmpty ? item.title.substring(0, 1) : '?',
          style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w600, color: Color(0xFF2563EB)),
        ),
      ),
    );
  }
}
