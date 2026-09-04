import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/table_taxonomy.dart';
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

  void _clearBrowse(WidgetRef ref) {
    ref.read(catalogSearchProvider.notifier).state = '';
    ref.read(catalogMajorProvider.notifier).state = null;
    ref.read(catalogMidProvider.notifier).state = null;
    ref.read(catalogCategoryProvider.notifier).state = null;
    ref.read(catalogFlavorFilterProvider.notifier).state = null;
    ref.read(catalogVolumeMinFilterProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = ref.watch(catalogSearchProvider).trim();
    final major = ref.watch(catalogMajorProvider);
    final mid = ref.watch(catalogMidProvider);
    final category = ref.watch(catalogCategoryProvider);
    final flavor = ref.watch(catalogFlavorFilterProvider);
    final volumeMin = ref.watch(catalogVolumeMinFilterProvider);
    final tokens = mallTokensOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final columns = isWebUi
        ? (width < webCompactBreakpoint ? 2 : tokens.productGridColumns)
        : 2;
    final aspectRatio = isWebUi ? (width < webCompactBreakpoint ? 0.82 : 0.76) : 0.68;
    final padding = EdgeInsets.all(isWebUi ? 24 : 16);

    final isLanding = search.isEmpty && major == null && mid == null && category == null;
    final isMidBrowse = major != null && mid == null && search.isEmpty && category == null;

    if (isLanding) {
      return _LandingView(
        padding: padding,
        onPickMajor: (name) {
          ref.read(catalogFlavorFilterProvider.notifier).state = null;
          ref.read(catalogVolumeMinFilterProvider.notifier).state = null;
          ref.read(catalogMidProvider.notifier).state = null;
          ref.read(catalogCategoryProvider.notifier).state = null;
          ref.read(catalogMajorProvider.notifier).state = name;
        },
        onSearchChanged: (v) => ref.read(catalogSearchProvider.notifier).state = v,
      );
    }

    if (isMidBrowse) {
      final table = tableMajorByName(major);
      return _MidBrowseView(
        majorName: tableMajorLabel(major),
        mids: table?.mids ?? const [],
        padding: padding,
        onBack: () => _clearBrowse(ref),
        onPickMid: (name) {
          ref.read(catalogFlavorFilterProvider.notifier).state = null;
          ref.read(catalogVolumeMinFilterProvider.notifier).state = null;
          ref.read(catalogCategoryProvider.notifier).state = null;
          ref.read(catalogMidProvider.notifier).state = name;
        },
      );
    }

    final catalogAsync = ref.watch(catalogProductsProvider);
    final bannerText = mid != null
        ? '“${tableMajorLabel(major ?? '')} · $mid” · 같은 회사·품목은 카드 1장, 상세에서 오퍼를 비교합니다.'
        : search.isNotEmpty
            ? '“$search” 검색 — 같은 회사·품목은 카드 1장, 상세에서 오퍼를 비교합니다.'
            : '같은 회사·품목은 카드 1장 · 단위당 대표가(중위)만 표시합니다.';

    return catalogAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('상품을 불러오지 못했습니다: $e')),
      data: (items) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isWebUi)
              Padding(
                padding: padding.copyWith(bottom: 0),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: '밥, 떡, 쌀…',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => ref.read(catalogSearchProvider.notifier).state = v,
                ),
              ),
            Padding(
              padding: padding.copyWith(bottom: 0, top: isWebUi ? padding.top : 12),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      if (mid != null || category != null) {
                        ref.read(catalogMidProvider.notifier).state = null;
                        ref.read(catalogCategoryProvider.notifier).state = null;
                        ref.read(catalogFlavorFilterProvider.notifier).state = null;
                        ref.read(catalogVolumeMinFilterProvider.notifier).state = null;
                        if (major == null) _clearBrowse(ref);
                      } else {
                        _clearBrowse(ref);
                      }
                    },
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: Text(
                      mid != null && major != null
                          ? tableMajorLabel(major)
                          : '식탁',
                    ),
                  ),
                  Flexible(
                    child: Text(
                      mid ??
                          category ??
                          (search.isNotEmpty
                              ? '검색'
                              : (major != null ? tableMajorLabel(major) : '목록')),
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.brandTeal,
                          ),
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
                  ? const Center(
                      child: Text('아직 등록된 대표 상품이 없습니다.\n식탁 분류는 그대로 고를 수 있습니다.'),
                    )
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

class _LandingView extends StatefulWidget {
  const _LandingView({
    required this.padding,
    required this.onPickMajor,
    required this.onSearchChanged,
  });

  final EdgeInsets padding;
  final ValueChanged<String> onPickMajor;
  final ValueChanged<String> onSearchChanged;

  @override
  State<_LandingView> createState() => _LandingViewState();
}

class _LandingViewState extends State<_LandingView> {
  final _tableKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final majors = orderedTableTaxonomy();
    final today = kTodayMajorNames
        .map(tableMajorByName)
        .whereType<TableMajor>()
        .toList();

    return ListView(
      padding: widget.padding,
      children: [
        if (!isWebUi) ...[
          TextField(
            decoration: const InputDecoration(
              hintText: '밥, 떡, 쌀…',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: widget.onSearchChanged,
          ),
          const SizedBox(height: 20),
        ],
        _HeroBlock(
          onPrimary: () {
            final ctx = _tableKey.currentContext;
            if (ctx != null) {
              Scrollable.ensureVisible(
                ctx,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut,
              );
            }
          },
        ),
        const SizedBox(height: 40),
        KeyedSubtree(
          key: _tableKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '식탁',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.brandTeal,
                      letterSpacing: -0.5,
                      fontSize: 26,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                '대분류로 들어갑니다. 제품이 없어도 분류는 보여 줍니다.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xA0212121),
                      fontSize: 13,
                    ),
              ),
              const SizedBox(height: 22),
              _MajorCircleGrid(majors: majors, onPick: widget.onPickMajor),
            ],
          ),
        ),
        const SizedBox(height: 48),
        Text(
          '오늘 추천',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppTheme.brandTeal,
                letterSpacing: -0.5,
                fontSize: 26,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          '지금 밥상에 올리기 좋은 분류.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xA0212121),
                fontSize: 13,
              ),
        ),
        const SizedBox(height: 22),
        _TodayGrid(items: today, onPick: widget.onPickMajor),
        const SizedBox(height: 48),
        Text(
          '대표가는 최저가가 아닙니다',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppTheme.brandTeal,
              ),
        ),
        const SizedBox(height: 12),
        const MallInfoBanner(
          text: '식탁 안 카드 가격은 단위당 중간값입니다. 용량·가게는 상세 오퍼에서만 고릅니다.',
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _HeroBlock extends StatelessWidget {
  const _HeroBlock({required this.onPrimary});

  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < webCompactBreakpoint;
    final left = _HeroPanel(
      title: '식탁부터 고르면,\n카드가 쭈르륵',
      lede: '대분류 → 중분류. 회사는 그 다음입니다. 같은 식탁 위 품목만 한 장으로 모입니다.',
      cta: '식탁 보기',
      onTap: onPrimary,
      gradient: const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Color(0xEB074A4E), Color(0x59074A4E)],
      ),
      solidCta: true,
    );
    final right = _HeroPanel(
      title: '공식 · 입점\n한 목록',
      lede: '배송 주체는 오퍼 줄에서 보입니다.',
      cta: '식탁으로',
      onTap: onPrimary,
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xE0872022), Color(0x8C872022)],
      ),
      solidCta: false,
      compactTitle: true,
    );

    if (narrow) {
      return Column(
        children: [
          SizedBox(height: 280, child: left),
          const SizedBox(height: 14),
          SizedBox(height: 200, child: right),
        ],
      );
    }

    return SizedBox(
      height: 340,
      child: Row(
        children: [
          Expanded(flex: 17, child: left),
          const SizedBox(width: 18),
          Expanded(flex: 9, child: right),
        ],
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.title,
    required this.lede,
    required this.cta,
    required this.onTap,
    required this.gradient,
    required this.solidCta,
    this.compactTitle = false,
  });

  final String title;
  final String lede;
  final String cta;
  final VoidCallback onTap;
  final Gradient gradient;
  final bool solidCta;
  final bool compactTitle;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: gradient),
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  letterSpacing: -0.6,
                  fontSize: compactTitle ? 26 : 36,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                lede,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 14,
                  height: 1.55,
                ),
              ),
              const Spacer(),
              Material(
                color: solidCta ? Colors.white : Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    alignment: Alignment.center,
                    decoration: solidCta
                        ? null
                        : BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                          ),
                    child: Text(
                      cta,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: solidCta ? AppTheme.brandTeal : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MajorCircleGrid extends StatelessWidget {
  const _MajorCircleGrid({required this.majors, required this.onPick});

  final List<TableMajor> majors;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cols = width < 600 ? 4 : (width < 960 ? 6 : 8);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: majors.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.78,
      ),
      itemBuilder: (context, index) {
        final m = majors[index];
        final label = tableMajorLabel(m.name);
        final imageUrl = tableMajorImageUrl(m.name);
        return InkWell(
          onTap: () => onPick(m.name),
          borderRadius: BorderRadius.circular(16),
          child: Column(
            children: [
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFEFF5F5),
                      border: Border.all(color: const Color(0x14074A4E)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0F074A4E),
                          blurRadius: 16,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: imageUrl == null
                        ? Center(
                            child: Text(
                              label.substring(0, 1),
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.brandTeal,
                              ),
                            ),
                          )
                        : Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(
                                label.substring(0, 1),
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.brandTeal,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.brandTeal,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TodayGrid extends StatelessWidget {
  const _TodayGrid({required this.items, required this.onPick});

  final List<TableMajor> items;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cols = width < webCompactBreakpoint ? 2 : 4;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        childAspectRatio: 0.88,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemBuilder: (context, index) {
        final m = items[index];
        final label = tableMajorLabel(m.name);
        final tag = index == 0 ? '지금 많이' : '오늘';
        return Material(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0x14074A4E)),
          ),
          shadowColor: const Color(0x0F074A4E),
          child: InkWell(
            onTap: () => onPick(m.name),
            borderRadius: BorderRadius.circular(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFEFF5F5),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      label.substring(0, 1),
                      style: const TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.brandTeal,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 8),
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
                      const SizedBox(height: 10),
                      Text(
                        '중분류 ${m.mids.length}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.brandTeal,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MidBrowseView extends StatelessWidget {
  const _MidBrowseView({
    required this.majorName,
    required this.mids,
    required this.padding,
    required this.onBack,
    required this.onPickMid,
  });

  final String majorName;
  final List<TableMid> mids;
  final EdgeInsets padding;
  final VoidCallback onBack;
  final ValueChanged<String> onPickMid;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cols = width < webCompactBreakpoint ? 2 : (width < 960 ? 3 : 4);

    return ListView(
      padding: padding,
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('식탁'),
            ),
            Text(
              majorName,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.brandTeal,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '중분류를 고르면 그 안의 회사+품목 카드가 나옵니다.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xA0212121),
              ),
        ),
        const SizedBox(height: 20),
        if (mids.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('중분류가 없습니다.')),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: mids.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              childAspectRatio: 1.35,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemBuilder: (context, index) {
              final mid = mids[index];
              return Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: Color(0x14074A4E)),
                ),
                child: InkWell(
                  onTap: () => onPickMid(mid.name),
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mid.name,
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
                          '소분류 ${mid.minors.length}',
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
          ),
      ],
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
            Expanded(child: _CardThumb(item: item)),
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
