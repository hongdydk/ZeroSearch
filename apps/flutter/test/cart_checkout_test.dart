import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_mall/core/models/models.dart';
import 'package:shopping_mall/core/payment/toss_payment_bridge.dart';
import 'package:shopping_mall/core/providers/app_providers.dart';
import 'package:shopping_mall/features/cart/cart_screen.dart';
import 'package:shopping_mall/features/checkout/checkout_screen.dart';

CartModel _cart() {
  return CartModel(
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
}

class _FixedCartNotifier extends CartNotifier {
  _FixedCartNotifier(this._cart);

  final CartModel _cart;

  @override
  Future<CartModel> build() async => _cart;

  @override
  Future<void> refreshAuthoritative() async {}

  @override
  Future<void> flushPending() async {}
}

void main() {
  test('Toss payment is disabled outside web', () {
    expect(tossPaymentSupported, isFalse);
  });

  testWidgets('cart opens checkout instead of charging', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartProvider.overrideWith(() => _FixedCartNotifier(_cart())),
        ],
        child: const MaterialApp(home: CartScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('주문하기'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '주문하기'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('checkout disables pay without address off web', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartProvider.overrideWith(() => _FixedCartNotifier(_cart())),
          addressesProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(home: Scaffold(body: CheckoutScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('등록된 배송지가 없습니다. 결제 전에 주소를 추가해 주세요.'), findsOneWidget);
    expect(find.text('토스 결제는 현재 웹에서만 지원합니다.'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '토스로 결제하기'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('checkout disables pay when address exists off web', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartProvider.overrideWith(() => _FixedCartNotifier(_cart())),
          addressesProvider.overrideWith(
            (ref) async => [
              ShippingAddressModel(
                id: 'a1',
                recipientName: '홍길동',
                phone: '01012345678',
                zonecode: '12345',
                address: '서울 강남구 테헤란로 1',
                detailAddress: '101호',
                isDefault: true,
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: CheckoutScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('홍길동'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '토스로 결제하기'),
    );
    expect(button.onPressed, isNull);
  });
}
