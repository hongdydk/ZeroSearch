import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shopping_mall/core/auth/login_portal.dart';
import 'package:shopping_mall/core/models/models.dart';
import 'package:shopping_mall/core/network/api_client.dart';
import 'package:shopping_mall/core/providers/app_providers.dart';
import 'package:shopping_mall/core/routing/app_router.dart';
import 'package:shopping_mall/core/storage/token_storage.dart';
import 'package:shopping_mall/core/theme/app_theme.dart';

class _Api extends ApiClient {
  _Api() : super(tokenReader: () async => null);

  @override
  Future<UserModel> me() async =>
      UserModel(id: 'u1', email: 't@example.com', displayName: 'T');

  @override
  Future<CatalogProductPageModel> catalogProducts({
    String? q,
    String? category,
    String? categoryMajor,
    String? categoryMid,
    String? l1Tag,
    String? storage,
    String? brand,
    String? menu,
    String? flavor,
    int? volumeMlMin,
    int? volumeMlMax,
    int offset = 0,
    int limit = 50,
  }) async {
    if (l1Tag == '라면/면류' && (brand == '농심' || menu == '신라면')) {
      return CatalogProductPageModel(
        items: [
          CatalogProductModel(
            id: 'cat-shin',
            title: '신라면',
            manufacturer: '농심',
            category: '국물봉지라면',
            offerCount: 2,
            priceUnit: 'credits',
            displayPriceLabel: '원',
            medianPriceCredits: 4200,
          ),
        ],
        total: 1,
      );
    }
    // L1 없이 브랜드만 오면 생활용품이 섞인다. 클라이언트는 l1Tag를 반드시 보낸다.
    if (l1Tag == null && brand == '그린에이드') {
      return CatalogProductPageModel(
        items: [
          CatalogProductModel(
            id: 'house-filter',
            title: '커피필터',
            manufacturer: '그린에이드',
            category: '필터',
            offerCount: 0,
            priceUnit: 'credits',
            displayPriceLabel: '원',
          ),
        ],
        total: 1,
      );
    }
    return CatalogProductPageModel(items: const [], total: 0);
  }

  @override
  Future<GuestL1FacetsModel> guestL1Facets({
    required String l1Tag,
    String? storage,
  }) async {
    if (l1Tag == '생수/음료') {
      return GuestL1FacetsModel(
        l1Tag: l1Tag,
        defaultAxis: 'brand',
        brands: const [],
        menus: const [],
      );
    }
    return GuestL1FacetsModel(
      l1Tag: l1Tag,
      defaultAxis: 'brand',
      brands: const [
        GuestL1FacetItem(name: '농심', count: 2),
        GuestL1FacetItem(name: '오뚜기', count: 1),
      ],
      menus: const [
        GuestL1FacetItem(name: '신라면', count: 1),
        GuestL1FacetItem(name: '진라면 매운맛', count: 1),
      ],
    );
  }
}

class _Tokens extends TokenStorage {
  @override
  Future<String?> readPortalToken(LoginPortal portal) async => null;

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

Future<GoRouter> _pumpMall(WidgetTester tester) async {
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
  return router;
}

void main() {
  testWidgets('guest L1 tap opens brand/menu axis without confirm', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = await _pumpMall(tester);
    expect(find.text('라면/면류'), findsWidgets);

    await tester.tap(find.text('라면/면류').first);
    await tester.pumpAndSettle();

    expect(router.state.uri.queryParameters['l1'], '라면/면류');
    expect(find.text('브랜드부터'), findsWidgets);
    expect(find.text('메뉴부터'), findsWidgets);
    expect(find.text('농심'), findsOneWidget);
    expect(find.text('오뚜기'), findsOneWidget);

    await tester.tap(find.text('메뉴부터').first);
    await tester.pumpAndSettle();

    expect(router.state.uri.queryParameters['axis'], 'menu');
    expect(find.text('신라면'), findsOneWidget);
    expect(find.text('농심'), findsNothing);
  });

  testWidgets('L1 brand pick shows catalog cards and back steps down', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = await _pumpMall(tester);
    await tester.tap(find.text('라면/면류').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('농심'));
    await tester.pumpAndSettle();

    expect(router.state.uri.queryParameters['brand'], '농심');
    expect(find.text('농심 신라면'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '라면/면류'));
    await tester.pumpAndSettle();

    expect(router.state.uri.queryParameters['brand'], isNull);
    expect(router.state.uri.queryParameters['l1'], '라면/면류');
    expect(find.text('브랜드부터'), findsWidgets);
  });

  testWidgets('L1 brand URL keeps l1Tag so untagged housewares do not appear', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = await _pumpMall(tester);
    router.go('/?l1=생수/음료&axis=brand&brand=그린에이드');
    await tester.pumpAndSettle();

    expect(router.state.uri.queryParameters['l1'], '생수/음료');
    expect(router.state.uri.queryParameters['brand'], '그린에이드');
    expect(find.text('커피필터'), findsNothing);
    expect(find.textContaining('조건에 맞는 상품이 없습니다'), findsOneWidget);
  });
}
