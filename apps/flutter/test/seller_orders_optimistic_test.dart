import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_mall/core/models/models.dart';
import 'package:shopping_mall/core/network/api_client.dart';
import 'package:shopping_mall/core/providers/app_providers.dart';
import 'package:shopping_mall/core/theme/app_theme.dart';
import 'package:shopping_mall/features/seller/seller_orders_screen.dart';

class _OrdersApi extends ApiClient {
  _OrdersApi() : super(tokenReader: () async => 'tok');

  Completer<void>? patchBlock;
  String? lastStatus;
  int patchCalls = 0;

  @override
  Future<List<SellerOrderItemModel>> sellerOrders() async {
    return [
      SellerOrderItemModel(
        id: 'item-1',
        orderId: 'ord-1',
        productTitle: '백산수',
        qty: 1,
        lineTotalCredits: 1200,
        fulfillmentStatus: lastStatus ?? 'paid',
        shopName: '공식 스토어',
        sellerType: 'platform',
      ),
    ];
  }

  @override
  Future<void> sellerUpdateOrderStatus(String itemId, String status) async {
    patchCalls += 1;
    lastStatus = status;
    if (patchBlock != null) await patchBlock!.future;
  }
}

void main() {
  testWidgets('seller order status tap moves the row before PATCH returns', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _OrdersApi();
    api.patchBlock = Completer<void>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: MaterialApp(
          theme: AppTheme.web(),
          home: const SellerOrdersScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('전체'));
    await tester.pump();

    expect(find.text('백산수'), findsOneWidget);
    expect(find.text('준비'), findsOneWidget);

    await tester.tap(find.text('준비'));
    await tester.pump();

    expect(api.patchCalls, 1);
    expect(api.patchBlock!.isCompleted, isFalse);
    expect(find.text('발송'), findsOneWidget);
    expect(find.text('준비'), findsNothing);
    expect(find.text('백산수'), findsOneWidget);

    api.patchBlock!.complete();
    await tester.pump();
    expect(find.text('발송'), findsOneWidget);
  });
}
