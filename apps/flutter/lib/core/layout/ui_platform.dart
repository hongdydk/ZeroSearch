import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Widget tests may set [debugForceWebUi] to exercise web layout on the VM.
@visibleForTesting
bool debugForceWebUi = false;

/// `true` on web (desktop + mobile browser) → 네이버 웹소설형 UI.
bool get isWebUi => kIsWeb || debugForceWebUi;

const double webContentMaxWidth = 1180;

/// Narrow mobile browser breakpoint (matches feed grid).
const double webCompactBreakpoint = 600;

bool isCompactWeb(BuildContext context) {
  if (!isWebUi) return false;
  return MediaQuery.sizeOf(context).width < webCompactBreakpoint;
}

bool isWideWeb(BuildContext context) => isWebUi && !isCompactWeb(context);
