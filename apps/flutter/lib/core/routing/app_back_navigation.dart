import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../catalog/browse_location.dart';

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
  final state = GoRouterState.of(context);
  final location = state.matchedLocation;

  if (kDebugMode) {
    debugPrint('[back] location=$location canPop=${router.canPop()}');
  }

  // Buyer auth (/login, /register) and other shell tabs: leave to home.
  // Do not SystemNavigator.pop() here — on mobile web that is a silent no-op.
  if (location != '/' &&
      location != '/seller' &&
      location != '/admin' &&
      isShellTabRoot(location)) {
    if (router.canPop()) {
      router.pop();
      return;
    }
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
    if (hasBrowseQuery(state.uri)) {
      router.go(browseStepDown(state.uri));
      return;
    }
    _confirmExitApp(context);
    return;
  }

  // Portal roots (/seller, /admin) with empty stack.
  SystemNavigator.pop();
}

/// 식탁·상세 앱 내 뒤로 — 상세는 pop, 식탁 browse는 URL step-down.
void popBrowseOrHome(BuildContext context) {
  final router = GoRouter.of(context);
  final state = GoRouterState.of(context);
  if (router.canPop()) {
    router.pop();
    return;
  }
  if (hasBrowseQuery(state.uri)) {
    router.go(browseStepDown(state.uri));
    return;
  }
  router.go('/');
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
