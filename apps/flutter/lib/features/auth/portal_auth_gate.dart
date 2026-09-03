import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/login_portal.dart';
import '../../core/providers/app_providers.dart';
import 'login_screen.dart';

/// 포털 세션이 맞을 때만 [child]를 보여 주고, 아니면 해당 포털 로그인 화면을 띄운다.
class PortalAuthGate extends ConsumerWidget {
  const PortalAuthGate({
    super.key,
    required this.portal,
    required this.child,
  });

  final LoginPortal portal;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    if (auth.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (auth.valueOrNull?.isPortal(portal) == true) {
      return child;
    }
    return LoginScreen(portal: portal);
  }
}
