import 'package:flutter/material.dart';

import '../../core/layout/ui_platform.dart';

/// 웹 셸: 좌우를 거의 채우고([webContentMaxWidth] 상한), 좁은 화면은 여백만 둔다.
class MallWebCanvas extends StatelessWidget {
  const MallWebCanvas({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isWebUi) return child;

    final compact = isCompactWeb(context);
    final hPad = compact ? 0.0 : 20.0;

    return ColoredBox(
      color: mallWebCanvasColor,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: webContentMaxWidth,
            minHeight: MediaQuery.sizeOf(context).height,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad),
            child: ColoredBox(
              color: Colors.white,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 페이지 본문만 중앙 정렬 (폼·상세 등).
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
