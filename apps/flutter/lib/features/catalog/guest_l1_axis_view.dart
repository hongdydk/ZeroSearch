import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/guest_l1.dart';
import '../../core/format/price_format.dart';
import '../../core/layout/ui_platform.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/routing/app_back_navigation.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/product_image.dart';
import '../../shared/widgets/seller_badge.dart';

class GuestL1AxisView extends ConsumerWidget {
  const GuestL1AxisView({
    super.key,
    required this.title,
    required this.axis,
    required this.storage,
    required this.padding,
    required this.onBack,
    required this.onAxis,
    required this.onStorage,
    required this.onPickBrand,
    required this.onPickMenu,
    required this.onSeeAll,
    this.showStorage = true,
    this.seeAllLabel = '이 분류 전체 보기',
  });

  final String title;
  final String axis;
  final String? storage;
  final EdgeInsets padding;
  final VoidCallback onBack;
  final ValueChanged<String> onAxis;
  final ValueChanged<String?> onStorage;
  final ValueChanged<String> onPickBrand;
  final ValueChanged<String> onPickMenu;
  final VoidCallback onSeeAll;
  final bool showStorage;
  final String seeAllLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sellerAxis = isSellerBrowseAxis(axis);
    return ListView(
      padding: padding,
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('홈'),
            ),
            Expanded(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.brandTeal,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          sellerAxis
              ? '판매자 오퍼는 가게·가격이 보이는 한 장입니다. 같은 품목이어도 판매자마다 카드가 갈라집니다.'
              : '브랜드 또는 메뉴로 좁히면 그 안의 회사+품목 카드가 나옵니다. 겹치는 1차 태그는 그대로입니다.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xA0212121),
              ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: kBrowseAxisBrand, label: Text('브랜드부터')),
              ButtonSegment(value: kBrowseAxisMenu, label: Text('메뉴부터')),
              ButtonSegment(value: kBrowseAxisSeller, label: Text('판매자 오퍼')),
            ],
            selected: {normalizeBrowseAxis(axis)},
            onSelectionChanged: (next) {
              if (next.isEmpty) return;
              onAxis(next.first);
            },
          ),
        ),
        if (showStorage) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('보관 전체'),
                selected: storage == null,
                onSelected: (_) => onStorage(null),
              ),
              ...kGuestL1StorageFilters.map(
                (value) => FilterChip(
                  label: Text(value),
                  selected: storage == value,
                  onSelected: (selected) => onStorage(selected ? value : null),
                ),
              ),
            ],
          ),
        ],
        if (!sellerAxis) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onSeeAll,
              child: Text(seeAllLabel),
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (sellerAxis)
          const _SellerOfferResults()
        else
          _BrandMenuFacets(
            axis: axis,
            onPickBrand: onPickBrand,
            onPickMenu: onPickMenu,
          ),
      ],
    );
  }
}

class _BrandMenuFacets extends ConsumerWidget {
  const _BrandMenuFacets({
    required this.axis,
    required this.onPickBrand,
    required this.onPickMenu,
  });

  final String axis;
  final ValueChanged<String> onPickBrand;
  final ValueChanged<String> onPickMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facetsAsync = ref.watch(guestL1FacetsProvider);
    return facetsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: Text('목록을 불러오지 못했습니다.')),
      ),
      data: (facets) {
        final items = axis == kBrowseAxisMenu
            ? (facets?.menus ?? const <GuestL1FacetItem>[])
            : (facets?.brands ?? const <GuestL1FacetItem>[]);
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('이 분류에 아직 상품이 없습니다.')),
          );
        }
        final width = MediaQuery.sizeOf(context).width;
        final cols = width < webCompactBreakpoint
            ? 2
            : (width < 900 ? 3 : (width < 1200 ? 4 : 5));
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: 1.7,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: Color(0x14074A4E)),
              ),
              child: InkWell(
                onTap: () => axis == kBrowseAxisMenu
                    ? onPickMenu(item.name)
                    : onPickBrand(item.name),
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.brandTeal,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '카드 ${item.count}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xA0212121),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SellerOfferResults extends ConsumerWidget {
  const _SellerOfferResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offersAsync = ref.watch(catalogOffersProvider);
    return offersAsync.when(
      skipLoadingOnReload: true,
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('오퍼를 불러오지 못했습니다.'),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.invalidate(catalogOffersProvider),
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      ),
      data: (page) {
        if (page.items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('이 분류에 공개 오퍼가 없습니다.')),
          );
        }
        final width = MediaQuery.sizeOf(context).width;
        final cols = width < webCompactBreakpoint
            ? 2
            : (width < 900 ? 3 : (width < 1200 ? 4 : 5));
        return Column(
          children: [
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: page.items.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                childAspectRatio: 0.78,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (context, index) =>
                  _OfferCard(item: page.items[index]),
            ),
            if (page.hasMore || page.loadingMore)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: page.loadingMore
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton(
                        onPressed: () =>
                            ref.read(catalogOffersProvider.notifier).loadMore(),
                        child: const Text('더 보기'),
                      ),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text('모두 불러왔습니다.')),
              ),
          ],
        );
      },
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.item});

  final CatalogOfferBrowseModel item;

  @override
  Widget build(BuildContext context) {
    final option = item.optionLine;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openDetailRoute(context, '/products/${item.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                  ? ProductImage(imageUrl: item.imageUrl, title: item.title)
                  : DecoratedBox(
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
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
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
                  if (option.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      option,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    formatWon(item.priceCredits),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.priceBurgundy,
                        ),
                  ),
                  const SizedBox(height: 4),
                  SellerBadge(
                    shopName: item.seller.shopName,
                    isOfficial: item.isOfficial,
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
