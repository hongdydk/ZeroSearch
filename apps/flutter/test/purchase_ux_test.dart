import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shopping_mall/core/auth/login_portal.dart';
import 'package:shopping_mall/core/cart/pending_cart_add.dart';
import 'package:shopping_mall/core/models/models.dart';
import 'package:shopping_mall/core/network/api_client.dart';
import 'package:shopping_mall/core/providers/app_providers.dart';
import 'package:shopping_mall/core/storage/token_storage.dart';
import 'package:shopping_mall/features/auth/login_screen.dart';
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
    cartState = CartModel(
      items: [
        CartItemModel(
          id: 'c1',
          productId: productId,
          productTitle: '백산수',
          qty: qty,
          priceCredits: 1200,
          lineTotalCredits: 1200 * qty,
          sellerId: 's1',
          shopName: '공식 스토어',
          sellerType: 'platform',
        ),
      ],
      totalCredits: 1200 * qty,
    );
    return cartState;
  }

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
  testWidgets('guest add goes to login with next and re-adds after login', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final api = _PurchaseApi();
    final tokens = _MemoryTokens();
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
              builder: (_, _) => const Text('cart-page'),
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

    expect(router.state.uri.path, '/login');
    final next = router.state.uri.queryParameters['next'] ?? '';
    expect(next, contains('/catalog/cat-1'));
    expect(next, contains('addOffer=offer-1'));
    expect(next, contains('addQty=3'));

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'buyer@mall.local');
    await tester.enterText(fields.at(1), 'secret');
    await tester.tap(find.widgetWithText(FilledButton, '로그인'));
    await tester.pumpAndSettle();

    expect(api.lastAddId, 'offer-1');
    expect(api.lastAddQty, 3);
    expect(router.state.uri.path, '/catalog/cat-1');
    expect(router.state.uri.queryParameters.containsKey('addOffer'), isFalse);
    expect(find.text('장바구니에 담았습니다.'), findsOneWidget);
    expect(find.text('장바구니 보기'), findsOneWidget);
  });

  testWidgets('pending add restores from next after login page rebuild', (
    tester,
  ) async {
    final api = _PurchaseApi();
    final tokens = _MemoryTokens();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStorageProvider.overrideWithValue(tokens),
        ],
        child: const MaterialApp(
          home: LoginScreen(
            next: '/catalog/cat-1?addOffer=offer-9&addQty=2',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LoginScreen)),
    );
    final pending = container.read(pendingCartAddProvider);
    expect(pending?.productId, 'offer-9');
    expect(pending?.qty, 2);
  });
}
