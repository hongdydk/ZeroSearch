import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/routing/configure_url_strategy_stub.dart'
    if (dart.library.js_interop) 'core/routing/configure_url_strategy_web.dart';

void main() {
  configureUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: ShoppingMallApp()));
}
