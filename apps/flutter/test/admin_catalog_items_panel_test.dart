import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_mall/core/models/models.dart';
import 'package:shopping_mall/core/theme/app_theme.dart';
import 'package:shopping_mall/features/admin/admin_screen.dart';

void main() {
  testWidgets('admin catalog items panel adds and deletes a card', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final query = TextEditingController();
    addTearDown(query.dispose);
    var searched = false;
    var added = false;
    AdminCatalogProductModel? deleted;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.web(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminCatalogItemsPanel(
              items: [
                AdminCatalogProductModel(
                  id: 'c1',
                  title: '백산수',
                  manufacturer: '농심',
                  category: '생수',
                  status: 'active',
                  offerCount: 3,
                  publishedOfferCount: 2,
                  shopCount: 2,
                  medianUnitPrice: 0.6,
                  priceUnit: 'ml',
                  displayPriceLabel: 'L당',
                ),
              ],
              total: 1,
              offset: 0,
              limit: 24,
              l1Tag: '',
              includeRetired: false,
              pageLocked: false,
              queryController: query,
              isRowBusy: (_) => false,
              onSearch: () => searched = true,
              onQueryChanged: (_) {},
              onL1Tag: (_) {},
              onIncludeRetired: (_) {},
              onAdd: () => added = true,
              onDelete: (item) => deleted = item,
            ),
          ),
        ),
      ),
    );

    expect(find.text('대표 카드 1건'), findsOneWidget);
    expect(find.text('농심 백산수'), findsOneWidget);
    expect(find.text('L당 600원(중앙값)'), findsOneWidget);
    expect(find.text('오퍼 2'), findsOneWidget);
    expect(find.text('가게 2'), findsOneWidget);
    expect(find.text('카드 추가'), findsOneWidget);

    await tester.tap(find.text('검색'));
    await tester.pump();
    expect(searched, isTrue);

    await tester.tap(find.text('카드 추가'));
    await tester.pump();
    expect(added, isTrue);

    await tester.tap(find.text('삭제'));
    await tester.pump();
    expect(deleted?.id, 'c1');
  });

  testWidgets('admin catalog items panel paginates with total count', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final query = TextEditingController();
    addTearDown(query.dispose);
    var next = false;
    var prev = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.web(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminCatalogItemsPanel(
              items: [
                AdminCatalogProductModel(
                  id: 'c2',
                  title: '삼다수',
                  manufacturer: '광동',
                  category: '생수',
                  status: 'active',
                  offerCount: 1,
                  publishedOfferCount: 1,
                  shopCount: 1,
                  medianPriceCredits: 1200,
                ),
              ],
              total: 80,
              offset: 24,
              limit: 24,
              l1Tag: '생수/음료',
              includeRetired: false,
              pageLocked: false,
              queryController: query,
              isRowBusy: (_) => false,
              onSearch: () {},
              onQueryChanged: (_) {},
              onL1Tag: (_) {},
              onIncludeRetired: (_) {},
              onPrev: () => prev = true,
              onNext: () => next = true,
              onAdd: () {},
              onDelete: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('대표 카드 80건'), findsOneWidget);
    expect(find.text('25–25 / 80건'), findsOneWidget);
    expect(find.text('오퍼 1'), findsOneWidget);
    expect(find.text('가게 1'), findsOneWidget);
    expect(find.text('1,200원(중앙값)'), findsOneWidget);

    await tester.tap(find.text('다음'));
    await tester.pump();
    expect(next, isTrue);

    await tester.tap(find.text('이전'));
    await tester.pump();
    expect(prev, isTrue);
  });
}
