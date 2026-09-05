import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';

/// Browse URL SSOT: `/`, `/?major=`, `/?major=&mid=`, `/?q=`.
String browseLocation({String? major, String? mid, String? q}) {
  final trimmedQ = q?.trim() ?? '';
  if (trimmedQ.isNotEmpty) {
    return Uri(path: '/', queryParameters: {'q': trimmedQ}).toString();
  }
  final params = <String, String>{};
  if (major != null && major.isNotEmpty) params['major'] = major;
  if (mid != null && mid.isNotEmpty) params['mid'] = mid;
  if (params.isEmpty) return '/';
  return Uri(path: '/', queryParameters: params).toString();
}

bool hasBrowseQuery(Uri uri) {
  final q = uri.queryParameters['q']?.trim() ?? '';
  final major = uri.queryParameters['major']?.trim() ?? '';
  final mid = uri.queryParameters['mid']?.trim() ?? '';
  return q.isNotEmpty || major.isNotEmpty || mid.isNotEmpty;
}

/// Deep-link step-down when the stack cannot pop.
String browseStepDown(Uri uri) {
  final q = uri.queryParameters['q']?.trim() ?? '';
  if (q.isNotEmpty) return '/';
  final major = uri.queryParameters['major']?.trim() ?? '';
  final mid = uri.queryParameters['mid']?.trim() ?? '';
  if (mid.isNotEmpty && major.isNotEmpty) {
    return browseLocation(major: major);
  }
  return '/';
}

/// Flavor/volume chips: 생수 종류일 때만.
bool showsWaterFilters({String? mid, String? category, String? q}) {
  if (mid == '생수') return true;
  if (category == '생수' || category == '일반생수') return true;
  return (q ?? '').trim() == '생수';
}

void clearCatalogBrowse(WidgetRef ref) {
  ref.read(catalogSearchProvider.notifier).state = '';
  ref.read(catalogDebouncedSearchProvider.notifier).state = '';
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
