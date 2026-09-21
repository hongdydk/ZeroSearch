import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shopping_mall/core/auth/login_portal.dart';
import 'package:shopping_mall/core/cart/guest_cart.dart';
import 'package:shopping_mall/core/models/models.dart';
import 'package:shopping_mall/core/network/api_client.dart';
import 'package:shopping_mall/core/network/api_exception.dart';
import 'package:shopping_mall/core/providers/app_providers.dart';
import 'package:shopping_mall/core/storage/token_storage.dart';
import 'package:shopping_mall/features/cart/cart_screen.dart';

final _seller = SellerSummaryModel(
  id: 's1',
  shopName: '공식 스토어',
  slug: 'official',
  sellerType: 'platform',
);

GuestCartLine _line({int qty = 1}) {
  return GuestCartLine(
    productId: 'p1',
    productTitle: '백산수',
    qty: qty,
    priceCredits: 1200,
    sellerId: _seller.id,
    shopName: _seller.shopName,
    sellerType: _seller.sellerType,
    maxQty: 5,
  );
}

CartModel _serverCart({int qty = 1}) {
  return CartModel.empty.copyWith(
    items: [
      CartItemModel(
        id: 'c1',
        productId: 'p1',
        productTitle: '백산수',
        qty: qty,
        priceCredits: 1200,
        lineTotalCredits: 1200 * qty,
        sellerId: _seller.id,
        shopName: _seller.shopName,
        sellerType: _seller.sellerType,
        maxQty: 5,
      ),
    ],
  );
}

class _LoggedOutTokens extends TokenStorage {
  @override
  Future<String?> readPortalToken(LoginPortal portal) async => null;

  @override
  Future<void> writePortalToken(LoginPortal portal, String token) async {}

  @override
  Future<void> clearPortal(LoginPortal portal) async {}

  @override
  Future<void> loadLeftAts() async {}

  @override
  Future<void> clearPortalLeft(LoginPortal portal) async {}
}

class _LoggedInTokens extends TokenStorage {
  @override
  Future<String?> readPortalToken(LoginPortal portal) async =>
      portal == LoginPortal.buyer ? 'tok' : null;

  @override
  Future<void> writePortalToken(LoginPortal portal, String token) async {}

  @override
  Future<void> clearPortal(LoginPortal portal) async {}

  @override
  Future<void> loadLeftAts() async {}

  @override
  Future<void> clearPortalLeft(LoginPortal portal) async {}
}

class _CartApi extends ApiClient {
  _CartApi() : super(tokenReader: () async => 'tok');

  CartModel cartState = _serverCart();
  final productIds = <String>[];
  final updateCalls = <int>[];
  final addCalls = <int>[];
  final removeCalls = <String>[];
  Completer<CartModel>? updateBlock;
  Object? updateError;

  @override
  Future<UserModel> me() async =>
      UserModel(id: 'u1', email: 't@example.com', displayName: 'T');

  @override
  Future<CartModel> cart() async => cartState;

  @override
  Future<ProductModel> product(String id) async {
    productIds.add(id);
    throw StateError('product() should not run on qty change');
  }

  @override
  Future<CartModel> addToCart(String productId, {int qty = 1}) async {
    addCalls.add(qty);
    cartState = cartState.addingOrMerging(
      CartItemModel(
        id: productId,
        productId: productId,
        productTitle: '백산수',
        qty: qty,
        priceCredits: 1200,
        lineTotalCredits: 1200 * qty,
        sellerId: _seller.id,
        shopName: _seller.shopName,
        sellerType: _seller.sellerType,
        maxQty: 5,
      ),
    );
    return cartState;
  }

  @override
  Future<CartModel> updateCartItem(String productId, int qty) async {
    updateCalls.add(qty);
    if (updateError != null) {
      final error = updateError!;
      updateError = null;
      throw error;
    }
    if (updateBlock != null) {
      return updateBlock!.future;
    }
    cartState = cartState.withItemQty(productId, qty);
    return cartState;
  }

  @override
  Future<CartModel> removeFromCart(String productId) async {
    removeCalls.add(productId);
    cartState = cartState.withoutItem(productId);
    return cartState;
  }
}

Future<void> _waitAuth(ProviderContainer container) async {
  for (var i = 0; i < 40; i++) {
    if (!container.read(authStateProvider).isLoading) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('auth did not finish loading');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('guest qty update uses local snapshot without product or cart API',
      () async {
    final store = MemoryGuestCartStore([_line()]);
    final api = _CartApi();
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tokenStorageProvider.overrideWithValue(_LoggedOutTokens()),
        guestCartStorageProvider.overrideWithValue(store),
        cartSyncDelayProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(container.dispose);

    await _waitAuth(container);
    final cart = await container.read(cartProvider.future);
    expect(cart.items.single.qty, 1);

    container.read(cartProvider.notifier).updateQty('p1', 2);
    expect(container.read(cartProvider).valueOrNull?.items.single.qty, 2);
    await Future<void>.delayed(Duration.zero);

    expect(store.lines.single.qty, 2);
    expect(api.productIds, isEmpty);
    expect(api.updateCalls, isEmpty);
    expect(api.removeCalls, isEmpty);
  });

  test('guest remove updates local snapshot without API', () async {
    final store = MemoryGuestCartStore([_line()]);
    final api = _CartApi();
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tokenStorageProvider.overrideWithValue(_LoggedOutTokens()),
        guestCartStorageProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);

    await _waitAuth(container);
    await container.read(cartProvider.future);
    container.read(cartProvider.notifier).remove('p1');
    await Future<void>.delayed(Duration.zero);

    expect(container.read(cartProvider).valueOrNull?.items, isEmpty);
    expect(store.lines, isEmpty);
    expect(api.productIds, isEmpty);
    expect(api.removeCalls, isEmpty);
  });

  test('buyer qty is optimistic and does not wait on updateCartItem', () async {
    final api = _CartApi();
    api.updateBlock = Completer<CartModel>();
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tokenStorageProvider.overrideWithValue(_LoggedInTokens()),
        guestCartStorageProvider.overrideWithValue(MemoryGuestCartStore()),
        cartSyncDelayProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(container.dispose);

    await _waitAuth(container);
    await container.read(cartProvider.future);

    container.read(cartProvider.notifier).updateQty('p1', 2);
    expect(container.read(cartProvider).valueOrNull?.items.single.qty, 2);

    await Future<void>.delayed(Duration.zero);
    expect(api.updateCalls, [2]);
    expect(api.updateBlock!.isCompleted, isFalse);
    expect(container.read(cartProvider).valueOrNull?.items.single.qty, 2);
    expect(container.read(cartProvider).isLoading, isFalse);

    api.cartState = _serverCart(qty: 2);
    api.updateBlock!.complete(api.cartState);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(cartProvider).valueOrNull?.items.single.qty, 2);
  });

  test('buyer qty rolls back and sets error when API fails', () async {
    final api = _CartApi();
    api.updateError = ApiException('재고가 부족합니다.');
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tokenStorageProvider.overrideWithValue(_LoggedInTokens()),
        guestCartStorageProvider.overrideWithValue(MemoryGuestCartStore()),
        cartSyncDelayProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(container.dispose);

    await _waitAuth(container);
    await container.read(cartProvider.future);

    container.read(cartProvider.notifier).updateQty('p1', 2);
    expect(container.read(cartProvider).valueOrNull?.items.single.qty, 2);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(cartProvider).valueOrNull?.items.single.qty, 1);
    expect(container.read(cartSyncErrorProvider), '재고가 부족합니다.');
  });

  test('login merges guest cart into server cart', () async {
    final store = MemoryGuestCartStore([_line(qty: 2)]);
    final api = _CartApi();
    api.cartState = CartModel.empty;
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tokenStorageProvider.overrideWithValue(_LoggedInTokens()),
        guestCartStorageProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);

    await _waitAuth(container);
    final cart = await container.read(cartProvider.future);
    expect(api.addCalls, [2]);
    expect(store.lines, isEmpty);
    expect(cart.items.single.qty, 2);
  });

  test('buyer qty debounce sends only the last value', () async {
    final api = _CartApi();
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tokenStorageProvider.overrideWithValue(_LoggedInTokens()),
        guestCartStorageProvider.overrideWithValue(MemoryGuestCartStore()),
        cartSyncDelayProvider.overrideWithValue(const Duration(milliseconds: 40)),
      ],
    );
    addTearDown(container.dispose);

    await _waitAuth(container);
    await container.read(cartProvider.future);

    container.read(cartProvider.notifier).updateQty('p1', 2);
    container.read(cartProvider.notifier).updateQty('p1', 3);
    expect(container.read(cartProvider).valueOrNull?.items.single.qty, 3);
    expect(api.updateCalls, isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(api.updateCalls, [3]);
  });

  test('buyer remove is optimistic and does not wait on API', () async {
    final api = _CartApi();
    api.updateBlock = Completer<CartModel>();
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tokenStorageProvider.overrideWithValue(_LoggedInTokens()),
        guestCartStorageProvider.overrideWithValue(MemoryGuestCartStore()),
      ],
    );
    addTearDown(container.dispose);

    await _waitAuth(container);
    await container.read(cartProvider.future);

    container.read(cartProvider.notifier).remove('p1');
    expect(container.read(cartProvider).valueOrNull?.items, isEmpty);
    expect(container.read(cartProvider).isLoading, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(api.removeCalls, ['p1']);
  });

  testWidgets('guest cart stepper updates qty immediately', (tester) async {
    final store = MemoryGuestCartStore([_line()]);
    final api = _CartApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStorageProvider.overrideWithValue(_LoggedOutTokens()),
          guestCartStorageProvider.overrideWithValue(store),
          cartSyncDelayProvider.overrideWithValue(Duration.zero),
        ],
        child: const MaterialApp(home: CartScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('백산수'), findsOneWidget);
    expect(find.text('1'), findsWidgets);

    await tester.tap(find.byTooltip('수량 늘리기'));
    await tester.pump();

    expect(find.text('2'), findsWidgets);
    expect(find.text('백산수'), findsOneWidget);
    expect(api.productIds, isEmpty);
    expect(api.updateCalls, isEmpty);
  });

  testWidgets('buyer cart stepper updates qty without waiting on PUT',
      (tester) async {
    final api = _CartApi();
    api.updateBlock = Completer<CartModel>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStorageProvider.overrideWithValue(_LoggedInTokens()),
          guestCartStorageProvider.overrideWithValue(MemoryGuestCartStore()),
          cartSyncDelayProvider.overrideWithValue(Duration.zero),
        ],
        child: const MaterialApp(home: CartScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('백산수'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.byTooltip('수량 늘리기'));
    await tester.pump();

    expect(find.text('2'), findsWidgets);
    expect(find.text('백산수'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(api.updateBlock!.isCompleted, isFalse);

    api.cartState = _serverCart(qty: 2);
    api.updateBlock!.complete(api.cartState);
    await tester.pump();
    expect(find.text('2'), findsWidgets);
  });
}
