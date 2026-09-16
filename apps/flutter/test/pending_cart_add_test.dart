import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_mall/core/cart/pending_cart_add.dart';
import 'package:shopping_mall/core/routing/login_location.dart';

void main() {
  test('withPendingCartAdd encodes offer and qty', () {
    final uri = withPendingCartAdd(
      Uri(path: '/catalog/cat-1'),
      productId: 'offer-1',
      qty: 3,
    );
    expect(uri.path, '/catalog/cat-1');
    expect(uri.queryParameters['addOffer'], 'offer-1');
    expect(uri.queryParameters['addQty'], '3');
  });

  test('tryParse accepts offer id and qty', () {
    final parsed = PendingCartAdd.tryParse(
      Uri.parse('/catalog/cat-1?addOffer=offer-1&addQty=3'),
    );
    expect(parsed?.productId, 'offer-1');
    expect(parsed?.qty, 3);
  });

  test('tryParse rejects unsafe ids and qty', () {
    expect(
      PendingCartAdd.tryParse(Uri.parse('/catalog/x?addOffer=../etc&addQty=1')),
      isNull,
    );
    expect(
      PendingCartAdd.tryParse(Uri.parse('/catalog/x?addOffer=offer-1&addQty=0')),
      isNull,
    );
  });

  test('stripPendingCartQuery removes only add params', () {
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
        Uri(path: '/login', queryParameters: {'next': '/catalog/cat-1'}),
      ),
      '/login?next=${Uri.encodeQueryComponent('/catalog/cat-1')}',
    );
    expect(buyerLoginLocation(Uri(path: '/login')), '/login');
  });
}
