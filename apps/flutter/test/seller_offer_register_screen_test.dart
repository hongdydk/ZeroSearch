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
  _RegisterApi({
    this.catalogHits,
    this.catalogTotal,
  }) : super(tokenReader: () async => 'tok');

  Map<String, Object?>? lastCreate;
  Map<String, Object?>? lastDraftCreate;
  Map<String, Object?>? lastDraftUpdate;
  ProductModel? created;
  IntakeDraftModel? createdDraft;
  int searchCalls = 0;
  int lastSearchOffset = 0;
  List<CatalogProductModel>? catalogHits;
  int? catalogTotal;

  List<CatalogProductModel> get _defaultHits => [
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

  @override
  Future<CatalogProductSearchPage> sellerSearchCatalog({
    String? q,
    String? category,
    int offset = 0,
    int limit = 30,
  }) async {
    searchCalls += 1;
    lastSearchOffset = offset;
    final hits = catalogHits ?? _defaultHits;
    final total = catalogTotal ?? hits.length;
    return CatalogProductSearchPage(
      items: hits.skip(offset).take(limit).toList(),
      total: total,
    );
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
  Future<SellerProductListPage> sellerProducts({
    String? q,
    String? filter,
    String? sort,
    int offset = 0,
    int limit = 20,
  }) async {
    final items = created == null ? <ProductModel>[] : [created!];
    return SellerProductListPage(
      items: items,
      total: items.length,
      counts: SellerProductCounts(all: items.length, pending: items.length),
    );
  }

  @override
  Future<List<IntakeDraftModel>> sellerCardDrafts() async =>
      createdDraft == null ? const [] : [createdDraft!];

  @override
  Future<IntakeDraftModel> sellerCreateCardDraft({
    required String manufacturer,
    required String title,
    required String category,
    String? optionLabel,
    int? priceCredits,
    int? stock,
    String? imageUrl,
    String? flavor,
    int? volumeMl,
    double? unitAmount,
    String? unit,
    int? packCount,
    String? description,
    String? visibility,
  }) async {
    lastDraftCreate = {
      'manufacturer': manufacturer,
      'title': title,
      'category': category,
      'unitAmount': unitAmount,
      'unit': unit,
      'packCount': packCount,
      'priceCredits': priceCredits,
      'stock': stock,
      'visibility': visibility,
    };
    createdDraft = IntakeDraftModel(
      id: 'd-new',
      kind: 'card',
      status: 'pending',
      sellerId: _seller.id,
      shopName: _seller.shopName,
      title: title,
      category: category,
      priceCredits: priceCredits ?? 0,
      stock: stock ?? 0,
      manufacturer: manufacturer,
      optionLabel: optionLabel ?? '500g',
      unitAmount: unitAmount,
      unit: unit,
      packCount: packCount ?? 1,
      visibility: visibility ?? 'public',
    );
    return createdDraft!;
  }

  @override
  Future<IntakeDraftModel> sellerUpdateCardDraft(
    String draftId, {
    int? priceCredits,
    int? stock,
    String? imageUrl,
    String? flavor,
    String? optionLabel,
    double? unitAmount,
    String? unit,
    int? packCount,
    String? visibility,
  }) async {
    lastDraftUpdate = {
      'id': draftId,
      'priceCredits': priceCredits,
      'stock': stock,
      'visibility': visibility,
    };
    createdDraft = IntakeDraftModel(
      id: draftId,
      kind: 'card',
      status: 'pending',
      sellerId: _seller.id,
      shopName: _seller.shopName,
      title: createdDraft?.title ?? '떡갈비',
      category: createdDraft?.category ?? '축산가공',
      priceCredits: priceCredits ?? createdDraft?.priceCredits ?? 0,
      stock: stock ?? createdDraft?.stock ?? 0,
      manufacturer: createdDraft?.manufacturer ?? '매일',
      optionLabel: optionLabel ?? createdDraft?.optionLabel,
      visibility: visibility ?? createdDraft?.visibility ?? 'public',
    );
    return createdDraft!;
  }
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

  testWidgets('missing card draft form shows visibility under stock and submits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _RegisterApi();
    final router = GoRouter(
      initialLocation: '/seller/products/new',
      routes: [
        GoRoute(
          path: '/seller/products',
          builder: (_, _) => const Scaffold(body: SellerProductsScreen()),
        ),
        GoRoute(
          path: '/seller/products/new',
          builder: (_, _) => const SellerOfferRegisterScreen(missingItem: true),
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

    expect(find.text('없는 품목 카드 초안'), findsOneWidget);
    expect(
      find.text('공개 목록에 바로 올라가지 않습니다. MD가 기존 카드에 붙이거나 새 카드로 승격합니다.'),
      findsOneWidget,
    );
    expect(find.text('가시성'), findsOneWidget);
    expect(find.text('공개'), findsOneWidget);
    expect(find.text('비공개'), findsNothing);
    expect(find.text('초안 제출'), findsOneWidget);
    expect(find.text('취소'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    Finder labeled(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );

    await tester.enterText(labeled('회사'), '매일');
    await tester.enterText(labeled('품목명'), '떡갈비');
    await tester.enterText(labeled('종류 (짐작)'), '축산가공');
    await tester.enterText(labeled('용량·팩'), '500');
    await tester.enterText(labeled('가격(원)'), '4800');
    await tester.enterText(labeled('재고'), '10');
    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(find.text('비공개'), findsOneWidget);
    expect(find.text('공개'), findsNothing);

    await tester.ensureVisible(find.text('초안 제출'));
    await tester.tap(find.text('초안 제출'));
    await tester.pumpAndSettle();

    expect(api.lastDraftCreate?['visibility'], 'hidden');
    expect(api.lastDraftCreate?['unitAmount'], 500);
    expect(api.lastDraftCreate?['priceCredits'], 4800);
    expect(api.lastDraftCreate?['stock'], 10);
  });

  testWidgets('catalog picker shows empty copy and missing-item link', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _RegisterApi(catalogHits: const [], catalogTotal: 0);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: MaterialApp(
          theme: AppTheme.web(),
          home: const Scaffold(body: SellerOfferRegisterScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '없는품목');
    await tester.tap(find.text('검색'));
    await tester.pumpAndSettle();

    expect(find.textContaining('검색 결과가 없습니다'), findsOneWidget);
    await tester.tap(find.text('없는 품목 초안 만들기'));
    await tester.pumpAndSettle();
    expect(find.text('없는 품목 카드 초안'), findsOneWidget);
  });

  testWidgets('catalog picker loads next page when results are capped', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final hits = [
      for (var i = 0; i < 35; i++)
        CatalogProductModel(
          id: 'c$i',
          title: '품목$i',
          category: '생수',
          offerCount: 0,
          priceUnit: 'ml',
          displayPriceLabel: 'L당',
          manufacturer: '농심',
        ),
    ];
    final api = _RegisterApi(catalogHits: hits, catalogTotal: 35);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: MaterialApp(
          theme: AppTheme.web(),
          home: const Scaffold(body: SellerOfferRegisterScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '품목');
    await tester.tap(find.text('검색'));
    await tester.pumpAndSettle();
    expect(api.lastSearchOffset, 0);
    expect(find.text('농심 품목0'), findsOneWidget);
    expect(find.text('다음 페이지'), findsOneWidget);

    await tester.ensureVisible(find.text('다음 페이지'));
    await tester.tap(find.text('다음 페이지'));
    await tester.pumpAndSettle();
    expect(api.lastSearchOffset, 30);
    expect(find.text('농심 품목30'), findsOneWidget);
  });

  testWidgets('missing item cancel pops without false', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _RegisterApi();
    final router = GoRouter(
      initialLocation: '/seller/products',
      routes: [
        GoRoute(
          path: '/seller/products',
          builder: (_, _) => const Scaffold(body: SellerProductsScreen()),
        ),
        GoRoute(
          path: '/seller/products/new',
          builder: (_, _) => const SellerOfferRegisterScreen(missingItem: true),
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
    await tester.tap(find.text('없는 품목'));
    await tester.pumpAndSettle();
    expect(find.text('없는 품목 카드 초안'), findsOneWidget);

    await tester.ensureVisible(find.text('취소'));
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.text('내 오퍼'), findsWidgets);
    expect(find.text('없는 품목 카드 초안'), findsNothing);
  });
}
