bool get tossPaymentSupported => false;

Future<void> requestTossCardPayment({
  required String clientKey,
  required String customerKey,
  required String orderId,
  required String orderName,
  required int amount,
  required String successUrl,
  required String failUrl,
}) {
  throw UnsupportedError('토스 결제는 웹에서만 지원합니다.');
}
