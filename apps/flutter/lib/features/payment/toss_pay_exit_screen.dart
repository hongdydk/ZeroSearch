import 'package:flutter/material.dart';

import '../../core/payment/toss_payment_bridge.dart';

/// Hop screen: URL is already `/toss-pay?…` via go_router; reload loads HTML.
class TossPayExitScreen extends StatefulWidget {
  const TossPayExitScreen({super.key});

  @override
  State<TossPayExitScreen> createState() => _TossPayExitScreenState();
}

class _TossPayExitScreenState extends State<TossPayExitScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reloadCurrentDocument();
    });
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
              onPressed: reloadCurrentDocument,
              child: const Text('이동되지 않으면 여기를 누르세요'),
            ),
          ],
        ),
      ),
    );
  }
}
