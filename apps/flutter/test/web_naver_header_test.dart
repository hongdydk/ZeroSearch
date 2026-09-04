import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_mall/core/layout/ui_platform.dart';
import 'package:shopping_mall/core/models/models.dart';
import 'package:shopping_mall/core/network/api_client.dart';
import 'package:shopping_mall/core/providers/app_providers.dart';
import 'package:shopping_mall/core/storage/token_storage.dart';
import 'package:shopping_mall/core/theme/app_theme.dart';
import 'package:shopping_mall/features/catalog/catalog_screen.dart';
import 'package:shopping_mall/shared/widgets/adaptive_shell.dart';
import 'package:shopping_mall/shared/widgets/web/web_naver_header.dart';

class _HeaderTestApiClient extends ApiClient {
  _HeaderTestApiClient() : super(tokenReader: () async => null);

  @override
  Future<UserModel> me() async => UserModel(
        id: 'user-1',
        email: 'test@example.com',
        displayName: 'Tester',
      );

  @override
  Future<List<CatalogProductModel>> catalogProducts({
    String? q,
    String? category,
    String? categoryMajor,
    String? categoryMid,
    String? flavor,
    int? volumeMlMin,
    int? volumeMlMax,
    int offset = 0,
    int limit = 50,
  }) async =>
      [
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
      ];
}

class _LoggedInTokenStorage extends TokenStorage {
  @override
  Future<String?> read() async => 'test-token';

  @override
  Future<String?> readPortal() async => 'buyer';

  @override
  Future<void> write(String token) async {}

  @override
  Future<void> writePortal(String portal) async {}

  @override
  Future<void> clear() async {}
}

class _LoggedOutTokenStorage extends TokenStorage {
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

Widget _headerHarness({required bool loggedIn}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(_HeaderTestApiClient()),
      tokenStorageProvider.overrideWithValue(
        loggedIn ? _LoggedInTokenStorage() : _LoggedOutTokenStorage(),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.web(),
      home: Scaffold(
        body: Column(
          children: [
            const WebNaverHeader(location: '/'),
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
  });

  tearDown(() {
    debugForceWebUi = false;
  });

  testWidgets('WebNaverHeader shows brand and cart without MY dropdown', (tester) async {
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

  testWidgets('Services menu has orders, membership, settings, logout when logged in',
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
    expect(find.widgetWithText(PopupMenuItem<String>, '판매자 센터'), findsOneWidget);
    expect(find.widgetWithText(PopupMenuItem<String>, '관리자'), findsOneWidget);
    expect(find.widgetWithText(PopupMenuItem<String>, '로그아웃'), findsOneWidget);
  });

  testWidgets('compact web shows search on home catalog', (tester) async {
    debugForceWebUi = true;
    _setLogicalViewport(tester, const Size(390, 844));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(_HeaderTestApiClient()),
          tokenStorageProvider.overrideWithValue(_LoggedOutTokenStorage()),
        ],
        child: MaterialApp(
          theme: AppTheme.web(),
          home: const WebShell(child: CatalogScreen()),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(AppBar), findsNothing);
    expect(find.text('제로 서치'), findsOneWidget);
    expect(find.text('밥, 떡, 쌀…'), findsOneWidget);
    expect(find.text('식탁'), findsWidgets);
    expect(find.text('면류'), findsWidgets);
    expect(find.text('간편식'), findsWidgets);
  });
}
