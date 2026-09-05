import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';

/// 구매자 보호 화면: auth bootstrap 중에는 스피너만 보여 로그인/빈 화면 flash를 막는다.
class BuyerAuthGate extends ConsumerWidget {
  const BuyerAuthGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    if (auth.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return child;
  }
}
