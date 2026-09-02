import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/ui_platform.dart';
import '../../core/providers/app_providers.dart';
import '../../core/routing/app_back_navigation.dart';
import '../../core/routing/app_router.dart';
import 'web/web_naver_header.dart';

class AdaptiveShell extends ConsumerWidget {
  const AdaptiveShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isWebUi) return WebShell(child: child);
    return MallShell(child: child);
  }
}

class WebShell extends ConsumerWidget {
  const WebShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider).valueOrNull;
    final location = _webShellLocation(context);
    final isAdmin = auth?.user?.isAdmin == true;
    final compact = isCompactWeb(context);

    return Scaffold(
      body: Column(
        children: [
          WebNaverHeader(
            location: location,
            isAdmin: isAdmin,
            compact: compact,
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class MallShell extends ConsumerWidget {
  const MallShell({super.key, required this.child});

  final Widget child;

  static const _tabs = [
    _TabDef(label: '홈', icon: Icons.home_outlined, path: '/'),
    _TabDef(label: '장바구니', icon: Icons.shopping_cart_outlined, path: '/cart'),
    _TabDef(label: '주문', icon: Icons.receipt_long_outlined, path: '/orders'),
    _TabDef(label: '멤버십', icon: Icons.card_membership_outlined, path: '/membership'),
    _TabDef(label: 'MY', icon: Icons.person_outline, path: '/settings'),
  ];

  int _indexForLocation(String location) {
    if (location == '/' || location.startsWith('/products/')) return 0;
    if (location.startsWith('/cart')) return 1;
    if (location.startsWith('/orders')) return 2;
    if (location.startsWith('/membership')) return 3;
    if (location.startsWith('/settings') || location.startsWith('/admin')) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final showBottomNav = !isSlimRoute(location) &&
        location != '/login' &&
        location != '/register';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        handleAppBackNavigation(context);
      },
      child: Scaffold(
        body: SafeArea(
          bottom: !showBottomNav,
          child: child,
        ),
        bottomNavigationBar: showBottomNav
            ? NavigationBar(
                selectedIndex: _indexForLocation(location),
                onDestinationSelected: (i) => context.go(_tabs[i].path),
                destinations: [
                  for (final t in _tabs)
                    NavigationDestination(icon: Icon(t.icon), label: t.label),
                ],
              )
            : null,
      ),
    );
  }
}

class _TabDef {
  const _TabDef({required this.label, required this.icon, required this.path});
  final String label;
  final IconData icon;
  final String path;
}

String _webShellLocation(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  return router?.state.matchedLocation ?? '/';
}
