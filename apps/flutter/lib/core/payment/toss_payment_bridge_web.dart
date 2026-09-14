import 'dart:js_interop';
import 'dart:js_interop_unsafe';

bool get tossPaymentSupported => true;

/// Reloads the current URL so Cloudflare serves `toss-pay.html`.
///
/// Call only after go_router has set the path to `/toss-pay?…`. A Dart-built
/// URL passed to `location.replace` is swallowed by dart2js / PathUrlStrategy.
void reloadCurrentDocument() {
  globalContext.callMethod('eval'.toJS, 'window.location.reload()'.toJS);
}
