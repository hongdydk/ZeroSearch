import 'package:flutter/material.dart';

import '../../core/layout/ui_platform.dart';

/// 목업(report/mockup) 기준: 회색 캔버스 + 중앙 흰 패널(max 960px).
class MallWebCanvas extends StatelessWidget {
  const MallWebCanvas({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isWebUi) return child;

    final compact = isCompactWeb(context);
    final hPad = compact ? 0.0 : 16.0;
    final vPad = compact ? 0.0 : 12.0;

    return ColoredBox(
      color: mallWebCanvasColor,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: webContentMaxWidth,
            minHeight: MediaQuery.sizeOf(context).height,
          ),
          child: Container(
            margin: EdgeInsets.fromLTRB(hPad, vPad, hPad, vPad),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: compact
                  ? null
                  : const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ],
            ),
            child: child,
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
