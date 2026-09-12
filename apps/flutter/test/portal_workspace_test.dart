import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shopping_mall/core/theme/app_theme.dart';
import 'package:shopping_mall/shared/widgets/portal_workspace.dart';

void main() {
  testWidgets('seller workspace shows selected mockup navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/seller/stats',
      routes: [
        GoRoute(
          path: '/seller/stats',
          builder: (_, _) => const PortalComingSoonScreen(
            role: PortalWorkspaceRole.seller,
            activePath: '/seller/stats',
            title: '통계',
            description: '운영 추이를 확인합니다.',
            items: ['기간별 주문 줄 추이'],
          ),
        ),
        GoRoute(
          path: '/seller/products',
          builder: (_, _) => const Scaffold(body: Text('오퍼 화면')),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.web(), routerConfig: router),
    );
    await tester.pumpAndSettle();

    expect(find.text('통계'), findsNWidgets(2));
    expect(find.text('준비 중'), findsOneWidget);
    expect(find.text('현재 API가 준비된 뒤 실제 데이터로 연결됩니다.'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == AppTheme.brandTeal,
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('내 오퍼'));
    await tester.pumpAndSettle();
    expect(find.text('오퍼 화면'), findsOneWidget);
  });

  testWidgets('compact workspace keeps portal navigation available', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.web(),
        home: const Scaffold(
          body: PortalWorkspaceScaffold(
            role: PortalWorkspaceRole.admin,
            activePath: '/admin',
            child: Text('관리자 본문'),
          ),
        ),
      ),
    );

    expect(find.text('운영 홈'), findsOneWidget);
    expect(find.text('관리자 본문'), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
  });
}
