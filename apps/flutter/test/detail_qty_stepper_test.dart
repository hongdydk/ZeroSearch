import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shopping_mall/core/auth/login_portal.dart';
import 'package:shopping_mall/core/models/models.dart';
import 'package:shopping_mall/core/network/api_client.dart';
import 'package:shopping_mall/core/providers/app_providers.dart';
import 'package:shopping_mall/core/storage/token_storage.dart';
import 'package:shopping_mall/features/product_detail/catalog_detail_screen.dart';
import 'package:shopping_mall/features/product_detail/product_detail_screen.dart';
import 'package:shopping_mall/shared/widgets/qty_stepper.dart';

final _seller = SellerSummaryModel(
  id: 's1',
  shopName: '공식 스토어',
  sellerType: 'platform',
);

class _DetailApi extends ApiClient {
  _DetailApi() : super(tokenReader: () async => 'test-token');

  String? lastProductId;
  int? lastQty;

  @override
  Future<UserModel> me() async =>
      UserModel(id: 'u1', email: 't@example.com', displayName: 'T');

  @override
  Future<CartModel> cart() async => CartModel(items: const [], totalCredits: 0);

  @override
  Future<CartModel> addToCart(String productId, {int qty = 1}) async {
    lastProductId = productId;
    lastQty = qty;
    return CartModel(items: const [], totalCredits: 0);
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

  @override
  Future<ProductModel> product(String id) async => ProductModel(
        id: id,
        title: '백산수 2L',
        priceCredits: 1200,
        stock: 5,
        category: '일반생수',
        seller: _seller,
      );
}

class _LoggedInTokens extends TokenStorage {
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

void main() {
  testWidgets('QtyStepper stays within min and max', (tester) async {
    var qty = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: QtyStepper(
                value: qty,
                max: 3,
                onChanged: (v) => setState(() => qty = v),
              ),
            );
          },
        ),
      ),
    );

    expect(
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove)).onPressed,
      isNull,
    );

    await tester.tap(find.byTooltip('수량 늘리기'));
    await tester.pump();
    await tester.tap(find.byTooltip('수량 늘리기'));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add)).onPressed,
      isNull,
    );

    await tester.tap(find.byTooltip('수량 줄이기'));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
  });
  Future<void> _pumpDetail(WidgetTester tester, Widget child, _DetailApi api) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/detail',
      routes: [
        GoRoute(
          path: '/detail',
          builder: (_, _) => Scaffold(body: child),
        ),
        GoRoute(path: '/login', builder: (_, _) => const Text('login-page')),
        GoRoute(path: '/cart', builder: (_, _) => const Text('cart-page')),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStorageProvider.overrideWithValue(_LoggedInTokens()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('catalog detail stepper adds selected qty', (tester) async {
    final api = _DetailApi();
    await _pumpDetail(tester, const CatalogDetailScreen(catalogId: 'cat-1'), api);

    expect(find.text('담기'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('수량 늘리기'));
    await tester.tap(find.byTooltip('수량 늘리기'));
    await tester.pump();
    await tester.tap(find.byTooltip('수량 늘리기'));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.text('담기'));
    await tester.pumpAndSettle();

    expect(api.lastProductId, 'offer-1');
    expect(api.lastQty, 3);
    expect(find.text('장바구니에 담았습니다.'), findsOneWidget);
    expect(find.text('장바구니 보기'), findsOneWidget);

    await tester.tap(find.text('장바구니 보기'));
    await tester.pumpAndSettle();
    expect(find.text('cart-page'), findsOneWidget);
  });

  testWidgets('product detail stepper adds selected qty', (tester) async {
    final api = _DetailApi();
    await _pumpDetail(tester, const ProductDetailScreen(productId: 'p1'), api);

    await tester.ensureVisible(find.byTooltip('수량 늘리기'));
    await tester.tap(find.byTooltip('수량 늘리기'));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);

    await tester.ensureVisible(find.text('장바구니 담기'));
    await tester.tap(find.text('장바구니 담기'));
    await tester.pumpAndSettle();

    expect(api.lastProductId, 'p1');
    expect(api.lastQty, 2);
  });

  testWidgets('stepper cannot exceed stock', (tester) async {
    final api = _DetailApi();
    await _pumpDetail(tester, const ProductDetailScreen(productId: 'p1'), api);

    await tester.ensureVisible(find.byTooltip('수량 늘리기'));
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.byTooltip('수량 늘리기'));
      await tester.pump();
    }
    expect(find.text('5'), findsOneWidget);

    final plus = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.add),
    );
    expect(plus.onPressed, isNull);
  });
}
