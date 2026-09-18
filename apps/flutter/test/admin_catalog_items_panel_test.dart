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
                  offerCount: 2,
                  publishedOfferCount: 1,
                ),
              ],
              pageLocked: false,
              queryController: query,
              isRowBusy: (_) => false,
              onSearch: () => searched = true,
              onAdd: () => added = true,
              onDelete: (item) => deleted = item,
            ),
          ),
        ),
      ),
    );

    expect(find.text('대표 카드 1건'), findsOneWidget);
    expect(find.text('농심 백산수'), findsOneWidget);
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
}
