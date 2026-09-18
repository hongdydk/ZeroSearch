import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'guest_l1.dart';
import '../providers/app_providers.dart';

/// 몰 구매 화면(카탈로그·상세·장바구니·결제)에서 헤더 검색을 연다. 포털·주문·설정은 제외.
bool showsMallBuyerSearch(String location) {
  if (location == '/') return true;
  if (location.startsWith('/catalog/')) return true;
  if (location.startsWith('/products/')) return true;
  if (location == '/cart' || location.startsWith('/cart/')) return true;
  if (location == '/checkout' || location.startsWith('/checkout/')) return true;
  return false;
}

/// Browse URL SSOT: `/`, `/?l1=`, `/?l1=&l2=`, `/?l1=&l2=&axis=brand|menu|seller`, `/?q=`. 레거시 `major`/`mid`도 읽는다.
String browseLocation({
  String? l1,
  String? l2,
  String? axis,
  String? brand,
  String? menu,
  String? storage,
  bool all = false,
  String? major,
  String? mid,
  String? category,
  String? q,
}) {
  final trimmedQ = q?.trim() ?? '';
  final params = <String, String>{};
  if (trimmedQ.isNotEmpty) {
    params['q'] = trimmedQ;
    final resolvedAxis = normalizeBrowseAxis(axis);
    params['axis'] = resolvedAxis;
    if (all) {
      params['all'] = '1';
    } else if (!isSellerBrowseAxis(resolvedAxis) &&
        resolvedAxis == kBrowseAxisMenu &&
        menu != null &&
        menu.isNotEmpty) {
      params['menu'] = menu;
    } else if (!isSellerBrowseAxis(resolvedAxis) &&
        brand != null &&
        brand.isNotEmpty) {
      params['brand'] = brand;
    }
    return Uri(path: '/', queryParameters: params).toString();
  }
  if (l1 != null && l1.isNotEmpty) {
    params['l1'] = l1;
    final resolvedL2 = normalizeGuestL2(l1, l2);
    if (resolvedL2 != null) {
      params['l2'] = resolvedL2;
      final resolvedAxis = (axis != null && axis.isNotEmpty)
          ? normalizeBrowseAxis(axis, fallback: guestL1DefaultAxis(l1))
          : guestL1DefaultAxis(l1);
      params['axis'] = resolvedAxis;
      if (storage != null && storage.isNotEmpty) params['storage'] = storage;
      if (all) {
        params['all'] = '1';
      } else if (!isSellerBrowseAxis(resolvedAxis) &&
          resolvedAxis == kBrowseAxisMenu &&
          menu != null &&
          menu.isNotEmpty) {
        params['menu'] = menu;
      } else if (!isSellerBrowseAxis(resolvedAxis) &&
          brand != null &&
          brand.isNotEmpty) {
        params['brand'] = brand;
      }
    }
  } else {
    if (major != null && major.isNotEmpty) params['major'] = major;
    if (mid != null && mid.isNotEmpty) params['mid'] = mid;
    if (category != null && category.isNotEmpty) params['category'] = category;
  }
  if (params.isEmpty) return '/';
  return Uri(path: '/', queryParameters: params).toString();
}

bool hasBrowseQuery(Uri uri) {
  final q = uri.queryParameters['q']?.trim() ?? '';
  final l1 = uri.queryParameters['l1']?.trim() ?? '';
  final major = uri.queryParameters['major']?.trim() ?? '';
  final mid = uri.queryParameters['mid']?.trim() ?? '';
  final category = uri.queryParameters['category']?.trim() ?? '';
  return q.isNotEmpty ||
      l1.isNotEmpty ||
      major.isNotEmpty ||
      mid.isNotEmpty ||
      category.isNotEmpty;
}

/// Deep-link step-down when the stack cannot pop.
String browseStepDown(Uri uri) {
  final q = uri.queryParameters['q']?.trim() ?? '';
  if (q.isNotEmpty) {
    final axis = uri.queryParameters['axis']?.trim() ?? '';
    final brand = uri.queryParameters['brand']?.trim() ?? '';
    final menu = uri.queryParameters['menu']?.trim() ?? '';
    final all = uri.queryParameters['all'] == '1';
    if (brand.isNotEmpty || menu.isNotEmpty || all) {
      return browseLocation(
        q: q,
        axis: axis.isEmpty ? kBrowseAxisBrand : axis,
      );
    }
    return '/';
  }
  final l1 = uri.queryParameters['l1']?.trim() ?? '';
  if (l1.isNotEmpty) {
    final axis = uri.queryParameters['axis']?.trim() ?? '';
    final l2 = uri.queryParameters['l2']?.trim() ?? '';
    final brand = uri.queryParameters['brand']?.trim() ?? '';
    final menu = uri.queryParameters['menu']?.trim() ?? '';
    final storage = uri.queryParameters['storage']?.trim() ?? '';
    final all = uri.queryParameters['all'] == '1';
    if (brand.isNotEmpty || menu.isNotEmpty || all) {
      return browseLocation(
        l1: l1,
        l2: l2.isEmpty ? null : l2,
        axis: axis.isEmpty ? null : axis,
        storage: storage.isEmpty ? null : storage,
      );
    }
    if (l2.isNotEmpty) {
      return browseLocation(l1: l1);
    }
    return '/';
  }
  final major = uri.queryParameters['major']?.trim() ?? '';
  final mid = uri.queryParameters['mid']?.trim() ?? '';
  final category = uri.queryParameters['category']?.trim() ?? '';
  if (category.isNotEmpty && mid.isNotEmpty) {
    return browseLocation(
      major: major.isEmpty ? null : major,
      mid: mid,
    );
  }
  if (mid.isNotEmpty && major.isNotEmpty) {
    return browseLocation(major: major);
  }
  return '/';
}

/// Flavor/volume chips: 현재 결과 집합의 공개 오퍼에서만.
class OfferFilterFacets {
  const OfferFilterFacets({
    this.flavors = const [],
    this.hasVolumeMin2000 = false,
  });

  final List<String> flavors;
  final bool hasVolumeMin2000;

  bool get hasChips => flavors.isNotEmpty || hasVolumeMin2000;
}

OfferFilterFacets offerFilterFacets({
  Iterable<String> availableFlavors = const [],
  bool hasVolumeMin2000 = false,
}) {
  final flavors = <String>[];
  final seen = <String>{};
  for (final raw in availableFlavors) {
    final name = raw.trim();
    if (name.isEmpty || seen.contains(name)) continue;
    seen.add(name);
    flavors.add(name);
  }
  return OfferFilterFacets(
    flavors: flavors,
    hasVolumeMin2000: hasVolumeMin2000,
  );
}

/// Legacy water-kind gate. Prefer [offerFilterFacets] for guest chips.
bool showsWaterFilters({
  String? l1,
  String? mid,
  String? category,
  String? q,
}) {
  if (mid == '생수') return true;
  if (category == '생수' || category == '일반생수') return true;
  return (q ?? '').trim() == '생수';
}

void clearCatalogBrowse(WidgetRef ref) {
  ref.read(catalogSearchProvider.notifier).state = '';
  ref.read(catalogDebouncedSearchProvider.notifier).state = '';
  ref.read(catalogL1Provider.notifier).state = null;
  ref.read(catalogL2Provider.notifier).state = null;
  ref.read(catalogL1AxisProvider.notifier).state = null;
  ref.read(catalogL1BrandProvider.notifier).state = null;
  ref.read(catalogL1MenuProvider.notifier).state = null;
  ref.read(catalogStorageFilterProvider.notifier).state = null;
  ref.read(catalogL1AllProvider.notifier).state = false;
  ref.read(catalogMajorProvider.notifier).state = null;
  ref.read(catalogMidProvider.notifier).state = null;
  ref.read(catalogCategoryProvider.notifier).state = null;
  ref.read(catalogFlavorFilterProvider.notifier).state = null;
  ref.read(catalogVolumeMinFilterProvider.notifier).state = null;
}

class CatalogSearchDebounce {
  CatalogSearchDebounce({this.delay = const Duration(milliseconds: 300)});

  final Duration delay;
  Timer? _timer;

  void schedule(String value, void Function(String value) onCommit) {
    _timer?.cancel();
    _timer = Timer(delay, () => onCommit(value));
  }

  void cancel() => _timer?.cancel();

  void dispose() => _timer?.cancel();
}
