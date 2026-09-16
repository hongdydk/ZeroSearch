import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shopping_mall/core/auth/login_portal.dart';
import 'package:shopping_mall/core/models/models.dart';
import 'package:shopping_mall/core/network/api_client.dart';
import 'package:shopping_mall/core/providers/app_providers.dart';
import 'package:shopping_mall/core/storage/token_storage.dart';
import 'package:shopping_mall/core/theme/app_theme.dart';
import 'package:shopping_mall/features/auth/portal_auth_gate.dart';
import 'package:shopping_mall/shared/widgets/portal_shell.dart';
import 'package:shopping_mall/shared/widgets/web/web_naver_header.dart';

class _Api extends ApiClient {
  _Api(this.meQueue) : super(tokenReader: () async => null);

  final List<UserModel> meQueue;
  int _i = 0;

  @override
  Future<UserModel> me() async => meQueue[_i++];
}

class _Tokens extends TokenStorage {
  _Tokens(this.store);

  final Map<LoginPortal, String?> store;
  final Map<String, String> kv = {};

  @override
  Future<String?> readPortalToken(LoginPortal portal) async => store[portal];

  @override
  Future<void> writePortalToken(LoginPortal portal, String token) async {
    store[portal] = token;
  }

  @override
  Future<void> clearPortal(LoginPortal portal) async {
    store[portal] = null;
    await clearPortalLeft(portal);
  }

  @override
  Future<String?> storageGet(String key) async => kv[key];

  @override
  Future<void> storageSet(String key, String value) async {
    kv[key] = value;
  }

  @override
  Future<void> storageRemove(String key) async {
    kv.remove(key);
  }
}

Widget _harness({
  required _Tokens tokens,
  required ApiClient api,
}) {
  late GoRouter router;
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      tokenStorageProvider.overrideWithValue(tokens),
    ],
    child: Consumer(
      builder: (context, ref, _) {
        router = GoRouter(
          initialLocation: '/admin',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(
                body: Column(
                  children: [
                    WebNaverHeader(location: '/'),
                    Text('몰 카탈로그'),
                  ],
                ),
              ),
            ),
            GoRoute(
              path: '/admin',
              builder: (_, _) => const PortalShell(
                title: '관리자',
                homePath: '/admin',
                child: PortalAuthGate(
                  portal: LoginPortal.admin,
                  child: Text('관리자 본문'),
                ),
              ),
            ),
          ],
        );
        return MaterialApp.router(
          theme: AppTheme.web(),
          routerConfig: router,
        );
      },
    ),
  );
}

void main() {
  final adminUser = UserModel(
    id: 'u1',
    email: 'admin@mall.local',
    displayName: '관리자계정',
    isAdmin: true,
  );
  final buyerUser = UserModel(
    id: 'u2',
    email: 'buyer@mall.local',
    displayName: '구매자계정',
  );

  testWidgets('admin 로그인 후 쇼핑몰은 게스트이고 /admin 세션은 남는다', (tester) async {
    final tokens = _Tokens({LoginPortal.admin: 'admin-tok'});
    final api = _Api([adminUser]);

    await tester.pumpWidget(_harness(tokens: tokens, api: api));
    await tester.pumpAndSettle();

    expect(find.text('관리자 본문'), findsOneWidget);

    await tester.tap(find.text('쇼핑몰'));
    await tester.pumpAndSettle();

    expect(find.text('몰 카탈로그'), findsOneWidget);
    expect(find.text('로그인'), findsWidgets);
    expect(find.text('관리자계정'), findsNothing);
    expect(tokens.store[LoginPortal.admin], 'admin-tok');

    final router = tester.element(find.text('몰 카탈로그'));
    GoRouter.of(router).go('/admin');
    await tester.pumpAndSettle();

    expect(find.text('관리자 본문'), findsOneWidget);
    expect(find.text('로그아웃'), findsOneWidget);
  });

  testWidgets('쇼핑몰은 구매자 슬롯만 쓰고 관리자 토큰은 복사하지 않는다', (tester) async {
    final tokens = _Tokens({
      LoginPortal.admin: 'admin-tok',
      LoginPortal.buyer: 'buyer-tok',
    });
    final api = _Api([buyerUser, adminUser]);

    await tester.pumpWidget(_harness(tokens: tokens, api: api));
    await tester.pumpAndSettle();

    expect(find.text('관리자 본문'), findsOneWidget);

    await tester.tap(find.text('쇼핑몰'));
    await tester.pumpAndSettle();

    expect(find.text('구매자계정'), findsOneWidget);
    expect(find.text('관리자계정'), findsNothing);
    expect(tokens.store[LoginPortal.admin], 'admin-tok');
    expect(tokens.store[LoginPortal.buyer], 'buyer-tok');
  });
}
