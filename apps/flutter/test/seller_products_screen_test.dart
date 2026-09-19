import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shopping_mall/core/models/models.dart';
import 'package:shopping_mall/core/network/api_client.dart';
import 'package:shopping_mall/core/providers/app_providers.dart';
import 'package:shopping_mall/core/theme/app_theme.dart';
import 'package:shopping_mall/features/seller/seller_offer_format.dart';
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
  _SellerApi(this.items, {this.drafts = const []}) : super(tokenReader: () async => 'tok');

  List<ProductModel> items;
  List<IntakeDraftModel> drafts;
  Map<String, Object?>? lastPatch;
  Map<String, Object?>? lastDraftPatch;
  Map<String, Object?>? lastListQuery;
  String? lastDeleteId;
  Map<String, Object?>? lastBulk;
  int patchCalls = 0;
  int listCalls = 0;
  int bulkCalls = 0;
  SellerProductBulkResult? nextBulkResult;

  SellerProductCounts _countsFor(List<ProductModel> rows) {
    return SellerProductCounts(
      all: rows.length,
      published: rows.where(sellerOfferIsPublic).length,
      pending: rows.where((p) => p.status == 'draft').length,
      soldOut: rows.where((p) => p.status == 'published' && p.stock <= 0).length,
      hidden: rows.where(sellerOfferIsHidden).length,
    );
  }

  @override
  Future<SellerProductListPage> sellerProducts({
    String? q,
    String? filter,
    String? sort,
    int offset = 0,
    int limit = 20,
  }) async {
    listCalls += 1;
    lastListQuery = {
      'q': q,
      'filter': filter,
      'sort': sort,
      'offset': offset,
      'limit': limit,
    };
    var rows = List<ProductModel>.from(items);
    if (q != null && q.isNotEmpty) {
      final needle = q.toLowerCase();
      rows = rows
          .where(
            (p) =>
                p.title.toLowerCase().contains(needle) ||
                (p.optionLabel ?? '').toLowerCase().contains(needle),
          )
          .toList();
    }
    final counts = _countsFor(rows);
    if (filter != null && filter.isNotEmpty && filter != 'all') {
      rows = rows.where((p) => sellerOfferMatchesFilter(p, filter)).toList();
    }
    if (sort == 'price') {
      rows.sort((a, b) => a.priceCredits.compareTo(b.priceCredits));
    } else if (sort == 'stock') {
      rows.sort((a, b) => a.stock.compareTo(b.stock));
    }
    final page = rows.skip(offset).take(limit).toList();
    return SellerProductListPage(
      items: page,
      total: rows.length,
      counts: counts,
    );
  }

  @override
  Future<ProductModel> sellerProduct(String productId) async {
    return items.firstWhere((row) => row.id == productId);
  }

  @override
  Future<List<IntakeDraftModel>> sellerCardDrafts() async => drafts;

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
    lastDraftPatch = {
      'id': draftId,
      'priceCredits': priceCredits,
      'stock': stock,
      'visibility': visibility,
    };
    drafts = [
      for (final row in drafts)
        if (row.id == draftId)
          IntakeDraftModel(
            id: row.id,
            kind: row.kind,
            status: row.status,
            sellerId: row.sellerId,
            shopName: row.shopName,
            title: row.title,
            category: row.category,
            priceCredits: priceCredits ?? row.priceCredits,
            stock: stock ?? row.stock,
            manufacturer: row.manufacturer,
            optionLabel: row.optionLabel,
            visibility: visibility ?? row.visibility,
          )
        else
          row,
    ];
    return drafts.firstWhere((row) => row.id == draftId);
  }

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
  Future<SellerProductBulkResult> sellerBulkUpdateProducts({
    required List<String> ids,
    int? priceCredits,
    int? stock,
    String? status,
  }) async {
    bulkCalls += 1;
    lastBulk = {
      'ids': List<String>.from(ids),
      'priceCredits': priceCredits,
      'stock': stock,
      'status': status,
    };
    if (nextBulkResult != null) return nextBulkResult!;
    items = [
      for (final row in items)
        if (ids.contains(row.id))
          row.copyWith(
            priceCredits: priceCredits,
            stock: stock,
            status: status,
          )
        else
          row,
    ];
    final updated = items.where((row) => ids.contains(row.id)).toList();
    return SellerProductBulkResult(
      updated: updated,
      successCount: updated.length,
    );
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
          builder: (_, _) => const Scaffold(body: SellerProductsScreen()),
        ),
        GoRoute(
          path: '/seller/products/:id',
          builder: (_, state) => Scaffold(
            body: SellerProductDetailScreen(
              productId: state.pathParameters['id']!,
            ),
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

  testWidgets('card draft price dialog defaults public and saves hidden', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _SellerApi(
      [_offer()],
      drafts: [
        IntakeDraftModel(
          id: 'd1',
          kind: 'card',
          status: 'pending',
          sellerId: 's1',
          shopName: '입점마트',
          title: '떡갈비',
          category: '축산가공',
          priceCredits: 0,
          stock: 0,
          manufacturer: '매일',
          optionLabel: '500g',
        ),
      ],
    );
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

    await tester.tap(find.text('매일 떡갈비'));
    await tester.pumpAndSettle();

    expect(find.text('가시성'), findsOneWidget);
    expect(find.text('공개'), findsWidgets);
    expect(find.text('비공개'), findsNothing);

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '가격(원)',
      ),
      '4800',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '재고',
      ),
      '10',
    );
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(find.text('비공개'), findsOneWidget);

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(api.lastDraftPatch?['priceCredits'], 4800);
    expect(api.lastDraftPatch?['stock'], 10);
    expect(api.lastDraftPatch?['visibility'], 'hidden');
  });

  testWidgets('list searches and uses distinct empty copy', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final emptyApi = _SellerApi([]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(emptyApi)],
        child: MaterialApp(
          theme: AppTheme.web(),
          home: const Scaffold(body: SellerProductsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('아직 등록한 오퍼가 없습니다. 오퍼 등록으로 시작하세요.'), findsOneWidget);

    final api = _SellerApi([
      _offer(),
      _offer(id: 'p2', optionLabel: '2L × 6', flavor: null, priceCredits: 9800),
    ]);
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

    await tester.enterText(find.byType(TextField).first, '없는옵션');
    await tester.tap(find.text('검색'));
    await tester.pumpAndSettle();
    expect(api.lastListQuery?['q'], '없는옵션');
    expect(find.text('이 검색·조건에 맞는 오퍼가 없습니다.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '2L');
    await tester.tap(find.text('검색'));
    await tester.pumpAndSettle();
    expect(find.text('2L × 6 · 9,800원 · 재고 40'), findsOneWidget);
    expect(find.text('500ml × 20 · 레몬 · 12,500원 · 재고 40'), findsNothing);
  });

  testWidgets('list paginates and sorts from the server', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _SellerApi([
      for (var i = 0; i < 21; i++)
        _offer(
          id: 'p$i',
          optionLabel: '500ml × $i',
          flavor: null,
          priceCredits: 1000 + i,
          stock: i,
        ),
    ]);
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

    expect(find.text('1–20 / 21'), findsOneWidget);
    await tester.ensureVisible(find.text('다음'));
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    expect(api.lastListQuery?['offset'], 20);
    expect(find.text('21–21 / 21'), findsOneWidget);

    await tester.tap(find.text('최신순'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('가격순').last);
    await tester.pumpAndSettle();
    expect(api.lastListQuery?['sort'], 'price');
    expect(api.lastListQuery?['offset'], 0);
  });

  testWidgets('list bulk sold out confirms once and posts selected ids', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _SellerApi([
      _offer(),
      _offer(id: 'p2', optionLabel: '2L × 6', flavor: null, priceCredits: 9800),
    ]);
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

    await tester.tap(find.byKey(const ValueKey('select-offer-p1')));
    await tester.tap(find.byKey(const ValueKey('select-offer-p2')));
    await tester.pump();
    expect(find.text('2건 선택'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '품절'));
    await tester.pumpAndSettle();
    expect(find.text('2건의 재고를 0으로 바꿀까요?'), findsOneWidget);

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(api.bulkCalls, 0);

    await tester.tap(find.widgetWithText(OutlinedButton, '품절'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();

    expect(api.bulkCalls, 1);
    expect(api.lastBulk?['stock'], 0);
    expect(api.lastBulk?['ids'], ['p1', 'p2']);
    expect(find.text('2건을 적용했습니다.'), findsOneWidget);
  });

  testWidgets('list bulk hide uses page selection and keeps search paging', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _SellerApi([
      for (var i = 0; i < 21; i++)
        _offer(
          id: 'p$i',
          optionLabel: '500ml × $i',
          flavor: null,
          priceCredits: 1000 + i,
          stock: i,
        ),
    ]);
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

    await tester.tap(find.byKey(const ValueKey('select-offer-page')));
    await tester.pump();
    expect(find.text('20건 선택'), findsOneWidget);

    await tester.ensureVisible(find.text('다음'));
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    expect(api.lastListQuery?['offset'], 20);
    expect(find.text('20건 선택'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('select-offer-p20')));
    await tester.pump();
    expect(find.text('21건 선택'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '숨김'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();

    expect(api.bulkCalls, 1);
    expect(api.lastBulk?['status'], 'archived');
    final ids = api.lastBulk?['ids'] as List<String>;
    expect(ids, containsAll(['p0', 'p19', 'p20']));
    expect(ids, hasLength(21));
  });

  testWidgets('list bulk price confirms and posts selected ids', (tester) async {
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

    await tester.tap(find.byKey(const ValueKey('select-offer-p1')));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '가격'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '가격(원)',
      ),
      '7700',
    );
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();
    expect(api.lastBulk?['priceCredits'], 7700);
    expect(api.lastBulk?['ids'], ['p1']);
    expect(find.text('1건을 적용했습니다.'), findsOneWidget);
  });

  testWidgets('list bulk unhide shows success fail summary', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _SellerApi([
      _offer(),
      _offer(id: 'p2', status: 'draft', optionLabel: '2L × 6', flavor: null),
    ]);
    api.nextBulkResult = const SellerProductBulkResult(
      successCount: 1,
      failCount: 1,
      failed: [
        SellerProductBulkFailure(
          id: 'p2',
          detail: '검수 전에는 공개할 수 없습니다.',
        ),
      ],
    );
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

    await tester.tap(find.byKey(const ValueKey('select-offer-p1')));
    await tester.tap(find.byKey(const ValueKey('select-offer-p2')));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, '숨김 해제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();
    expect(api.lastBulk?['status'], 'published');
    expect(
      find.text('1건 적용, 1건 실패. 검수 전에는 공개할 수 없습니다.'),
      findsOneWidget,
    );
  });
}
