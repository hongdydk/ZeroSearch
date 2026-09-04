import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/price_format.dart';
import '../../core/layout/ui_platform.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/routing/app_back_navigation.dart';
import '../../core/theme/app_theme.dart';
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
    final category = ref.watch(catalogCategoryProvider);
    final flavor = ref.watch(catalogFlavorFilterProvider);
    final volumeMin = ref.watch(catalogVolumeMinFilterProvider);
    final tokens = mallTokensOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final columns = isWebUi
        ? (width < webCompactBreakpoint ? 2 : tokens.productGridColumns)
        : 2;
    final aspectRatio = isWebUi ? (width < webCompactBreakpoint ? 0.82 : 0.76) : 0.68;
    final padding = EdgeInsets.all(isWebUi ? 20 : 16);
    final isLanding = search.isEmpty && category == null;

    return catalogAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('상품을 불러오지 못했습니다: $e')),
      data: (items) {
        if (isLanding) {
          return _LandingView(
            items: items,
            padding: padding,
            onPickCategory: (c) {
              ref.read(catalogFlavorFilterProvider.notifier).state = null;
              ref.read(catalogVolumeMinFilterProvider.notifier).state = null;
              ref.read(catalogCategoryProvider.notifier).state = c;
            },
            onSearchChanged: (v) => ref.read(catalogSearchProvider.notifier).state = v,
          );
        }

        final bannerText = category != null
            ? '“$category” · 같은 회사·품목은 카드 1장, 상세에서 오퍼를 비교합니다.'
            : '“$search” 검색 — 같은 회사·품목은 카드 1장, 상세에서 오퍼를 비교합니다.';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isWebUi) ...[
              Padding(
                padding: padding.copyWith(bottom: 0),
                child: Text(
                  category ?? '검색',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              Padding(
                padding: padding.copyWith(top: 12, bottom: 0),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: '밥, 떡, 쌀…',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => ref.read(catalogSearchProvider.notifier).state = v,
                ),
              ),
            ],
            Padding(
              padding: padding.copyWith(bottom: 0, top: isWebUi ? padding.top : 12),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      ref.read(catalogCategoryProvider.notifier).state = null;
                      ref.read(catalogSearchProvider.notifier).state = '';
                      ref.read(catalogFlavorFilterProvider.notifier).state = null;
                      ref.read(catalogVolumeMinFilterProvider.notifier).state = null;
                    },
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('식탁'),
                  ),
                  if (category != null)
                    Text(
                      category,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.brandTeal,
                          ),
                    ),
                ],
              ),
            ),
            if (isWebUi)
              Padding(
                padding: padding.copyWith(top: 8, bottom: 0),
                child: MallInfoBanner(text: bannerText),
              ),
            Padding(
              padding: padding.copyWith(top: 12, bottom: 0),
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
                      padding: padding.copyWith(top: 16),
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

class _LandingView extends StatelessWidget {
  const _LandingView({
    required this.items,
    required this.padding,
    required this.onPickCategory,
    required this.onSearchChanged,
  });

  final List<CatalogProductModel> items;
  final EdgeInsets padding;
  final ValueChanged<String> onPickCategory;
  final ValueChanged<String> onSearchChanged;

  List<_TableEntry> _tablesFrom(List<CatalogProductModel> items) {
    final seen = <String>{};
    final out = <_TableEntry>[];
    for (final item in items) {
      final c = item.category.trim();
      if (c.isEmpty || seen.contains(c)) continue;
      seen.add(c);
      out.add(_TableEntry(category: c, imageUrl: item.imageUrl));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final tables = _tablesFrom(items);
    final today = tables.take(4).toList();

    return ListView(
      padding: padding,
      children: [
        if (!isWebUi) ...[
          TextField(
            decoration: const InputDecoration(
              hintText: '밥, 떡, 쌀…',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: 20),
        ],
        Text(
          '식탁',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppTheme.brandTeal,
                letterSpacing: -0.4,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          '밥 · 떡 · 쌀. 먼저 식탁을 고릅니다.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        if (tables.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('표시할 식탁이 없습니다.')),
          )
        else
          SizedBox(
            height: 108,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tables.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final t = tables[index];
                return _TableCircle(
                  entry: t,
                  onTap: () => onPickCategory(t.category),
                );
              },
            ),
          ),
        const SizedBox(height: 32),
        Text(
          '오늘 추천',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppTheme.brandTeal,
                letterSpacing: -0.4,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          '지금 식탁에 올리기 좋은.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        if (today.isEmpty)
          const SizedBox.shrink()
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = isWebUi
                  ? (constraints.maxWidth < webCompactBreakpoint ? 2 : 4)
                  : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  childAspectRatio: isWebUi ? 0.85 : 0.78,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                ),
                itemCount: today.length,
                itemBuilder: (context, index) {
                  final t = today[index];
                  return _TodayCard(
                    entry: t,
                    tag: index == 0 ? '지금 많이' : '오늘',
                    onTap: () => onPickCategory(t.category),
                  );
                },
              );
            },
          ),
        const SizedBox(height: 32),
        Text(
          '대표가는 최저가가 아닙니다',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppTheme.brandTeal,
              ),
        ),
        const SizedBox(height: 8),
        MallInfoBanner(
          text: '식탁 안 카드 가격은 단위당 중간값입니다. 용량·가게는 상세 오퍼에서만 고릅니다.',
        ),
      ],
    );
  }
}

class _TableEntry {
  const _TableEntry({required this.category, this.imageUrl});

  final String category;
  final String? imageUrl;
}

class _TableCircle extends StatelessWidget {
  const _TableCircle({required this.entry, required this.onTap});

  final _TableEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 80,
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x14074A4E)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0F074A4E),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: entry.imageUrl != null && entry.imageUrl!.isNotEmpty
                  ? ProductImage(imageUrl: entry.imageUrl, title: entry.category)
                  : ColoredBox(
                      color: const Color(0xFFEFF5F5),
                      child: Center(
                        child: Text(
                          entry.category.isNotEmpty ? entry.category.substring(0, 1) : '?',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.brandTeal,
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              entry.category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.brandTeal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.entry,
    required this.tag,
    required this.onTap,
  });

  final _TableEntry entry;
  final String tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: entry.imageUrl != null && entry.imageUrl!.isNotEmpty
                  ? ProductImage(imageUrl: entry.imageUrl, title: entry.category)
                  : const ColoredBox(
                      color: Color(0xFFEFF5F5),
                      child: Center(
                        child: Icon(Icons.restaurant, color: AppTheme.brandTeal, size: 36),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0x14074A4E),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.brandTeal,
                      ),
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
                          color: AppTheme.priceBurgundy,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '오퍼 ${item.offerCount}',
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
          colors: [Color(0xFFD5E2E0), Color(0xFFEFF5F5)],
        ),
      ),
      child: Center(
        child: Text(
          item.title.isNotEmpty ? item.title.substring(0, 1) : '?',
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w600,
            color: AppTheme.brandTeal,
          ),
        ),
      ),
    );
  }
}
