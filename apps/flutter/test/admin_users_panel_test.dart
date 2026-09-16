import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_mall/core/theme/app_theme.dart';
import 'package:shopping_mall/features/admin/admin_screen.dart';

void main() {
  testWidgets('admin users table shows roles, search, save and delete', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final query = TextEditingController();
    addTearDown(query.dispose);
    var searched = false;
    var savedId = '';
    var deletedId = '';
    final draft = <String, bool>{'u1': false};

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.web(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminUsersPanel(
              users: const [
                {
                  'id': 'u1',
                  'email': 'buyer@mall.local',
                  'displayName': '구매자',
                  'isAdmin': false,
                  'sellerStatus': null,
                },
                {
                  'id': 'u2',
                  'email': 'shop@mall.local',
                  'displayName': '가게',
                  'isAdmin': true,
                  'sellerStatus': 'active',
                },
              ],
              queryController: query,
              adminDraft: draft,
              pageLocked: false,
              isRowBusy: (_) => false,
              onSearch: () => searched = true,
              onAdminChanged: (id, value) => draft[id] = value,
              onSave: (id) => savedId = id,
              onDelete: (id) => deletedId = id,
            ),
          ),
        ),
      ),
    );

    expect(find.text('buyer@mall.local'), findsOneWidget);
    expect(find.text('구매자'), findsWidgets);
    expect(find.text('판매자'), findsOneWidget);
    expect(find.text('관리자'), findsWidgets);
    expect(find.text('검색'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '저장'), findsNWidgets(2));
    expect(find.widgetWithText(TextButton, '삭제'), findsNWidgets(2));

    await tester.enterText(find.byType(TextField), 'buyer');
    await tester.tap(find.text('검색'));
    await tester.pump();
    expect(searched, isTrue);

    await tester.tap(find.widgetWithText(FilledButton, '저장').first);
    await tester.pump();
    expect(savedId, 'u1');

    await tester.tap(find.widgetWithText(TextButton, '삭제').last);
    await tester.pump();
    expect(deletedId, 'u2');
  });
}
