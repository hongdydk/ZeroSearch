import 'dart:js_interop';
import 'dart:js_interop_unsafe';

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
  final uri = Uri(
    path: '/toss-pay.html',
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
  final location = globalContext['location'];
  if (location == null || location.isUndefinedOrNull) {
    throw StateError('결제 페이지로 이동하지 못했습니다.');
  }
  final assign = (location as JSObject)['assign'];
  if (assign == null || assign.isUndefinedOrNull) {
    throw StateError('결제 페이지로 이동하지 못했습니다.');
  }
  (assign as JSFunction).callAsFunction(location, uri.toString().toJS);
}
