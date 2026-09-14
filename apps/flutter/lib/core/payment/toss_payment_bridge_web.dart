import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('goToTossPay')
external void _goToTossPay(JSString url);

bool get tossPaymentSupported => true;

Future<void> requestTossCardPayment({
  required String clientKey,
  required String customerKey,
  required String orderId,
  required String orderName,
  required int amount,
  required String successUrl,
  required String failUrl,
}) async {
  // Cloudflare Pages pretty-URL: /toss-pay.html → 308 /toss-pay
  final uri = Uri(
    path: '/toss-pay',
    queryParameters: {
      'clientKey': clientKey,
      'customerKey': customerKey,
      'orderId': orderId,
      'orderName': orderName,
      'amount': '$amount',
      'successUrl': successUrl,
      'failUrl': failUrl,
    },
  );
  if (!globalContext.has('goToTossPay')) {
    throw StateError('결제 페이지로 이동하지 못했습니다. 페이지를 새로고침해 주세요.');
  }
  _goToTossPay(uri.toString().toJS);
}
