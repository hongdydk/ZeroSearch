import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shopping_mall/core/auth/login_portal.dart';
import 'package:shopping_mall/core/layout/ui_platform.dart';
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
    String? l2Tag,
    String? storage,
    String? brand,
    String? menu,
    String? flavor,
    int? volumeMlMin,
    int? volumeMlMax,
    int offset = 0,
    int limit = 50,
  }) async {
    if (l1Tag == '라면/면류' && l2Tag == '봉지라면' && (brand == '농심' || menu == '신라면')) {
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
    String? l1Tag,
    String? l2Tag,
    String? q,
    String? storage,
  }) async {
    if (l1Tag == '생수/음료') {
      return GuestL1FacetsModel(
        l1Tag: l1Tag ?? '',
        l2Tag: l2Tag ?? '',
        defaultAxis: 'brand',
        brands: const [],
        menus: const [],
      );
    }
    if (l2Tag != '봉지라면') {
      return GuestL1FacetsModel(
        l1Tag: l1Tag ?? '',
        l2Tag: l2Tag ?? '',
        defaultAxis: 'brand',
        brands: const [],
        menus: const [],
      );
    }
    return GuestL1FacetsModel(
      l1Tag: l1Tag ?? '',
      l2Tag: l2Tag ?? '',
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

  @override
  Future<CatalogOfferBrowsePageModel> catalogOffers({
    String? q,
    String? category,
    String? categoryMajor,
    String? categoryMid,
    String? l1Tag,
    String? l2Tag,
    String? storage,
    String? brand,
    String? menu,
    String? flavor,
    int? volumeMlMin,
    int? volumeMlMax,
    int offset = 0,
    int limit = 50,
  }) async {
    if (l1Tag == '라면/면류' && l2Tag == '봉지라면') {
      return CatalogOfferBrowsePageModel(
        items: [
          CatalogOfferBrowseModel(
            id: 'offer-official',
            catalogProductId: 'cat-shin',
            title: '신라면',
            manufacturer: '농심',
            priceCredits: 3900,
            stock: 10,
            seller: SellerSummaryModel(
              id: 's-official',
              shopName: '공식 스토어',
              slug: 'official',
              sellerType: 'platform',
            ),
          ),
          CatalogOfferBrowseModel(
            id: 'offer-mart',
            catalogProductId: 'cat-shin',
            title: '신라면',
            manufacturer: '농심',
            priceCredits: 4200,
            stock: 4,
            seller: SellerSummaryModel(
              id: 's-mart',
              shopName: '면사랑마트',
              slug: 'myeon-sarang',
              sellerType: 'merchant',
            ),
          ),
        ],
        total: 2,
      );
    }
    if (l1Tag == '생수/음료') {
      return CatalogOfferBrowsePageModel(items: [], total: 0);
    }
    return CatalogOfferBrowsePageModel(items: [], total: 0);
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
  testWidgets('guest L1 tap opens L2 picker before axis', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = await _pumpMall(tester);
    expect(find.text('라면/면류'), findsWidgets);

    await tester.tap(find.text('라면/면류').first);
    await tester.pumpAndSettle();

    expect(router.state.uri.queryParameters['l1'], '라면/면류');
    expect(router.state.uri.queryParameters['l2'], isNull);
    expect(find.text('봉지라면'), findsOneWidget);
    expect(find.text('컵·용기면'), findsOneWidget);
    expect(find.text('브랜드부터'), findsNothing);
    expect(find.text('농심'), findsNothing);

    await tester.tap(find.text('봉지라면'));
    await tester.pumpAndSettle();

    expect(router.state.uri.queryParameters['l2'], '봉지라면');
    expect(find.text('브랜드부터'), findsWidgets);
    expect(find.text('메뉴부터'), findsWidgets);
    expect(find.text('판매자 오퍼'), findsWidgets);
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
    await tester.tap(find.text('봉지라면'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('농심'));
    await tester.pumpAndSettle();

    expect(router.state.uri.queryParameters['brand'], '농심');
    expect(router.state.uri.queryParameters['l2'], '봉지라면');
    expect(find.text('농심 신라면'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '봉지라면'));
    await tester.pumpAndSettle();

    expect(router.state.uri.queryParameters['brand'], isNull);
    expect(router.state.uri.queryParameters['l1'], '라면/면류');
    expect(router.state.uri.queryParameters['l2'], '봉지라면');
    expect(find.text('브랜드부터'), findsWidgets);
  });

  testWidgets('L1 brand URL keeps l1Tag so untagged housewares do not appear', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = await _pumpMall(tester);
    router.go('/?l1=생수/음료&l2=생수&axis=brand&brand=그린에이드');
    await tester.pumpAndSettle();

    expect(router.state.uri.queryParameters['l1'], '생수/음료');
    expect(router.state.uri.queryParameters['l2'], '생수');
    expect(router.state.uri.queryParameters['brand'], '그린에이드');
    expect(find.text('커피필터'), findsNothing);
    expect(find.textContaining('조건에 맞는 상품이 없습니다'), findsOneWidget);
  });

  testWidgets('L1 seller axis lists one card per offer with seller and price', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = await _pumpMall(tester);
    await tester.tap(find.text('라면/면류').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('봉지라면'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('판매자 오퍼').first);
    await tester.pumpAndSettle();

    expect(router.state.uri.queryParameters['l1'], '라면/면류');
    expect(router.state.uri.queryParameters['l2'], '봉지라면');
    expect(router.state.uri.queryParameters['axis'], 'seller');
    expect(find.text('공식 스토어'), findsOneWidget);
    expect(find.text('면사랑마트'), findsOneWidget);
    expect(find.text('3,900원'), findsOneWidget);
    expect(find.text('4,200원'), findsOneWidget);
    expect(find.text('농심'), findsNothing);
  });

  testWidgets('L1 seller axis with untagged brand stays empty', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = await _pumpMall(tester);
    router.go('/?l1=생수/음료&l2=생수&axis=seller');
    await tester.pumpAndSettle();

    expect(router.state.uri.queryParameters['l1'], '생수/음료');
    expect(router.state.uri.queryParameters['l2'], '생수');
    expect(router.state.uri.queryParameters['axis'], 'seller');
    expect(find.text('커피필터'), findsNothing);
    expect(find.textContaining('공개 오퍼가 없습니다'), findsOneWidget);
  });

  testWidgets('mobile search axis keeps the search field', (tester) async {
    debugForceWebUi = false;
    addTearDown(() => debugForceWebUi = false);
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = await _pumpMall(tester);
    router.go('/?q=신라면&axis=brand');
    await tester.pumpAndSettle();

    expect(router.state.uri.queryParameters['q'], '신라면');
    expect(find.text('브랜드부터'), findsWidgets);
    expect(find.byType(TextField), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '신라면');
  });
}
