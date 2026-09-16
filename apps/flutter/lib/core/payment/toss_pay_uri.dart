/// In-app path for the standalone Toss launcher (`web/toss-pay.html`).
/// Cloudflare serves this path as HTML. Do not use `.html` — a 308 strips query.
const tossPayPath = '/toss-pay';

bool isTossPayDocumentPath(String pathname) =>
    pathname == tossPayPath || pathname == '$tossPayPath/';

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
    path: tossPayPath,
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
