import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_mall/core/models/models.dart';
import 'package:shopping_mall/core/payment/toss_payment_bridge.dart';
import 'package:shopping_mall/core/providers/app_providers.dart';
import 'package:shopping_mall/features/cart/cart_screen.dart';

void main() {
  test('Toss payment is disabled outside web', () {
    expect(tossPaymentSupported, isFalse);
  });

  testWidgets('cart disables toss checkout off web', (tester) async {
    final cart = CartModel(
      items: [
        CartItemModel(
          id: '1',
          productId: 'p1',
          productTitle: '농심 백산수',
          qty: 1,
          priceCredits: 12900,
          lineTotalCredits: 12900,
          sellerId: 's1',
          shopName: '공식 스토어',
          sellerType: 'platform',
        ),
      ],
      totalCredits: 12900,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartProvider.overrideWith((ref) async => cart),
        ],
        child: const MaterialApp(home: CartScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('토스 결제는 현재 웹에서만 지원합니다.'), findsOneWidget);
    expect(find.text('토스로 결제하기'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '토스로 결제하기'),
    );
    expect(button.onPressed, isNull);
  });
}
