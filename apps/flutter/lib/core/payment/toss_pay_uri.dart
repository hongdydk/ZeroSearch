/// In-app path for the standalone Toss launcher (`web/toss-pay.html`).
Uri tossPayAppUri({
  required String clientKey,
  required String customerKey,
  required String orderId,
  required String orderName,
  required int amount,
  required String successUrl,
  required String failUrl,
}) {
  return Uri(
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
}
