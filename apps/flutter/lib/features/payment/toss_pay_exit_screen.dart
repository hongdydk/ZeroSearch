import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/payment/toss_payment_bridge.dart';

/// Hop screen: go_router is on `/toss-pay?…`; hop loads Cloudflare HTML.
class TossPayExitScreen extends StatefulWidget {
  const TossPayExitScreen({super.key});

  @override
  State<TossPayExitScreen> createState() => _TossPayExitScreenState();
}

class _TossPayExitScreenState extends State<TossPayExitScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hop());
  }

  String _search() {
    try {
      final uri = GoRouterState.of(context).uri;
      if (uri.hasQuery) return '?${uri.query}';
    } catch (_) {}
    return '';
  }

  void _hop() {
    if (!mounted) return;
    hopToTossPayHtml(search: _search());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('결제창으로 이동 중…'),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _hop,
              child: const Text('이동되지 않으면 여기를 누르세요'),
            ),
          ],
        ),
      ),
    );
  }
}
