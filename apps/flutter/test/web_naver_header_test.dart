import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shopping_mall/core/auth/login_portal.dart';
import 'package:shopping_mall/core/cart/guest_cart.dart';
import 'package:shopping_mall/core/catalog/browse_location.dart';
import 'package:shopping_mall/core/layout/ui_platform.dart';
import 'package:shopping_mall/core/models/models.dart';
import 'package:shopping_mall/core/network/api_client.dart';
import 'package:shopping_mall/core/providers/app_providers.dart';
import 'package:shopping_mall/core/storage/token_storage.dart';
import 'package:shopping_mall/core/theme/app_theme.dart';
import 'package:shopping_mall/shared/widgets/adaptive_shell.dart';
import 'package:shopping_mall/shared/widgets/web/web_naver_header.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _HeaderTestApiClient extends ApiClient {
  _HeaderTestApiClient({this.cartState}) : super(tokenReader: () async => null);

  final CartModel? cartState;

  @override
  Future<UserModel> me() async =>
      UserModel(id: 'user-1', email: 'test@example.com', displayName: 'Tester');

  @override
  Future<CartModel> cart() async =>
      cartState ?? CartModel(items: const [], totalCredits: 0);

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
  }) async => CatalogProductPageModel(
    items: [
      CatalogProductModel(
        id: 'cat-1',
        title: '백산수',
        manufacturer: '농심',
        category: '일반생수',
        offerCount: 3,
        priceUnit: 'ml',
        displayPriceLabel: 'L당 420',
        medianUnitPrice: 0.42,
      ),
      CatalogProductModel(
        id: 'cat-2',
        title: '신라면',
        manufacturer: '농심',
        category: '국물봉지라면',
        offerCount: 2,
        priceUnit: 'credits',
        displayPriceLabel: '890',
        medianPriceCredits: 890,
      ),
    ],
    total: 2,
  );
}

class _LoggedInTokenStorage extends TokenStorage {
  @override
  Future<String?> readPortalToken(LoginPortal portal) async =>
      portal == LoginPortal.buyer ? 'test-token' : null;

  @override
  Future<String?> read() async => 'test-token';

  @override
  Future<String?> readPortal() async => 'buyer';

  @override
  Future<void> write(String token) async {}

  @override
  Future<void> writePortal(String portal) async {}

  @override
  Future<void> loadLeftAts() async {}

  @override
  Future<void> clear() async {}
}

class _LoggedOutTokenStorage extends TokenStorage {
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
  Future<void> loadLeftAts() async {}

  @override
  Future<void> clear() async {}
}

Widget _headerHarness({
  required bool loggedIn,
  String location = '/',
  ApiClient? api,
}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api ?? _HeaderTestApiClient()),
      tokenStorageProvider.overrideWithValue(
        loggedIn ? _LoggedInTokenStorage() : _LoggedOutTokenStorage(),
      ),
      guestCartStorageProvider.overrideWithValue(MemoryGuestCartStore()),
    ],
    child: MaterialApp(
      theme: AppTheme.web(),
      home: Scaffold(
        body: Column(
          children: [
            WebNaverHeader(location: location),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    ),
  );
}

void _setLogicalViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  setUp(() {
    debugForceWebUi = false;
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    debugForceWebUi = false;
  });

  testWidgets('WebNaverHeader shows brand and cart without MY dropdown', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_headerHarness(loggedIn: true));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('제로 서치'), findsOneWidget);
    expect(find.text('MY'), findsNothing);
    expect(find.text('장바구니'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
  });

  testWidgets(
    'Services menu has orders, membership, settings, logout when logged in',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_headerHarness(loggedIn: true));
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.text('≡'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(PopupMenuItem<String>, '홈'), findsNothing);
      expect(find.widgetWithText(PopupMenuItem<String>, '주문'), findsOneWidget);
      expect(find.widgetWithText(PopupMenuItem<String>, '멤버십'), findsOneWidget);
      expect(find.widgetWithText(PopupMenuItem<String>, '설정'), findsOneWidget);
      expect(
        find.widgetWithText(PopupMenuItem<String>, '판매자 센터'),
        findsOneWidget,
      );
      expect(find.widgetWithText(PopupMenuItem<String>, '관리자'), findsOneWidget);
      expect(
        find.widgetWithText(PopupMenuItem<String>, '로그아웃'),
        findsOneWidget,
      );
    },
  );

  testWidgets('compact web shows search on home catalog', (tester) async {
    debugForceWebUi = true;
    _setLogicalViewport(tester, const Size(390, 844));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(_HeaderTestApiClient()),
          tokenStorageProvider.overrideWithValue(_LoggedOutTokenStorage()),
          guestCartStorageProvider.overrideWithValue(MemoryGuestCartStore()),
        ],
        child: MaterialApp(
          theme: AppTheme.web(),
          home: const WebShell(child: SizedBox.shrink()),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(AppBar), findsNothing);
    expect(find.text('제로 서치'), findsOneWidget);
    expect(find.text('밥, 떡, 쌀…'), findsOneWidget);
  });

  test('mall buyer search is on catalog, product, cart, checkout', () {
    expect(showsMallBuyerSearch('/'), isTrue);
    expect(showsMallBuyerSearch('/catalog/abc'), isTrue);
    expect(showsMallBuyerSearch('/products/p1'), isTrue);
    expect(showsMallBuyerSearch('/cart'), isTrue);
    expect(showsMallBuyerSearch('/checkout'), isTrue);
    expect(showsMallBuyerSearch('/orders'), isFalse);
    expect(showsMallBuyerSearch('/admin'), isFalse);
    expect(showsMallBuyerSearch('/seller'), isFalse);
  });

  testWidgets('search field is visible on mall shopping pages', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final location in [
      '/',
      '/catalog/cat-1',
      '/products/p1',
      '/cart',
      '/checkout',
    ]) {
      await tester.pumpWidget(_headerHarness(loggedIn: false, location: location));
      await tester.pump();
      expect(find.text('밥, 떡, 쌀…'), findsOneWidget, reason: location);
    }

    await tester.pumpWidget(_headerHarness(loggedIn: false, location: '/orders'));
    await tester.pump();
    expect(find.text('밥, 떡, 쌀…'), findsNothing);
  });

  testWidgets('header search submit goes to catalog query', (tester) async {
    debugForceWebUi = true;
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    late GoRouter router;
    router = GoRouter(
      initialLocation: '/catalog/cat-1',
      routes: [
        ShellRoute(
          builder: (context, state, child) => WebShell(child: child),
          routes: [
            GoRoute(path: '/', builder: (_, _) => const Text('home-catalog')),
            GoRoute(
              path: '/catalog/:id',
              builder: (_, _) => const Text('catalog-detail'),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(_HeaderTestApiClient()),
          tokenStorageProvider.overrideWithValue(_LoggedOutTokenStorage()),
          guestCartStorageProvider.overrideWithValue(MemoryGuestCartStore()),
        ],
        child: MaterialApp.router(
          theme: AppTheme.web(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('catalog-detail'), findsOneWidget);
    expect(find.text('밥, 떡, 쌀…'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '떡갈비');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/');
    expect(router.state.uri.queryParameters['q'], '떡갈비');
    expect(find.text('home-catalog'), findsOneWidget);
  });

  testWidgets('header login from catalog passes next', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    late GoRouter router;
    router = GoRouter(
      initialLocation: '/catalog/cat-1',
      routes: [
        ShellRoute(
          builder: (context, state, child) => WebShell(child: child),
          routes: [
            GoRoute(
              path: '/catalog/:id',
              builder: (_, _) => const Text('catalog-detail'),
            ),
            GoRoute(
              path: '/login',
              builder: (_, state) =>
                  Text('login next=${state.uri.queryParameters['next']}'),
            ),
          ],
        ),
      ],
    );

    debugForceWebUi = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(_HeaderTestApiClient()),
          tokenStorageProvider.overrideWithValue(_LoggedOutTokenStorage()),
          guestCartStorageProvider.overrideWithValue(MemoryGuestCartStore()),
        ],
        child: MaterialApp.router(
          theme: AppTheme.web(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('로그인'));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/login');
    expect(router.state.uri.queryParameters['next'], '/catalog/cat-1');
  });

  testWidgets('header login on login page keeps next', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    late GoRouter router;
    router = GoRouter(
      initialLocation: '/login?next=${Uri.encodeQueryComponent('/catalog/cat-1')}',
      routes: [
        ShellRoute(
          builder: (context, state, child) => WebShell(child: child),
          routes: [
            GoRoute(
              path: '/login',
              builder: (_, state) =>
                  Text('login next=${state.uri.queryParameters['next']}'),
            ),
          ],
        ),
      ],
    );

    debugForceWebUi = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(_HeaderTestApiClient()),
          tokenStorageProvider.overrideWithValue(_LoggedOutTokenStorage()),
          guestCartStorageProvider.overrideWithValue(MemoryGuestCartStore()),
        ],
        child: MaterialApp.router(
          theme: AppTheme.web(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('로그인').first);
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/login');
    expect(router.state.uri.queryParameters['next'], '/catalog/cat-1');
  });

  testWidgets('header cart badge shows item qty', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _headerHarness(
        loggedIn: true,
        api: _HeaderTestApiClient(
          cartState: CartModel(
            items: [
              CartItemModel(
                id: '1',
                productId: 'p1',
                productTitle: '백산수',
                qty: 3,
                priceCredits: 1200,
                lineTotalCredits: 3600,
                sellerId: 's1',
                shopName: '공식 스토어',
                sellerType: 'platform',
              ),
            ],
            totalCredits: 3600,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('장바구니'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });
}
