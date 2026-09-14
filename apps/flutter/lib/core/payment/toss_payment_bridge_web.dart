import 'dart:js_interop';

@JS('requestTossCardPayment')
external JSPromise<JSAny?> _requestTossCardPayment(
  String clientKey,
  String customerKey,
  String orderId,
  String orderName,
  int amount,
  String successUrl,
  String failUrl,
);

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
  await _requestTossCardPayment(
    clientKey,
    customerKey,
    orderId,
    orderName,
    amount,
    successUrl,
    failUrl,
  ).toDart;
}
