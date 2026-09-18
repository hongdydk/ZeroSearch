import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_mall/core/models/models.dart';
import 'package:shopping_mall/features/seller/seller_offer_format.dart';

final _seller = SellerSummaryModel(
  id: 's1',
  shopName: '입점마트',
  sellerType: 'merchant',
);

ProductModel _product({
  String status = 'published',
  int stock = 10,
  String? optionLabel = '500ml × 20',
  String? flavor = '레몬',
}) {
  return ProductModel(
    id: 'p1',
    title: '백산수',
    priceCredits: 12000,
    stock: stock,
    category: '생수',
    seller: _seller,
    status: status,
    catalogProductId: 'c1',
    optionLabel: optionLabel,
    flavor: flavor,
  );
}

void main() {
  test('option label keeps capacity and flavor', () {
    expect(sellerOfferOptionLabel(_product()), '500ml × 20 · 레몬');
    expect(
      sellerOfferOptionLabel(_product(optionLabel: '2L × 6', flavor: null)),
      '2L × 6',
    );
    expect(
      sellerOfferOptionLabel(_product(optionLabel: '', flavor: '자몽')),
      '자몽',
    );
  });

  test('hidden filter uses archived status', () {
    final hidden = _product(status: 'archived');
    final draft = _product(status: 'draft');
    final published = _product();
    expect(sellerOfferMatchesFilter(hidden, 'hidden'), isTrue);
    expect(sellerOfferMatchesFilter(draft, 'hidden'), isFalse);
    expect(sellerOfferMatchesFilter(published, 'hidden'), isFalse);
    expect(sellerOfferIsHidden(hidden), isTrue);
    expect(sellerOfferStatusLabel(hidden), '숨김');
  });

  test('sold-out filter ignores archived offers', () {
    final archivedEmpty = _product(status: 'archived', stock: 0);
    final publishedEmpty = _product(status: 'published', stock: 0);
    expect(sellerOfferMatchesFilter(archivedEmpty, 'sold_out'), isFalse);
    expect(sellerOfferMatchesFilter(publishedEmpty, 'sold_out'), isTrue);
    expect(sellerOfferMatchesFilter(archivedEmpty, 'hidden'), isTrue);
  });
}
