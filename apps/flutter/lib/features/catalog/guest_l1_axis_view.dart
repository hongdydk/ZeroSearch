import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/guest_l1.dart';
import '../../core/layout/ui_platform.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';

class GuestL1AxisView extends ConsumerWidget {
  const GuestL1AxisView({
    super.key,
    required this.l1,
    required this.axis,
            required this.storage,
            required this.padding,
            required this.onBack,
    required this.onAxis,
    required this.onStorage,
    required this.onPickBrand,
    required this.onPickMenu,
    required this.onSeeAll,
  });

  final String l1;
  final String axis;
  final String? storage;
  final EdgeInsets padding;
  final VoidCallback onBack;
  final ValueChanged<String> onAxis;
  final ValueChanged<String?> onStorage;
  final ValueChanged<String> onPickBrand;
  final ValueChanged<String> onPickMenu;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facetsAsync = ref.watch(guestL1FacetsProvider);
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
                l1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.brandTeal,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '브랜드 또는 메뉴로 좁히면 그 안의 회사+품목 카드가 나옵니다. 겹치는 1차 태그는 그대로입니다.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xA0212121),
              ),
        ),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'brand', label: Text('브랜드부터')),
            ButtonSegment(value: 'menu', label: Text('메뉴부터')),
          ],
          selected: {axis == 'menu' ? 'menu' : 'brand'},
          onSelectionChanged: (next) {
            if (next.isEmpty) return;
            onAxis(next.first);
          },
        ),
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
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onSeeAll,
            child: const Text('이 분류 전체 보기'),
          ),
        ),
        const SizedBox(height: 8),
        facetsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) => const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('목록을 불러오지 못했습니다.')),
          ),
          data: (facets) {
            final items = axis == 'menu'
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
                childAspectRatio: 1.55,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
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
                    onTap: () => axis == 'menu'
                        ? onPickMenu(item.name)
                        : onPickBrand(item.name),
                    borderRadius: BorderRadius.circular(18),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
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
        ),
      ],
    );
  }
}
