import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shopping_mall/core/models/models.dart';
import 'package:shopping_mall/core/network/api_client.dart';
import 'package:shopping_mall/core/providers/app_providers.dart';
import 'package:shopping_mall/core/routing/app_router.dart';
import 'package:shopping_mall/core/storage/token_storage.dart';
import 'package:shopping_mall/core/theme/app_theme.dart';

class _Api extends ApiClient {
  _Api() : super(tokenReader: () async => null);

  @override
  Future<UserModel> me() async => UserModel(
        id: 'u1',
        email: 't@example.com',
        displayName: 'T',
      );

  @override
  Future<CatalogProductPageModel> catalogProducts({
    String? q,
    String? category,
    String? categoryMajor,
    String? categoryMid,
    String? flavor,
    int? volumeMlMin,
    int? volumeMlMax,
    int offset = 0,
    int limit = 50,
  }) async =>
      CatalogProductPageModel(items: const [], total: 0);
}

class _Tokens extends TokenStorage {
  @override
  Future<String?> read() async => null;

  @override
  Future<String?> readPortal() async => null;

  @override
  Future<void> write(String token) async {}

  @override
  Future<void> writePortal(String portal) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  testWidgets('table major tap navigates to mid list', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    late GoRouter router;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(_Api()),
          tokenStorageProvider.overrideWithValue(_Tokens()),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(routerProvider);
            return MaterialApp.router(
              theme: AppTheme.web(),
              routerConfig: router,
            );
          },
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.textContaining('식탁'), findsWidgets);
    expect(find.text('면류'), findsWidgets);

    await tester.tap(find.text('면류').first);
    await tester.pumpAndSettle();

    expect(find.text('봉지면'), findsOneWidget);
    expect(find.text('용기면'), findsOneWidget);
    expect(router.state.uri.queryParameters['major'], '면류');
  });

  testWidgets('mid tap and browse back step down', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    late GoRouter router;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(_Api()),
          tokenStorageProvider.overrideWithValue(_Tokens()),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(routerProvider);
            return MaterialApp.router(
              theme: AppTheme.web(),
              routerConfig: router,
            );
          },
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('면류').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('봉지면'));
    await tester.pumpAndSettle();

    expect(router.state.uri.queryParameters['mid'], '봉지면');
    expect(find.widgetWithText(TextButton, '면류'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '면류'));
    await tester.pumpAndSettle();

    expect(router.state.uri.queryParameters['mid'], isNull);
    expect(router.state.uri.queryParameters['major'], '면류');
    expect(find.text('봉지면'), findsOneWidget);
    expect(find.text('용기면'), findsOneWidget);
  });
}
