import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Bottom-nav 루트 경로 — 시스템 뒤로가기 시 여기서 홈(/) 또는 앱 종료.
bool isShellTabRoot(String location) {
  return location == '/' ||
      location == '/cart' ||
      location == '/orders' ||
      location == '/membership' ||
      location == '/settings' ||
      location == '/login' ||
      location == '/register' ||
      location == '/seller' ||
      location == '/admin';
}

/// Android 시스템 뒤로가기 / iOS 스와이프 백 공통 처리.
void handleAppBackNavigation(BuildContext context) {
  final router = GoRouter.of(context);
  final location = GoRouterState.of(context).matchedLocation;

  if (kDebugMode) {
    debugPrint('[back] location=$location canPop=${router.canPop()}');
  }

  if (location != '/' &&
      location != '/login' &&
      location != '/seller' &&
      location != '/admin' &&
      isShellTabRoot(location)) {
    router.go('/');
    return;
  }

  if (router.canPop()) {
    router.pop();
    return;
  }

  if (location.startsWith('/seller/')) {
    router.go('/seller');
    return;
  }
  if (location.startsWith('/admin/')) {
    router.go('/admin');
    return;
  }

  if (!isShellTabRoot(location)) {
    router.go('/');
    return;
  }

  if (location == '/') {
    _confirmExitApp(context);
    return;
  }

  SystemNavigator.pop();
}

Future<void> _confirmExitApp(BuildContext context) async {
  final exit = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('앱 종료'),
      content: const Text('앱을 종료하시겠습니까?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('종료'),
        ),
      ],
    ),
  );
  if (exit == true && context.mounted) {
    SystemNavigator.pop();
  }
}

/// 상세 화면 진입 시 스택에 쌓기 (뒤로가기 동작용).
void openDetailRoute(BuildContext context, String path) {
  final current = GoRouterState.of(context).uri.toString();
  if (current == path) return;
  context.push(path);
}
