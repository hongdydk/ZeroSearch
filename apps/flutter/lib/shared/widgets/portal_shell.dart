import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/ui_platform.dart';
import '../../core/providers/app_providers.dart';
import '../../core/routing/app_back_navigation.dart';
import 'web_content_frame.dart';

/// 판매자·관리자 포털 셸 — 몰 검색·장바구니·≡ 없이 브랜드 + 로그아웃만.
class PortalShell extends ConsumerWidget {
  const PortalShell({
    super.key,
    required this.title,
    required this.homePath,
    required this.child,
  });

  final String title;
  final String homePath;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider).valueOrNull;
    final loggedIn = auth?.isLoggedIn == true;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        handleAppBackNavigation(context);
      },
      child: Scaffold(
        backgroundColor: isWebUi ? mallWebCanvasColor : null,
        body: isWebUi
            ? MallWebCanvas(
                child: Column(
                  children: [
                    _PortalHeader(
                      title: title,
                      homePath: homePath,
                      showLogout: loggedIn,
                    ),
                    Expanded(child: child),
                  ],
                ),
              )
            : SafeArea(
                child: Column(
                  children: [
                    _PortalHeader(
                      title: title,
                      homePath: homePath,
                      showLogout: loggedIn,
                    ),
                    Expanded(child: child),
                  ],
                ),
              ),
      ),
    );
  }
}

class _PortalHeader extends ConsumerWidget {
  const _PortalHeader({
    required this.title,
    required this.homePath,
    required this.showLogout,
  });

  final String title;
  final String homePath;
  final bool showLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                InkWell(
                  onTap: () => context.go(homePath),
                  borderRadius: BorderRadius.circular(4),
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => context.go('/'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF6B7280),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: const Text('쇼핑몰'),
                ),
                if (showLogout)
                  TextButton(
                    onPressed: () {
                      ref.read(authStateProvider.notifier).logout();
                      context.go(homePath);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: const Text('로그아웃'),
                  ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: theme.dividerColor),
        ],
      ),
    );
  }
}
