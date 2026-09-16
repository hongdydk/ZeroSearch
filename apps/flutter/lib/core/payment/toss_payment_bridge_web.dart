import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'toss_pay_uri.dart';

bool get tossPaymentSupported => true;

/// Reloads so Cloudflare serves `toss-pay.html`, only if the real document
/// path is already `/toss-pay`. A Dart-built URL passed to `location.replace`
/// is swallowed by dart2js / PathUrlStrategy.
void reloadCurrentDocument() {
  hopToTossPayHtml();
}

/// Syncs `window.location` to `/toss-pay?…` then reloads the document.
///
/// go_router can paint the exit screen before PathUrlStrategy updates the
/// document URL. Reloading then would re-fetch `/checkout` (주문서).
/// `history.replaceState` updates the bar without a Dart `location.replace`;
/// reload runs only after [isTossPayDocumentPath] is true.
void hopToTossPayHtml({String search = ''}) {
  final query = search.isEmpty
      ? ''
      : (search.startsWith('?') ? search : '?$search');
  final targetJson = query.isEmpty ? 'null' : jsonEncode('$tossPayPath$query');
  globalContext.callMethod(
    'eval'.toJS,
    '''
(function () {
  var target = $targetJson;
  var path = window.location.pathname;
  if (target && path !== '/toss-pay' && path !== '/toss-pay/') {
    history.replaceState(history.state, '', target);
  }
  path = window.location.pathname;
  if (path === '/toss-pay' || path === '/toss-pay/') {
    window.location.reload();
  }
})()
'''
        .toJS,
  );
}
