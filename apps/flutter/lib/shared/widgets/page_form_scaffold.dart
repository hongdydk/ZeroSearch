import 'package:flutter/material.dart';

import '../../core/layout/ui_platform.dart';

/// Centered scrollable form layout for web (max width) and mobile.
class PageFormScaffold extends StatelessWidget {
  const PageFormScaffold({
    super.key,
    required this.child,
    this.maxWidth = 720,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (!isWebUi) {
      return SingleChildScrollView(
        padding: padding,
        child: child,
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SingleChildScrollView(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}
