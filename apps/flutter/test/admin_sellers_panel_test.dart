import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_mall/core/models/models.dart';
import 'package:shopping_mall/core/theme/app_theme.dart';
import 'package:shopping_mall/features/admin/admin_screen.dart';

AdminSellerModel _seller({
  required String id,
  required String status,
  String shopName = '입점마트',
  String sellerType = 'merchant',
  int warningCount = 0,
}) {
  return AdminSellerModel(
    id: id,
    shopName: shopName,
    userEmail: '$id@mall.local',
    status: status,
    sellerType: sellerType,
    warningCount: warningCount,
  );
}

void main() {
  testWidgets('admin sellers panel exposes warn suspend remove flow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String approved = '';
    String warned = '';
    String suspended = '';
    String removed = '';

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.web(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminSellersPanel(
              pendingSellers: [_seller(id: 'p1', status: 'pending')],
              sellers: [
                _seller(id: 'p1', status: 'pending'),
                _seller(id: 'a1', status: 'active', warningCount: 1),
                _seller(id: 's1', status: 'suspended'),
              ],
              pageLocked: false,
              isRowBusy: (_) => false,
              onApprove: (id) => approved = id,
              onWarn: (id) => warned = id,
              onSuspend: (id) => suspended = id,
              onUnsuspend: (_) {},
              onRemove: (id) => removed = id,
            ),
          ),
        ),
      ),
    );

    expect(find.text('승인'), findsOneWidget);
    expect(find.text('경고'), findsOneWidget);
    expect(find.text('정지'), findsOneWidget);
    expect(find.text('해제'), findsWidgets);

    await tester.tap(find.text('승인'));
    await tester.pump();
    expect(approved, 'p1');

    await tester.tap(find.text('경고'));
    await tester.pump();
    expect(warned, 'a1');

    await tester.tap(find.text('정지'));
    await tester.pump();
    expect(suspended, 'a1');

    await tester.tap(find.text('해제').first);
    await tester.pump();
    expect(removed, isNotEmpty);
  });
}
