import 'package:flutter/material.dart';

import '../../core/layout/ui_platform.dart';

/// 웹에서 본문을 중앙 정렬·최대 너비로 제한한다. 폰 프레임 없음.
class WebContentFrame extends StatelessWidget {
  const WebContentFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isWebUi) return child;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: webContentMaxWidth),
        child: child,
      ),
    );
  }
}
