import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shopping_mall/core/cart/guest_cart.dart';
import 'package:shopping_mall/core/cart/guest_cart_storage.dart';
import 'package:shopping_mall/core/models/models.dart';
import 'package:shopping_mall/core/network/api_client.dart';
import 'package:shopping_mall/core/network/api_exception.dart';
import 'package:shopping_mall/core/routing/app_router.dart';
import 'package:shopping_mall/core/routing/login_location.dart';
import 'package:shopping_mall/core/routing/safe_next_path.dart';

class _MergeApi extends ApiClient {
  _MergeApi() : super(tokenReader: () async => 'tok');

  final List<(String, int)> added = [];
  CartModel userCart = CartModel(items: const [], totalCredits: 0);

  @override
  Future<CartModel> addToCart(String productId, {int qty = 1}) async {
    added.add((productId, qty));
    final existing = userCart.items.where((item) => item.productId == productId);
    if (existing.isEmpty) {
      userCart = CartModel(
        items: [
          ...userCart.items,
          CartItemModel(
            id: productId,
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
        totalCredits: userCart.totalCredits + 1200 * qty,
      );
    } else {
      final next = [
        for (final item in userCart.items)
          if (item.productId == productId)
            CartItemModel(
              id: item.id,
              productId: item.productId,
              productTitle: item.productTitle,
              qty: item.qty + qty,
              priceCredits: item.priceCredits,
              lineTotalCredits: item.priceCredits * (item.qty + qty),
              sellerId: item.sellerId,
              shopName: item.shopName,
              sellerType: item.sellerType,
            )
          else
            item,
      ];
      userCart = cartModelFromItems(next);
    }
    return userCart;
  }
}

class _FailingMergeApi extends _MergeApi {
  @override
  Future<CartModel> addToCart(String productId, {int qty = 1}) async {
    throw ApiException('재고가 부족합니다.', statusCode: 400);
  }
}

GuestCartLine _line(String id, int qty) => GuestCartLine(
      productId: id,
      qty: qty,
      productTitle: '백산수',
      priceCredits: 1200,
      sellerId: 's1',
      shopName: '공식 스토어',
      sellerType: 'platform',
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('guest add merges the same offer into one line and persists', () async {
    final first = GuestCartStorage();
    await first.add('offer-1', 2, snapshot: _line('offer-1', 2));
    await first.add('offer-1', 3, snapshot: _line('offer-1', 3));

    final reloaded = GuestCartStorage();
    final lines = await reloaded.load();
    expect(lines, hasLength(1));
    expect(lines.single.productId, 'offer-1');
    expect(lines.single.qty, 5);
    expect(lines.single.productTitle, '백산수');
  });

  test('login merge posts each guest line then clears; retry does not duplicate',
      () async {
    final guest = GuestCartStorage();
    await guest.add('offer-1', 2, snapshot: _line('offer-1', 2));
    final api = _MergeApi();

    await mergeGuestCartIntoUser(api: api, guest: guest);
    expect(api.added, [('offer-1', 2)]);
    expect(api.userCart.items.single.qty, 2);
    expect(await guest.load(), isEmpty);

    await mergeGuestCartIntoUser(api: api, guest: guest);
    expect(api.added, [('offer-1', 2)]);
    expect(api.userCart.items, hasLength(1));
    expect(api.userCart.items.single.qty, 2);
  });

  test('login merge stacks qty onto the same user offer without a second line',
      () async {
    final guest = GuestCartStorage();
    await guest.add('offer-1', 3, snapshot: _line('offer-1', 3));
    final api = _MergeApi();
    await api.addToCart('offer-1', qty: 1);

    await mergeGuestCartIntoUser(api: api, guest: guest);
    expect(api.userCart.items, hasLength(1));
    expect(api.userCart.items.single.qty, 4);
    expect(await guest.load(), isEmpty);
  });

  test('unsellable guest lines are dropped on merge so cart load can continue',
      () async {
    final guest = GuestCartStorage();
    await guest.add('offer-1', 1, snapshot: _line('offer-1', 1));
    await mergeGuestCartIntoUser(api: _FailingMergeApi(), guest: guest);
    expect(await guest.load(), isEmpty);
  });

  test('stripPendingCartQuery still clears legacy add params', () {
    expect(
      stripPendingCartQuery('/catalog/cat-1?addOffer=offer-1&addQty=2'),
      '/catalog/cat-1',
    );
    final stripped = stripPendingCartQuery(
      '/catalog/cat-1?addOffer=o1&addQty=2&flavor=레몬',
    );
    final uri = Uri.parse(stripped!);
    expect(uri.path, '/catalog/cat-1');
    expect(uri.queryParameters['flavor'], '레몬');
    expect(uri.queryParameters.containsKey('addOffer'), isFalse);
    expect(stripPendingCartQuery('https://evil.example/x'), isNull);
  });

  test('buyerLoginLocation uses current path and keeps existing next', () {
    expect(
      buyerLoginLocation(Uri(path: '/catalog/cat-1')),
      '/login?next=${Uri.encodeQueryComponent('/catalog/cat-1')}',
    );
    expect(
      buyerLoginLocation(
        Uri(path: '/login', queryParameters: {'next': '/checkout'}),
      ),
      '/login?next=${Uri.encodeQueryComponent('/checkout')}',
    );
    expect(buyerLoginLocation(Uri(path: '/login')), '/login');
  });

  test('checkout still requires login; cart and catalog do not', () {
    expect(requiresBuyerAuth('/checkout'), isTrue);
    expect(requiresBuyerAuth('/orders'), isTrue);
    expect(requiresBuyerAuth('/cart'), isFalse);
    expect(requiresBuyerAuth('/catalog/cat-1'), isFalse);
    expect(requiresBuyerAuth('/products/p1'), isFalse);
    expect(requiresBuyerAuth('/'), isFalse);
  });
}
