import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_mall/core/payment/toss_pay_uri.dart';
import 'package:shopping_mall/features/payment/toss_pay_exit_screen.dart';

void main() {
  test('tossPayAppUri encodes launcher query on /toss-pay', () {
    final uri = tossPayAppUri(
      clientKey: 'test_ck',
      customerKey: 'cust-1',
      orderId: 'zs_1',
      orderName: '농심 백산수',
      amount: 12900,
      successUrl: 'https://mall.anoveli.com/payment/success',
      failUrl: 'https://mall.anoveli.com/payment/fail',
    );

    expect(uri.path, tossPayPath);
    expect(uri.queryParameters['clientKey'], 'test_ck');
    expect(uri.queryParameters['orderName'], '농심 백산수');
    expect(uri.queryParameters['amount'], '12900');
    expect(uri.toString(), startsWith('/toss-pay?'));
    expect(uri.path, isNot(contains('.html')));
  });

  test('isTossPayDocumentPath only matches the HTML hop path', () {
    expect(isTossPayDocumentPath('/toss-pay'), isTrue);
    expect(isTossPayDocumentPath('/toss-pay/'), isTrue);
    expect(isTossPayDocumentPath('/checkout'), isFalse);
    expect(isTossPayDocumentPath('/toss-pay.html'), isFalse);
  });

  testWidgets('exit screen shows waiting copy', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TossPayExitScreen()));
    await tester.pump();

    expect(find.text('결제창으로 이동 중…'), findsOneWidget);
    expect(find.text('이동되지 않으면 여기를 누르세요'), findsOneWidget);
  });
}
