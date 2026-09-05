import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/catalog/browse_location.dart';
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

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});

  static const _flavorOptions = ['레몬', '자몽'];

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  final _searchDebounce = CatalogSearchDebounce();
  String? _syncedQuery;
  String? _pendingSyncKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Riverpod forbids provider writes during didChangeDependencies/build.
    // Defer so go('/?major=') / deep-link sync actually applies.
    if (GoRouter.maybeOf(context) == null) return;
    final uri = GoRouterState.of(context).uri;
    final key = uri.hasQuery ? uri.query : '';
    if (_syncedQuery == key || _pendingSyncKey == key) return;
    _pendingSyncKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingSyncKey = null;
      if (!mounted) return;
      _syncBrowseFromUri(uri);
    });
  }

  @override
  void dispose() {
    _searchDebounce.dispose();
    super.dispose();
  }

  void _syncBrowseFromUri(Uri uri) {
    final key = uri.hasQuery ? uri.query : '';
    if (_syncedQuery == key) return;
    _syncedQuery = key;
    _searchDebounce.cancel();

    final q = (uri.queryParameters['q'] ?? '').trim();
    final majorRaw = uri.queryParameters['major'];
    final midRaw = uri.queryParameters['mid'];
    final major = (majorRaw == null || majorRaw.isEmpty) ? null : majorRaw;
    final mid = (midRaw == null || midRaw.isEmpty) ? null : midRaw;

    if (q.isNotEmpty) {
      if (ref.read(catalogSearchProvider) != q) {
        ref.read(catalogSearchProvider.notifier).state = q;
      }
      if (ref.read(catalogDebouncedSearchProvider) != q) {
        ref.read(catalogDebouncedSearchProvider.notifier).state = q;
      }
      if (ref.read(catalogMajorProvider) != null) {
        ref.read(catalogMajorProvider.notifier).state = null;
      }
      if (ref.read(catalogMidProvider) != null) {
        ref.read(catalogMidProvider.notifier).state = null;
      }
      if (ref.read(catalogCategoryProvider) != null) {
        ref.read(catalogCategoryProvider.notifier).state = null;
      }
      return;
    }
    if (ref.read(catalogSearchProvider).isNotEmpty) {
      ref.read(catalogSearchProvider.notifier).state = '';
    }
    if (ref.read(catalogDebouncedSearchProvider).isNotEmpty) {
      ref.read(catalogDebouncedSearchProvider.notifier).state = '';
    }
    if (ref.read(catalogMajorProvider) != major) {
      ref.read(catalogMajorProvider.notifier).state = major;
    }
    if (ref.read(catalogMidProvider) != mid) {
      ref.read(catalogMidProvider.notifier).state = mid;
    }
  }

  void _applyMajorDrill(String name) {
    ref.read(catalogMidScrollOffsetProvider.notifier).state = 0;
    ref.read(catalogSearchProvider.notifier).state = '';
    ref.read(catalogDebouncedSearchProvider.notifier).state = '';
    ref.read(catalogCategoryProvider.notifier).state = null;
    ref.read(catalogFlavorFilterProvider.notifier).state = null;
    ref.read(catalogVolumeMinFilterProvider.notifier).state = null;
    ref.read(catalogMidProvider.notifier).state = null;
    ref.read(catalogMajorProvider.notifier).state = name;
    // go (not push): one CatalogScreen + URL history. push stacked screens
    // that share providers and left drill state stuck after pop.
    context.go(browseLocation(major: name));
  }

  void _applyMidDrill(String major, String name) {
    ref.read(catalogFlavorFilterProvider.notifier).state = null;
    ref.read(catalogVolumeMinFilterProvider.notifier).state = null;
    ref.read(catalogCategoryProvider.notifier).state = null;
    ref.read(catalogMidProvider.notifier).state = name;
    context.go(browseLocation(major: major, mid: name));
  }

  void _onSearchTyped(String value) {
    ref.read(catalogSearchProvider.notifier).state = value;
    _searchDebounce.schedule(value, (committed) {
      if (!mounted) return;
      final q = committed.trim();
      context.go(q.isEmpty ? '/' : browseLocation(q: q));
    });
  }

  void _clearStaleWaterFilters(bool showWater) {
    if (showWater) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(catalogFlavorFilterProvider) != null) {
        ref.read(catalogFlavorFilterProvider.notifier).state = null;
      }
      if (ref.read(catalogVolumeMinFilterProvider) != null) {
        ref.read(catalogVolumeMinFilterProvider.notifier).state = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final typedSearch = ref.watch(catalogSearchProvider).trim();
    final debouncedSearch = ref.watch(catalogDebouncedSearchProvider).trim();
    final urlMajor = ref.watch(catalogMajorProvider);
    final urlMid = ref.watch(catalogMidProvider);
    final category = ref.watch(catalogCategoryProvider);
    final flavor = ref.watch(catalogFlavorFilterProvider);
    final volumeMin = ref.watch(catalogVolumeMinFilterProvider);
    final tokens = mallTokensOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final columns = isWebUi
        ? (width < webCompactBreakpoint ? 2 : tokens.productGridColumns)
        : 2;
    final aspectRatio = isWebUi ? (width < webCompactBreakpoint ? 0.82 : 0.76) : 0.68;
    final padding = EdgeInsets.symmetric(
      horizontal: isWebUi ? 24 : 16,
      vertical: isWebUi ? 20 : 16,
    );

    final inSearch = typedSearch.isNotEmpty;
    final major = inSearch ? null : urlMajor;
    final mid = inSearch ? null : urlMid;
    final showWater = showsWaterFilters(
      mid: urlMid,
      category: category,
      q: debouncedSearch,
    );
    if (!showWater && (flavor != null || volumeMin != null)) {
      _clearStaleWaterFilters(false);
    }

    final isLanding = !inSearch && major == null && mid == null && category == null;
    final isMidBrowse = !inSearch && major != null && mid == null && category == null;
    final awaitingFirstSearch = inSearch &&
        debouncedSearch.isEmpty &&
        urlMajor == null &&
        urlMid == null &&
        category == null;

    if (isLanding) {
      return _LandingView(
        padding: padding,
        searchValue: typedSearch,
        initialScrollOffset: ref.watch(catalogLandingScrollOffsetProvider),
        onScrollOffset: (v) =>
            ref.read(catalogLandingScrollOffsetProvider.notifier).state = v,
        onPickMajor: _applyMajorDrill,
        onSearchChanged: _onSearchTyped,
      );
    }

    if (isMidBrowse) {
      final table = tableMajorByName(major);
      return _MidBrowseView(
        majorName: tableMajorLabel(major),
        mids: table?.mids ?? const [],
        padding: padding,
        initialScrollOffset: ref.watch(catalogMidScrollOffsetProvider),
        onScrollOffset: (v) =>
            ref.read(catalogMidScrollOffsetProvider.notifier).state = v,
        onBack: () => popBrowseOrHome(context),
        onPickMid: (name) => _applyMidDrill(major!, name),
      );
    }

    final bannerText = mid != null
        ? '“${tableMajorLabel(major ?? '')} · $mid” · 같은 회사·품목은 카드 1장, 상세에서 오퍼를 비교합니다.'
        : inSearch
            ? '“$typedSearch” 검색 — 같은 회사·품목은 카드 1장, 상세에서 오퍼를 비교합니다.'
            : '같은 회사·품목은 카드 1장 · 단위당 대표가(중위)만 표시합니다.';

    final catalogAsync = awaitingFirstSearch ? null : ref.watch(catalogProductsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isWebUi)
          Padding(
            padding: padding.copyWith(bottom: 0),
            child: _SyncedSearchField(
              value: typedSearch,
              onChanged: _onSearchTyped,
            ),
          ),
        Padding(
          padding: padding.copyWith(bottom: 0, top: isWebUi ? padding.top : 12),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => popBrowseOrHome(context),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: Text(
                  !inSearch && mid != null && major != null
                      ? tableMajorLabel(major)
                      : '식탁',
                ),
              ),
              Flexible(
                child: Text(
                  mid ??
                      category ??
                      (inSearch
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
        if (showWater)
          Padding(
            padding: padding.copyWith(top: 12, bottom: 0),
            child: _FilterChips(
              flavor: flavor,
              volumeMin: volumeMin,
              onFlavor: (v) => ref.read(catalogFlavorFilterProvider.notifier).state = v,
              onVolumeMin: (v) => ref.read(catalogVolumeMinFilterProvider.notifier).state = v,
            ),
          ),
        if (catalogAsync != null && catalogAsync.isLoading && catalogAsync.hasValue)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _catalogResultsBody(catalogAsync, padding, columns, aspectRatio)),
      ],
    );
  }

  Widget _catalogResultsBody(
    AsyncValue<List<CatalogProductModel>>? catalogAsync,
    EdgeInsets padding,
    int columns,
    double aspectRatio,
  ) {
    if (catalogAsync == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return catalogAsync.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('상품을 불러오지 못했습니다.'),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => ref.invalidate(catalogProductsProvider),
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const Center(
            child: Text('조건에 맞는 상품이 없습니다.\n검색어나 식탁 분류를 바꿔 보세요.'),
          );
        }
        return GridView.builder(
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
        );
      },
    );
  }
}

class _LandingView extends StatefulWidget {
  const _LandingView({
    required this.padding,
    required this.searchValue,
    required this.initialScrollOffset,
    required this.onScrollOffset,
    required this.onPickMajor,
    required this.onSearchChanged,
  });

  final EdgeInsets padding;
  final String searchValue;
  final double initialScrollOffset;
  final ValueChanged<double> onScrollOffset;
  final ValueChanged<String> onPickMajor;
  final ValueChanged<String> onSearchChanged;

  @override
  State<_LandingView> createState() => _LandingViewState();
}

class _LandingViewState extends State<_LandingView> {
  final _tableKey = GlobalKey();
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
    _scroll.addListener(() {
      if (_scroll.hasClients) widget.onScrollOffset(_scroll.offset);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreOffset());
  }

  void _restoreOffset() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    final target = widget.initialScrollOffset.clamp(0.0, max);
    if (target > 0) _scroll.jumpTo(target);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final majors = orderedTableTaxonomy();
    final today = kTodayMajorNames
        .map(tableMajorByName)
        .whereType<TableMajor>()
        .toList();

    return ListView(
      controller: _scroll,
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: widget.padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isWebUi) ...[
                _SyncedSearchField(
                  value: widget.searchValue,
                  onChanged: widget.onSearchChanged,
                ),
                const SizedBox(height: 12),
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
              const SizedBox(height: 20),
              KeyedSubtree(
                key: _tableKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '카테고리',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.brandTeal,
                            letterSpacing: -0.5,
                            fontSize: 22,
                          ),
                    ),
                    const SizedBox(height: 12),
                    _MajorCircleRow(majors: majors, onPick: widget.onPickMajor),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                '오늘 추천',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.brandTeal,
                      letterSpacing: -0.5,
                      fontSize: 22,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                '지금 식탁에 올리기 좋은.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xA0212121),
                      fontSize: 13,
                    ),
              ),
              const SizedBox(height: 16),
              _TodayGrid(items: today, onPick: widget.onPickMajor),
              const SizedBox(height: 40),
              Text(
                '대표가는 최저가가 아닙니다',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.brandTeal,
                      letterSpacing: -0.5,
                      fontSize: 26,
                    ),
              ),
              const SizedBox(height: 22),
              const _ExplainSection(),
              const SizedBox(height: 40),
            ],
          ),
        ),
        const _SiteFooter(),
      ],
    );
  }
}

class _HeroBlock extends StatefulWidget {
  const _HeroBlock({required this.onPrimary});

  static const _bannerHeight = 176.0;
  static const _mainImage =
      'https://images.unsplash.com/photo-1542838132-92c53300491e?auto=format&fit=crop&w=1400&q=80';
  static const _sideImage =
      'https://images.unsplash.com/photo-1604719312566-8912e9227c6a?auto=format&fit=crop&w=800&q=80';

  final VoidCallback onPrimary;

  @override
  State<_HeroBlock> createState() => _HeroBlockState();
}

class _HeroBlockState extends State<_HeroBlock> {
  late final PageController _page;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _page = PageController();
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _goPage(int delta) {
    if (!_page.hasClients) return;
    final target = (_index + delta).clamp(0, 1);
    if (target == _index) return;
    _page.animateToPage(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _HeroPanel(
        kicker: '이 마켓',
        title: '식탁부터 고르면,\n카드가 쭈르륵',
        lede: '밥이면 밥, 떡이면 떡. 회사는 그 다음입니다.',
        cta: '카테고리 보기',
        onTap: widget.onPrimary,
        imageUrl: _HeroBlock._mainImage,
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xEB074A4E), Color(0x59074A4E), Color(0x00074A4E)],
          stops: [0.0, 0.52, 0.78],
        ),
        solidCta: true,
      ),
      _HeroPanel(
        kicker: '공식 · 입점',
        title: '한 목록에서\n비교합니다',
        lede: '배송 주체(자사배송 / 판매자배송)는 오퍼 줄에 표시합니다.',
        cta: '카테고리로',
        onTap: widget.onPrimary,
        imageUrl: _HeroBlock._sideImage,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xE0872022), Color(0x8C872022)],
        ),
        solidCta: false,
      ),
    ];

    return Column(
      children: [
        SizedBox(
          height: _HeroBlock._bannerHeight,
          child: Stack(
            children: [
              PageView(
                controller: _page,
                physics: const ClampingScrollPhysics(),
                onPageChanged: (i) => setState(() => _index = i),
                children: pages,
              ),
              Positioned(
                left: 6,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _CarouselChevron(
                    icon: Icons.chevron_left,
                    enabled: _index > 0,
                    onPressed: () => _goPage(-1),
                  ),
                ),
              ),
              Positioned(
                right: 6,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _CarouselChevron(
                    icon: Icons.chevron_right,
                    enabled: _index < pages.length - 1,
                    onPressed: () => _goPage(1),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(pages.length, (i) {
            final active = i == _index;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: active ? 16 : 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: AppTheme.brandTeal.withValues(alpha: active ? 1 : 0.28),
                borderRadius: BorderRadius.circular(999),
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// Compact teal chevron for banner / category carousels (web mouse UX).
class _CarouselChevron extends StatelessWidget {
  const _CarouselChevron({
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: enabled ? 0.92 : 0.45),
      shape: const CircleBorder(),
      elevation: enabled ? 1 : 0,
      shadowColor: const Color(0x40074A4E),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onPressed : null,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(
            icon,
            size: 22,
            color: AppTheme.brandTeal.withValues(alpha: enabled ? 1 : 0.35),
          ),
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.kicker,
    required this.title,
    required this.lede,
    required this.cta,
    required this.onTap,
    required this.imageUrl,
    required this.gradient,
    required this.solidCta,
  });

  final String kicker;
  final String title;
  final String lede;
  final String cta;
  final VoidCallback onTap;
  final String imageUrl;
  final Gradient gradient;
  final bool solidCta;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const ColoredBox(color: Color(0xFF074A4E)),
                ),
                DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kicker,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 11,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                          letterSpacing: -0.5,
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        lede,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                      const Spacer(),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 34,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: solidCta
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(999),
                            border: solidCta
                                ? null
                                : Border.all(
                                    color: Colors.white.withValues(alpha: 0.5),
                                  ),
                          ),
                          child: Text(
                            cta,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: solidCta ? AppTheme.brandTeal : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExplainSection extends StatelessWidget {
  const _ExplainSection();

  static const _photoUrl =
      'https://images.unsplash.com/photo-1464226184884-fa280b87c399?auto=format&fit=crop&w=1000&q=80';

  static const _items = [
    (
      '카드 가격은 무엇인가요?',
      '그 종류의 비교 단위(생수는 L당)로 공개 오퍼 가격의 중간값입니다. 지금 결제할 금액이 아닙니다.',
    ),
    (
      '왜 판매자마다 카드가 없나요?',
      '같은 회사의 그 품목은 한 장입니다. 용량·맛·가게 차이는 상세 오퍼 한 줄에서만 고릅니다.',
    ),
    (
      '공식과 입점은 어떻게 보이나요?',
      '한 목록에 함께 두고, 배송 주체(자사배송 / 판매자배송)는 오퍼 줄에 표시합니다.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < webCompactBreakpoint;
    final photo = ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: narrow ? 200 : 320,
        width: double.infinity,
        child: Image.network(
          _photoUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFEFF5F5)),
        ),
      ),
    );
    final faq = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x14074A4E)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
        child: Column(
          children: [
            for (var i = 0; i < _items.length; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _items[i].$1,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.brandTeal,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _items[i].$2,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.55,
                          color: Color(0xB3212121),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (i < _items.length - 1)
                const Divider(height: 1, color: Color(0x1F074A4E)),
            ],
          ],
        ),
      ),
    );

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          photo,
          const SizedBox(height: 16),
          faq,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 9, child: photo),
        const SizedBox(width: 18),
        Expanded(flex: 11, child: faq),
      ],
    );
  }
}

class _SiteFooter extends StatelessWidget {
  const _SiteFooter();

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < webCompactBreakpoint;
    final links = Text(
      '회사소개 · 이용약관 · 개인정보처리방침 · 고객센터',
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.82),
        fontSize: 13,
      ),
    );

    return ColoredBox(
      color: AppTheme.brandTeal,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isWebUi ? 24 : 16,
          36,
          isWebUi ? 24 : 16,
          28,
        ),
        child: narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '제로 서치',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '식탁부터 고르고, 한 장으로 비교합니다.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  links,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '제로 서치',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '식탁부터 고르고, 한 장으로 비교합니다.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  links,
                ],
              ),
      ),
    );
  }
}

class _MajorCircleRow extends StatefulWidget {
  const _MajorCircleRow({required this.majors, required this.onPick});

  /// Narrow / mobile: compact horizontal row.
  static const _compactItemWidth = 72.0;
  static const _compactCircle = 56.0;
  static const _compactRowHeight = 86.0;
  static const _compactGap = 12.0;

  /// Wide / desktop: closer to original landing photo size.
  static const _wideItemWidth = 100.0;
  static const _wideCircle = 80.0;
  static const _wideRowHeight = 112.0;
  static const _wideGap = 16.0;

  final List<TableMajor> majors;
  final ValueChanged<String> onPick;

  @override
  State<_MajorCircleRow> createState() => _MajorCircleRowState();
}

class _MajorCircleRowState extends State<_MajorCircleRow> {
  late final ScrollController _scroll;
  bool _canBack = false;
  bool _canForward = false;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
    _scroll.addListener(_syncArrows);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncArrows());
  }

  @override
  void didUpdateWidget(covariant _MajorCircleRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.majors.length != widget.majors.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncArrows());
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_syncArrows);
    _scroll.dispose();
    super.dispose();
  }

  void _syncArrows() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final back = pos.pixels > 0.5;
    final forward = pos.pixels < pos.maxScrollExtent - 0.5;
    if (back != _canBack || forward != _canForward) {
      setState(() {
        _canBack = back;
        _canForward = forward;
      });
    }
  }

  void _nudge(double delta) {
    if (!_scroll.hasClients) return;
    final target =
        (_scroll.offset + delta).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= webCompactBreakpoint;
    final itemWidth =
        wide ? _MajorCircleRow._wideItemWidth : _MajorCircleRow._compactItemWidth;
    final circleSize =
        wide ? _MajorCircleRow._wideCircle : _MajorCircleRow._compactCircle;
    final gap = wide ? _MajorCircleRow._wideGap : _MajorCircleRow._compactGap;
    final rowHeight =
        wide ? _MajorCircleRow._wideRowHeight : _MajorCircleRow._compactRowHeight;
    final step = itemWidth + gap;
    final glyphSize = wide ? 28.0 : 22.0;
    final showArrows = _canBack || _canForward;
    return SizedBox(
      height: rowHeight,
      child: Row(
        children: [
          if (showArrows) ...[
            _CarouselChevron(
              icon: Icons.chevron_left,
              enabled: _canBack,
              onPressed: () => _nudge(-step),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: ListView.separated(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              itemCount: widget.majors.length,
              separatorBuilder: (_, __) => SizedBox(width: gap),
              itemBuilder: (context, index) {
                final m = widget.majors[index];
                final label = tableMajorLabel(m.name);
                final imageUrl = tableMajorImageUrl(m.name);
                return SizedBox(
                  width: itemWidth,
                  child: InkWell(
                    onTap: () => widget.onPick(m.name),
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      children: [
                        Container(
                          width: circleSize,
                          height: circleSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFEFF5F5),
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
                          child: imageUrl == null
                              ? Center(
                                  child: Text(
                                    label.substring(0, 1),
                                    style: TextStyle(
                                      fontSize: glyphSize,
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
                                      style: TextStyle(
                                        fontSize: glyphSize,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.brandTeal,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.brandTeal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (showArrows) ...[
            const SizedBox(width: 4),
            _CarouselChevron(
              icon: Icons.chevron_right,
              enabled: _canForward,
              onPressed: () => _nudge(step),
            ),
          ],
        ],
      ),
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
    final cols = width < webCompactBreakpoint
        ? 2
        : (width < 1100 ? 4 : (width < 1400 ? 5 : 6));

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
        final imageUrl = tableMajorImageUrl(m.name);
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
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                    child: imageUrl == null
                        ? ColoredBox(
                            color: const Color(0xFFEFF5F5),
                            child: Center(
                              child: Text(
                                label.substring(0, 1),
                                style: const TextStyle(
                                  fontSize: 42,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.brandTeal,
                                ),
                              ),
                            ),
                          )
                        : Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorBuilder: (_, __, ___) => ColoredBox(
                              color: const Color(0xFFEFF5F5),
                              child: Center(
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

class _MidBrowseView extends StatefulWidget {
  const _MidBrowseView({
    required this.majorName,
    required this.mids,
    required this.padding,
    required this.initialScrollOffset,
    required this.onScrollOffset,
    required this.onBack,
    required this.onPickMid,
  });

  final String majorName;
  final List<TableMid> mids;
  final EdgeInsets padding;
  final double initialScrollOffset;
  final ValueChanged<double> onScrollOffset;
  final VoidCallback onBack;
  final ValueChanged<String> onPickMid;

  @override
  State<_MidBrowseView> createState() => _MidBrowseViewState();
}

class _MidBrowseViewState extends State<_MidBrowseView> {
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
    _scroll.addListener(() {
      if (_scroll.hasClients) widget.onScrollOffset(_scroll.offset);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreOffset());
  }

  void _restoreOffset() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    final target = widget.initialScrollOffset.clamp(0.0, max);
    if (target > 0) _scroll.jumpTo(target);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cols = width < webCompactBreakpoint
        ? 2
        : (width < 900 ? 3 : (width < 1200 ? 4 : 5));

    return ListView(
      controller: _scroll,
      padding: widget.padding,
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('식탁'),
            ),
            Text(
              widget.majorName,
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
        if (widget.mids.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('중분류가 없습니다.')),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.mids.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              childAspectRatio: 1.35,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemBuilder: (context, index) {
              final mid = widget.mids[index];
              return Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: Color(0x14074A4E)),
                ),
                child: InkWell(
                  onTap: () => widget.onPickMid(mid.name),
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

class _SyncedSearchField extends StatefulWidget {
  const _SyncedSearchField({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_SyncedSearchField> createState() => _SyncedSearchFieldState();
}

class _SyncedSearchFieldState extends State<_SyncedSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _SyncedSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: const InputDecoration(
        hintText: '밥, 떡, 쌀…',
        prefixIcon: Icon(Icons.search),
      ),
      onChanged: widget.onChanged,
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
    final hasPrice =
        item.medianUnitPrice != null || item.medianPriceCredits != null;
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
                          fontWeight: hasPrice ? FontWeight.w700 : FontWeight.w500,
                          color: hasPrice
                              ? AppTheme.priceBurgundy
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.offerCount > 0 ? '오퍼 ${item.offerCount}' : '오퍼 없음',
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
