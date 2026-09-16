import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shopping_mall/core/auth/login_portal.dart';
import 'package:shopping_mall/core/cart/guest_cart.dart';
import 'package:shopping_mall/core/models/models.dart';
import 'package:shopping_mall/core/network/api_client.dart';
import 'package:shopping_mall/core/network/api_exception.dart';
import 'package:shopping_mall/core/payment/toss_payment_bridge.dart';
import 'package:shopping_mall/core/providers/app_providers.dart';
import 'package:shopping_mall/core/routing/app_router.dart';
import 'package:shopping_mall/core/storage/token_storage.dart';
import 'package:shopping_mall/core/theme/app_theme.dart';
import 'package:shopping_mall/features/payment/payment_result_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SuccessApi extends ApiClient {
  _SuccessApi() : super(tokenReader: () async => 'token');

  int confirms = 0;

  @override
  Future<OrderModel> confirmTossPayment({
    required String paymentKey,
    required String orderId,
    required int amount,
  }) async {
    confirms += 1;
    return OrderModel(
      id: 'order-1',
      status: 'paid',
      totalCredits: 12900,
      items: const [],
    );
  }
}

class _DuplicatePaidApi extends ApiClient {
  _DuplicatePaidApi() : super(tokenReader: () async => 'token');

  int confirms = 0;

  @override
  Future<OrderModel> confirmTossPayment({
    required String paymentKey,
    required String orderId,
    required int amount,
  }) async {
    confirms += 1;
    throw ApiException('이미 처리된 결제입니다.');
  }

  @override
  Future<TossPaymentStatusModel> tossPaymentStatus(String orderId) async {
    return TossPaymentStatusModel(orderId: orderId, status: 'paid');
  }
}

class _LoggedInApi extends ApiClient {
  _LoggedInApi() : super(tokenReader: () async => 'token');

  @override
  Future<UserModel> me() async =>
      UserModel(id: 'u1', email: 'buyer@example.com', displayName: 'Buyer');

  @override
  Future<CatalogProductPageModel> catalogProducts({
    String? q,
    String? category,
    String? categoryMajor,
    String? categoryMid,
    String? flavor,
    int? volumeMlMin,
    int? volumeMlMax,
    int offset = 0,
    int limit = 50,
  }) async => CatalogProductPageModel(items: const [], total: 0);

  @override
  Future<CartModel> cart() async =>
      CartModel(items: const [], totalCredits: 0);

  @override
  Future<List<OrderModel>> orders() async => const [];

  @override
  Future<OrderModel> confirmTossPayment({
    required String paymentKey,
    required String orderId,
    required int amount,
  }) async {
    return OrderModel(
      id: 'order-1',
      status: 'paid',
      totalCredits: 12900,
      items: const [],
    );
  }
}

class _Tokens extends TokenStorage {
  @override
  Future<String?> readPortalToken(LoginPortal portal) async =>
      portal == LoginPortal.buyer ? 'token' : null;

  @override
  Future<String?> read() async => 'token';

  @override
  Future<String?> readPortal() async => 'buyer';

  @override
  Future<void> write(String token) async {}

  @override
  Future<void> writePortal(String portal) async {}

  @override
  Future<void> loadLeftAts() async {}

  @override
  Future<void> clearPortalLeft(LoginPortal portal) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Toss payment bridge is disabled outside web', () {
    expect(tossPaymentSupported, isFalse);
  });

  testWidgets('success screen rejects missing callback values', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PaymentSuccessScreen(
          paymentKey: null,
          orderId: null,
          amount: null,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('결제를 완료하지 못했습니다'), findsOneWidget);
    expect(find.text('결제 승인 정보가 올바르지 않습니다.'), findsOneWidget);
  });

  testWidgets('success screen confirms a paid order', (tester) async {
    final api = _SuccessApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: PaymentSuccessScreen(
            paymentKey: 'pk',
            orderId: 'zs_123456',
            amount: '12900',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.confirms, 1);
    expect(find.text('결제가 완료되었습니다'), findsOneWidget);
    expect(find.text('주문 내역 보기'), findsOneWidget);
  });

  testWidgets('duplicate success converges on already paid status', (
    tester,
  ) async {
    final api = _DuplicatePaidApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: PaymentSuccessScreen(
            paymentKey: 'pk',
            orderId: 'zs_123456',
            amount: '12900',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.confirms, 1);
    expect(find.text('결제가 완료되었습니다'), findsOneWidget);
    expect(find.text('주문 내역 보기'), findsOneWidget);
  });

  testWidgets('fail screen keeps a route back to cart', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PaymentFailScreen(
          code: 'PAY_PROCESS_CANCELED',
          message: '구매자가 결제를 취소했습니다.',
        ),
      ),
    );

    expect(find.text('결제가 완료되지 않았습니다'), findsOneWidget);
    expect(find.text('오류 코드: PAY_PROCESS_CANCELED'), findsOneWidget);
    expect(find.text('장바구니로'), findsOneWidget);
  });

  testWidgets('payment success and fail routes render', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    late GoRouter router;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(_LoggedInApi()),
          tokenStorageProvider.overrideWithValue(_Tokens()),
          guestCartStorageProvider.overrideWithValue(MemoryGuestCartStore()),
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

    router.go('/payment/success?paymentKey=pk&orderId=zs_123456&amount=12900');
    await tester.pumpAndSettle();
    expect(find.text('결제가 완료되었습니다'), findsOneWidget);

    router.go('/payment/fail?code=PAY_PROCESS_CANCELED&message=취소됨');
    await tester.pumpAndSettle();
    expect(find.text('결제가 완료되지 않았습니다'), findsOneWidget);
    expect(find.text('오류 코드: PAY_PROCESS_CANCELED'), findsOneWidget);
  });
}
