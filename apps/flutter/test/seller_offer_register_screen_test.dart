import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shopping_mall/core/models/models.dart';
import 'package:shopping_mall/core/network/api_client.dart';
import 'package:shopping_mall/core/providers/app_providers.dart';
import 'package:shopping_mall/core/theme/app_theme.dart';
import 'package:shopping_mall/features/seller/seller_offer_register_screen.dart';
import 'package:shopping_mall/features/seller/seller_product_detail_screen.dart';
import 'package:shopping_mall/features/seller/seller_products_screen.dart';

final _seller = SellerSummaryModel(
  id: 's1',
  shopName: '입점마트',
  sellerType: 'merchant',
);

class _RegisterApi extends ApiClient {
  _RegisterApi() : super(tokenReader: () async => 'tok');

  Map<String, Object?>? lastCreate;
  ProductModel? created;

  @override
  Future<List<CatalogProductModel>> sellerSearchCatalog({
    String? q,
    String? category,
    int offset = 0,
    int limit = 30,
  }) async {
    return [
      CatalogProductModel(
        id: 'c1',
        title: '백산수',
        category: '생수',
        offerCount: 1,
        priceUnit: 'ml',
        displayPriceLabel: 'L당',
        manufacturer: '농심',
        volumeOptions: const ['2L', '500ml'],
      ),
    ];
  }

  @override
  Future<ProductModel> sellerCreateProduct({
    required String title,
    required String category,
    int? priceCredits,
    int? stock,
    String? description,
    String status = 'draft',
    String? catalogProductId,
    String? optionLabel,
    int? volumeMl,
    double? unitAmount,
    String? unit,
    int? packCount,
    String? flavor,
    String? imageUrl,
  }) async {
    lastCreate = {
      'title': title,
      'priceCredits': priceCredits,
      'stock': stock,
      'unitAmount': unitAmount,
      'unit': unit,
      'packCount': packCount,
      'optionLabel': optionLabel,
      'catalogProductId': catalogProductId,
    };
    created = ProductModel(
      id: 'p-new',
      title: title,
      priceCredits: priceCredits ?? 0,
      stock: stock ?? 0,
      category: category,
      seller: _seller,
      status: 'draft',
      catalogProductId: catalogProductId,
      optionLabel: optionLabel ?? '2L × 12',
      unitAmount: unitAmount,
      unit: unit,
      packCount: packCount ?? 1,
    );
    return created!;
  }

  @override
  Future<List<ProductModel>> sellerProducts() async =>
      created == null ? [] : [created!];

  @override
  Future<List<IntakeDraftModel>> sellerCardDrafts() async => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('register creates identity without price then offers price step', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _RegisterApi();
    final router = GoRouter(
      initialLocation: '/seller/products/new',
      routes: [
        GoRoute(
          path: '/seller/products',
          builder: (_, _) => const SellerProductsScreen(),
        ),
        GoRoute(
          path: '/seller/products/new',
          builder: (_, _) => const SellerOfferRegisterScreen(),
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

    expect(find.text('오퍼 등록'), findsOneWidget);
    expect(find.text('가격(원)'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '백산수');
    await tester.tap(find.text('검색'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('농심 백산수'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('오퍼 초안 만들기'));
    await tester.pumpAndSettle();

    expect(api.lastCreate?['priceCredits'], isNull);
    expect(api.lastCreate?['stock'], isNull);
    expect(api.lastCreate?['unitAmount'], 2);
    expect(api.lastCreate?['unit'], 'L');
    expect(api.lastCreate?['packCount'], 1);
    expect(api.lastCreate?['optionLabel'], '2L');
    expect(find.text('이어서 가격·재고'), findsOneWidget);
    expect(find.text('나중에'), findsOneWidget);
  });
}
