import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_mall/core/theme/app_theme.dart';
import 'package:shopping_mall/features/admin/admin_dashboard.dart';
import 'package:shopping_mall/features/admin/admin_screen.dart';

void main() {
  testWidgets('admin users table splits names and toggles each role', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final query = TextEditingController();
    addTearDown(query.dispose);
    var searched = false;
    var savedId = '';
    var deletedId = '';
    final drafts = <String, AdminUserRowDraft>{
      'u1': const AdminUserRowDraft(
        buyerName: '구매이름',
        isBuyer: true,
        isSeller: false,
        isAdmin: false,
      ),
      'u2': const AdminUserRowDraft(
        buyerName: '운영이름',
        sellerName: '청정마트',
        isBuyer: true,
        isSeller: true,
        isAdmin: true,
      ),
    };

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
                  'displayName': '구매이름',
                  'sellerName': null,
                  'isBuyer': true,
                  'isSeller': false,
                  'isAdmin': false,
                  'sellerStatus': null,
                },
                {
                  'id': 'u2',
                  'email': 'shop@mall.local',
                  'displayName': '운영이름',
                  'sellerName': '청정마트',
                  'isBuyer': true,
                  'isSeller': true,
                  'isAdmin': true,
                  'sellerStatus': 'active',
                },
              ],
              queryController: query,
              userDrafts: drafts,
              pageLocked: false,
              isRowBusy: (_) => false,
              onSearch: () => searched = true,
              onDraftChanged: (id, value) => drafts[id] = value,
              onSave: (id) => savedId = id,
              onDelete: (id) => deletedId = id,
            ),
          ),
        ),
      ),
    );

    expect(find.text('buyer@mall.local'), findsOneWidget);
    expect(find.text('구매자 이름'), findsOneWidget);
    expect(find.text('판매자 이름'), findsOneWidget);
    expect(find.text('구매이름'), findsOneWidget);
    expect(find.text('청정마트'), findsOneWidget);
    expect(find.text('구매자'), findsOneWidget);
    expect(find.text('판매자'), findsOneWidget);
    expect(find.text('관리자'), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
    expect(find.byType(Checkbox), findsNWidgets(6));
    expect(find.text('검색'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '저장'), findsNWidgets(2));
    expect(find.widgetWithText(TextButton, '삭제'), findsNWidgets(2));

    await tester.enterText(find.byType(TextField).first, 'buyer');
    await tester.tap(find.text('검색'));
    await tester.pump();
    expect(searched, isTrue);

    await tester.enterText(find.byType(TextField).at(1), '새구매자');
    await tester.tap(find.byType(Checkbox).at(2));
    await tester.pump();
    expect(drafts['u1']!.buyerName, '새구매자');
    expect(drafts['u1']!.isAdmin, isTrue);

    await tester.tap(find.widgetWithText(FilledButton, '저장').first);
    await tester.pump();
    expect(savedId, 'u1');

    await tester.tap(find.widgetWithText(TextButton, '삭제').last);
    await tester.pump();
    expect(deletedId, 'u2');
  });
}
