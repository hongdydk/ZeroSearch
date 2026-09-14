import 'package:web/web.dart' as web;

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
  final uri = Uri.parse('${Uri.base.origin}/toss-pay').replace(
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
  web.window.location.replace(uri.toString());
}
