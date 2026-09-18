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
  test('product json keeps unit pack and empty price', () {
    final mapped = ProductModel.fromJson({
      'id': 'p1',
      'title': '백산수',
      'priceCredits': 0,
      'stock': 0,
      'category': '생수',
      'status': 'draft',
      'catalogProductId': 'c1',
      'optionLabel': '2L × 12',
      'unitAmount': 2,
      'unit': 'L',
      'packCount': 12,
      'seller': {
        'id': 's1',
        'shopName': '입점마트',
        'sellerType': 'merchant',
      },
    });
    expect(mapped.unitAmount, 2);
    expect(mapped.unit, 'L');
    expect(mapped.packCount, 12);
    expect(mapped.hasSellablePrice, isFalse);
  });
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

  test('unit fields format 2L pack without folding pack into volume', () {
    final offer = _product(optionLabel: '2L × 12', flavor: null).copyWith(
      unitAmount: 2,
      unit: 'L',
      packCount: 12,
    );
    expect(sellerOfferOptionLabel(offer), '2L × 12');
    expect(formatSellerUnitLabel(amount: 2, unit: 'L', packCount: 12), '2L × 12');
    expect(parseSellerUnitLabel('2L × 12')?.packCount, 12);
    expect(parseSellerUnitLabel('2L × 12')?.amount, 2);
  });

  test('incomplete draft is not sold out', () {
    final incomplete = ProductModel(
      id: 'p1',
      title: '백산수',
      priceCredits: 0,
      stock: 0,
      category: '생수',
      seller: _seller,
      status: 'draft',
      catalogProductId: 'c1',
      optionLabel: '2L × 12',
    );
    expect(incomplete.hasSellablePrice, isFalse);
    expect(sellerOfferMatchesFilter(incomplete, 'sold_out'), isFalse);
    expect(sellerOfferMatchesFilter(incomplete, 'pending'), isTrue);
    expect(sellerOfferStatusLabel(incomplete), '가격 미입력');
    expect(sellerOfferPriceLabel(incomplete), '가격 미입력');
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
