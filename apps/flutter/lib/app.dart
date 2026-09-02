import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/layout/ui_platform.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

class ShoppingMallApp extends ConsumerWidget {
  const ShoppingMallApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Shopping Mall',
      theme: AppTheme.forPlatform(),
      routerConfig: router,
      builder: (context, child) {
        if (!isWebUi) return child ?? const SizedBox.shrink();
        return ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
