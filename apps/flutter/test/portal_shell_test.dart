import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shopping_mall/core/models/models.dart';
import 'package:shopping_mall/core/network/api_client.dart';
import 'package:shopping_mall/core/providers/app_providers.dart';
import 'package:shopping_mall/core/storage/token_storage.dart';
import 'package:shopping_mall/shared/widgets/portal_shell.dart';

class _Api extends ApiClient {
  _Api(this.user) : super(tokenReader: () async => 'tok');

  final UserModel user;

  @override
  Future<UserModel> me() async => user;
}

class _Tokens extends TokenStorage {
  _Tokens({required this.token, required this.portal});

  String? token;
  String? portal;
  int clearCount = 0;

  @override
  Future<String?> read() async => token;

  @override
  Future<String?> readPortal() async => portal;

  @override
  Future<void> write(String value) async => token = value;

  @override
  Future<void> writePortal(String value) async => portal = value;

  @override
  Future<void> clear() async {
    clearCount += 1;
    token = null;
    portal = null;
  }
}

Widget _harness({
  required _Tokens tokens,
  required UserModel user,
}) {
  late GoRouter router;
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(_Api(user)),
      tokenStorageProvider.overrideWithValue(tokens),
    ],
    child: Consumer(
      builder: (context, ref, _) {
        router = GoRouter(
          initialLocation: '/admin',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: Text('몰 카탈로그')),
            ),
            GoRoute(
              path: '/admin',
              builder: (_, _) => const PortalShell(
                title: '관리자',
                homePath: '/admin',
                child: Text('관리자 본문'),
              ),
            ),
          ],
        );
        return MaterialApp.router(routerConfig: router);
      },
    ),
  );
}

void main() {
  final adminUser = UserModel(
    id: 'u1',
    email: 'admin@mall.local',
    isAdmin: true,
  );

  testWidgets('쇼핑몰 from admin portal logs out then opens mall as guest', (
    tester,
  ) async {
    final tokens = _Tokens(token: 'admin-tok', portal: 'admin');

    await tester.pumpWidget(_harness(tokens: tokens, user: adminUser));
    await tester.pumpAndSettle();

    expect(find.text('관리자 본문'), findsOneWidget);

    await tester.tap(find.text('쇼핑몰'));
    await tester.pumpAndSettle();

    expect(find.text('몰 카탈로그'), findsOneWidget);
    expect(tokens.clearCount, greaterThanOrEqualTo(1));
    expect(tokens.token, isNull);
    expect(tokens.portal, isNull);
  });

  testWidgets('쇼핑몰 keeps buyer portal session of a promoted admin', (
    tester,
  ) async {
    final tokens = _Tokens(token: 'buyer-tok', portal: 'buyer');

    await tester.pumpWidget(_harness(tokens: tokens, user: adminUser));
    await tester.pumpAndSettle();

    await tester.tap(find.text('쇼핑몰'));
    await tester.pumpAndSettle();

    expect(find.text('몰 카탈로그'), findsOneWidget);
    expect(tokens.clearCount, 0);
    expect(tokens.token, 'buyer-tok');
    expect(tokens.portal, 'buyer');
  });
}
