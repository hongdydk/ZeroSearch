import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shopping_mall/core/models/models.dart';
import 'package:shopping_mall/core/network/api_client.dart';
import 'package:shopping_mall/core/providers/app_providers.dart';
import 'package:shopping_mall/core/theme/app_theme.dart';
import 'package:shopping_mall/features/seller/seller_product_detail_screen.dart';
import 'package:shopping_mall/features/seller/seller_products_screen.dart';

final _seller = SellerSummaryModel(
  id: 's1',
  shopName: '입점마트',
  sellerType: 'merchant',
);

ProductModel _offer({
  String id = 'p1',
  String status = 'published',
  String? optionLabel = '500ml × 20',
  String? flavor = '레몬',
  int priceCredits = 12500,
  int stock = 40,
}) {
  return ProductModel(
    id: id,
    title: '백산수',
    priceCredits: priceCredits,
    stock: stock,
    category: '생수',
    seller: _seller,
    status: status,
    catalogProductId: 'c1',
    optionLabel: optionLabel,
    flavor: flavor,
    imageUrl: 'https://img.example/water.jpg',
  );
}

class _SellerApi extends ApiClient {
  _SellerApi(this.items) : super(tokenReader: () async => 'tok');

  List<ProductModel> items;
  Map<String, Object?>? lastPatch;
  String? lastDeleteId;
  int patchCalls = 0;

  @override
  Future<List<ProductModel>> sellerProducts() async => items;

  @override
  Future<List<IntakeDraftModel>> sellerCardDrafts() async => const [];

  @override
  Future<ProductModel> sellerUpdateProduct(
    String productId, {
    int? priceCredits,
    int? stock,
    String? imageUrl,
    String? status,
    String? optionLabel,
    double? unitAmount,
    String? unit,
    int? packCount,
    String? flavor,
  }) async {
    patchCalls += 1;
    lastPatch = {
      'id': productId,
      'priceCredits': priceCredits,
      'stock': stock,
      'imageUrl': imageUrl,
      'status': status,
    };
    items = [
      for (final row in items)
        if (row.id == productId)
          row.copyWith(
            priceCredits: priceCredits,
            stock: stock,
            imageUrl: imageUrl,
            status: status,
          )
        else
          row,
    ];
    return items.firstWhere((row) => row.id == productId);
  }

  @override
  Future<void> sellerDeleteProduct(String productId) async {
    lastDeleteId = productId;
    items = [
      for (final row in items)
        if (row.id == productId) row.copyWith(status: 'archived') else row,
    ];
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
        category: '생수',
        offerCount: 1,
        imageUrl: 'https://img.example/card.jpg',
        offers: const [],
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('list shows option differentiation and opens detail', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _SellerApi([
      _offer(),
      _offer(id: 'p2', optionLabel: '2L × 6', flavor: null, priceCredits: 9800),
      _offer(id: 'p3', status: 'archived', optionLabel: '500ml × 24', flavor: null),
    ]);
    final router = GoRouter(
      initialLocation: '/seller/products',
      routes: [
        GoRoute(
          path: '/seller/products',
          builder: (_, _) => const SellerProductsScreen(),
        ),
        GoRoute(
          path: '/seller/products/:id',
          builder: (_, state) => SellerProductDetailScreen(
            productId: state.pathParameters['id']!,
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: MaterialApp.router(theme: AppTheme.web(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('500ml × 20 · 레몬 · 12,500원 · 재고 40'), findsOneWidget);
    expect(find.text('2L × 6 · 9,800원 · 재고 40'), findsOneWidget);

    await tester.tap(find.text('숨김 1'));
    await tester.pumpAndSettle();
    expect(find.text('500ml × 24 · 12,500원 · 재고 40'), findsOneWidget);
    expect(find.text('숨김'), findsWidgets);

    await tester.tap(find.text('전체 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('백산수').first);
    await tester.pumpAndSettle();
    expect(find.text('연결된 카드'), findsOneWidget);
    expect(find.text('가격(원)'), findsOneWidget);
    expect(find.text('구매자에게 숨김'), findsOneWidget);
  });

  testWidgets('detail save patches price stock and hide', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _SellerApi([_offer()]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: MaterialApp(
          theme: AppTheme.web(),
          home: const Scaffold(
            body: SellerProductDetailScreen(productId: 'p1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '11000');
    await tester.enterText(find.byType(TextField).at(1), '8');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(api.patchCalls, 1);
    expect(api.lastPatch?['priceCredits'], 11000);
    expect(api.lastPatch?['stock'], 8);
    expect(api.lastPatch?['status'], 'archived');
  });

  testWidgets('list hide action patches archived', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _SellerApi([_offer()]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: MaterialApp(
          theme: AppTheme.web(),
          home: const Scaffold(body: SellerProductsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('관리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('숨김').last);
    await tester.pumpAndSettle();

    expect(api.patchCalls, 1);
    expect(api.lastPatch?['status'], 'archived');
  });
}
