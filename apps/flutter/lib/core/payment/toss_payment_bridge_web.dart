import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('requestTossCardPayment')
external JSPromise<JSAny?> _requestTossCardPayment(
  JSString clientKey,
  JSString customerKey,
  JSString orderId,
  JSString orderName,
  JSNumber amount,
  JSString successUrl,
  JSString failUrl,
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
  if (!globalContext.has('requestTossCardPayment')) {
    throw StateError('토스 결제 SDK를 불러오지 못했습니다. 페이지를 새로고침해 주세요.');
  }
  try {
    await _requestTossCardPayment(
      clientKey.toJS,
      customerKey.toJS,
      orderId.toJS,
      orderName.toJS,
      amount.toJS,
      successUrl.toJS,
      failUrl.toJS,
    ).toDart;
  } catch (error) {
    throw StateError(_jsErrorMessage(error));
  }
}

String _jsErrorMessage(Object error) {
  final text = error.toString().trim();
  if (text.isEmpty ||
      text == 'Error' ||
      text.contains('Unexpected null value')) {
    return '결제창을 열지 못했습니다. 다시 시도해 주세요.';
  }
  return text.replaceFirst(RegExp(r'^Error:\s*'), '');
}
