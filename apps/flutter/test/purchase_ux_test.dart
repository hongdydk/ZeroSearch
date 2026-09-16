import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shopping_mall/core/auth/login_portal.dart';
import 'package:shopping_mall/core/cart/guest_cart.dart';
import 'package:shopping_mall/core/cart/guest_cart_storage.dart';
import 'package:shopping_mall/core/models/models.dart';
import 'package:shopping_mall/core/network/api_client.dart';
import 'package:shopping_mall/core/providers/app_providers.dart';
import 'package:shopping_mall/core/routing/app_router.dart';
import 'package:shopping_mall/core/storage/token_storage.dart';
import 'package:shopping_mall/features/auth/login_screen.dart';
import 'package:shopping_mall/features/cart/cart_screen.dart';
import 'package:shopping_mall/features/checkout/checkout_screen.dart';
import 'package:shopping_mall/features/product_detail/catalog_detail_screen.dart';
import 'package:shopping_mall/shared/widgets/adaptive_shell.dart';

final _seller = SellerSummaryModel(
  id: 's1',
  shopName: '공식 스토어',
  sellerType: 'platform',
);

class _MemoryTokens extends TokenStorage {
  final Map<LoginPortal, String?> _tokens = {};

  @override
  Future<String?> readPortalToken(LoginPortal portal) async => _tokens[portal];

  @override
  Future<void> writePortalToken(LoginPortal portal, String token) async {
    _tokens[portal] = token;
  }

  @override
  Future<void> clearPortal(LoginPortal portal) async {
    _tokens.remove(portal);
  }

  @override
  Future<void> loadLeftAts() async {}

  @override
  Future<void> clearPortalLeft(LoginPortal portal) async {}

  @override
  Future<String?> read() async => readPortalToken(LoginPortal.buyer);

  @override
  Future<void> write(String token) => writePortalToken(LoginPortal.buyer, token);

  @override
  Future<void> clear() async => _tokens.clear();
}

class _PurchaseApi extends ApiClient {
  _PurchaseApi() : super(tokenReader: () async => null);

  String? lastAddId;
  int? lastAddQty;
  int addCalls = 0;
  CartModel cartState = CartModel(items: const [], totalCredits: 0);

  @override
  Future<String> login(
    String email,
    String password, {
    LoginPortal portal = LoginPortal.buyer,
  }) async => 'tok';

  @override
  Future<UserModel> me() async =>
      UserModel(id: 'u1', email: 't@example.com', displayName: 'T');

  @override
  Future<CartModel> cart() async => cartState;

  @override
  Future<CartModel> addToCart(String productId, {int qty = 1}) async {
    lastAddId = productId;
    lastAddQty = qty;
    addCalls += 1;
    final existing = cartState.items.where((item) => item.productId == productId);
    final nextQty = existing.isEmpty ? qty : existing.first.qty + qty;
    cartState = CartModel(
      items: [
        CartItemModel(
          id: 'c1',
          productId: productId,
          productTitle: '백산수',
          qty: nextQty,
          priceCredits: 1200,
          lineTotalCredits: 1200 * nextQty,
          sellerId: 's1',
          shopName: '공식 스토어',
          sellerType: 'platform',
        ),
      ],
      totalCredits: 1200 * nextQty,
    );
    return cartState;
  }

  @override
  Future<ProductModel> product(String id) async => ProductModel(
        id: id,
        title: '백산수 · 2L',
        priceCredits: 1200,
        stock: 5,
        category: '일반생수',
        seller: _seller,
      );

  @override
  Future<CatalogProductDetailModel> catalogProduct(
    String id, {
    String? flavor,
    int? volumeMlMin,
    int? volumeMlMax,
  }) async => CatalogProductDetailModel(
        id: id,
        title: '백산수',
        category: '일반생수',
        offerCount: 1,
        offers: [
          CatalogOfferModel(
            id: 'offer-1',
            priceCredits: 1200,
            stock: 5,
            seller: _seller,
            optionLabel: '2L',
          ),
        ],
      );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('guest add stays on detail and fills guest cart badge', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final api = _PurchaseApi();
    final tokens = _MemoryTokens();
    final guest = GuestCartStorage();
    late GoRouter router;
    router = GoRouter(
      initialLocation: '/catalog/cat-1',
      routes: [
        ShellRoute(
          builder: (context, state, child) => WebShell(child: child),
          routes: [
            GoRoute(
              path: '/catalog/:id',
              builder: (_, state) => CatalogDetailScreen(
                catalogId: state.pathParameters['id']!,
              ),
            ),
            GoRoute(
              path: '/login',
              builder: (_, state) => LoginScreen(
                next: state.uri.queryParameters['next'],
              ),
            ),
            GoRoute(
              path: '/cart',
              builder: (_, _) => const CartScreen(),
            ),
            GoRoute(path: '/', builder: (_, _) => const Text('home-page')),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStorageProvider.overrideWithValue(tokens),
          guestCartStorageProvider.overrideWithValue(guest),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byTooltip('수량 늘리기'));
    await tester.tap(find.byTooltip('수량 늘리기'));
    await tester.pump();
    await tester.tap(find.byTooltip('수량 늘리기'));
    await tester.pump();
    await tester.tap(find.text('담기'));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/catalog/cat-1');
    expect(find.text('로그인'), findsWidgets);
    expect(find.text('이메일'), findsNothing);
    expect(api.addCalls, 0);
    expect(api.lastAddId, isNull);
    expect(find.text('장바구니에 담았습니다.'), findsOneWidget);
    expect(find.text('장바구니 보기'), findsOneWidget);
    expect(find.text('3'), findsWidgets);

    final lines = await guest.load();
    expect(lines, hasLength(1));
    expect(lines.single.productId, 'offer-1');
    expect(lines.single.qty, 3);
  });

  testWidgets('login merges guest cart into user cart without duplicate lines', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final api = _PurchaseApi();
    final tokens = _MemoryTokens();
    final guest = GuestCartStorage();
    await guest.add(
      'offer-1',
      3,
      snapshot: const GuestCartLine(
        productId: 'offer-1',
        qty: 3,
        productTitle: '백산수 · 2L',
        priceCredits: 1200,
        sellerId: 's1',
        shopName: '공식 스토어',
        sellerType: 'platform',
      ),
    );

    late GoRouter router;
    router = GoRouter(
      initialLocation: '/login?next=${Uri.encodeQueryComponent('/cart')}',
      routes: [
        ShellRoute(
          builder: (context, state, child) => WebShell(child: child),
          routes: [
            GoRoute(
              path: '/login',
              builder: (_, state) => LoginScreen(
                next: state.uri.queryParameters['next'],
              ),
            ),
            GoRoute(
              path: '/cart',
              builder: (_, _) => const CartScreen(),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStorageProvider.overrideWithValue(tokens),
          guestCartStorageProvider.overrideWithValue(guest),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'buyer@mall.local');
    await tester.enterText(fields.at(1), 'secret');
    await tester.tap(find.widgetWithText(FilledButton, '로그인'));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/cart');
    expect(api.addCalls, 1);
    expect(api.lastAddId, 'offer-1');
    expect(api.lastAddQty, 3);
    expect(await guest.load(), isEmpty);
    expect(find.text('백산수'), findsOneWidget);
    expect(find.text('3'), findsWidgets);

    await mergeGuestCartIntoUser(api: api, guest: guest);
    expect(api.addCalls, 1);
    expect(api.cartState.items, hasLength(1));
    expect(api.cartState.items.single.qty, 3);
  });

  testWidgets('guest cart can view update remove without login', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final api = _PurchaseApi();
    final guest = GuestCartStorage();
    await guest.add(
      'offer-1',
      2,
      snapshot: const GuestCartLine(
        productId: 'offer-1',
        qty: 2,
        productTitle: '백산수 · 2L',
        priceCredits: 1200,
        sellerId: 's1',
        shopName: '공식 스토어',
        sellerType: 'platform',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStorageProvider.overrideWithValue(_MemoryTokens()),
          guestCartStorageProvider.overrideWithValue(guest),
        ],
        child: const MaterialApp(home: CartScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('백산수 · 2L'), findsOneWidget);
    expect(find.text('주문·결제는 로그인 후 진행됩니다.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect((await guest.load()).single.qty, 3);
    expect(api.addCalls, 0);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(await guest.load(), isEmpty);
    expect(find.text('아직 담은 상품이 없어요.'), findsOneWidget);
  });

  testWidgets('guest checkout goes to login with next back to checkout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final api = _PurchaseApi();
    final tokens = _MemoryTokens();
    final guest = GuestCartStorage();
    await guest.add(
      'offer-1',
      1,
      snapshot: const GuestCartLine(
        productId: 'offer-1',
        qty: 1,
        productTitle: '백산수 · 2L',
        priceCredits: 1200,
        sellerId: 's1',
        shopName: '공식 스토어',
        sellerType: 'platform',
      ),
    );

    late GoRouter router;
    router = GoRouter(
      initialLocation: '/cart',
      redirect: (context, state) {
        final loggedIn = tokens._tokens[LoginPortal.buyer] != null;
        final path = state.matchedLocation;
        if (!loggedIn && requiresBuyerAuth(path)) {
          final raw = state.uri.hasQuery
              ? '${state.matchedLocation}?${state.uri.query}'
              : state.matchedLocation;
          return '/login?next=${Uri.encodeQueryComponent(raw)}';
        }
        return null;
      },
      routes: [
        ShellRoute(
          builder: (context, state, child) => WebShell(child: child),
          routes: [
            GoRoute(path: '/cart', builder: (_, _) => const CartScreen()),
            GoRoute(
              path: '/checkout',
              builder: (_, _) => const CheckoutScreen(),
            ),
            GoRoute(
              path: '/login',
              builder: (_, state) => LoginScreen(
                next: state.uri.queryParameters['next'],
              ),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStorageProvider.overrideWithValue(tokens),
          guestCartStorageProvider.overrideWithValue(guest),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('주문하기'));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/login');
    expect(router.state.uri.queryParameters['next'], '/checkout');
    expect(find.text('이메일'), findsOneWidget);
  });
}
