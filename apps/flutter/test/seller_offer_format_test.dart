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

  test('public chip excludes sold out and archived', () {
    expect(sellerOfferIsPublic(_product(stock: 0)), isFalse);
    expect(sellerOfferIsPublic(_product(stock: 1)), isTrue);
    expect(sellerOfferIsPublic(_product(status: 'archived')), isFalse);
    expect(sellerOfferMatchesFilter(_product(stock: 0), 'published'), isFalse);
    expect(sellerOfferMatchesFilter(_product(stock: 1), 'published'), isTrue);
  });

  test('empty copy distinguishes first-time from search filter', () {
    expect(
      sellerOffersEmptyCopy(hasAnyOffers: false, hasQuery: false),
      '아직 등록한 오퍼가 없습니다. 오퍼 등록으로 시작하세요.',
    );
    expect(
      sellerOffersEmptyCopy(hasAnyOffers: true, hasQuery: true),
      '이 검색·조건에 맞는 오퍼가 없습니다.',
    );
  });

  test('bulk summary reports success and first failure', () {
    expect(
      sellerOfferBulkSummary(successCount: 3, failDetails: const []),
      '3건을 적용했습니다.',
    );
    expect(
      sellerOfferBulkSummary(
        successCount: 2,
        failDetails: const ['검수 전에는 공개할 수 없습니다.'],
      ),
      '2건 적용, 1건 실패. 검수 전에는 공개할 수 없습니다.',
    );
    expect(
      sellerOfferBulkSummary(
        successCount: 0,
        failDetails: const ['상품을 찾을 수 없습니다.'],
      ),
      '적용하지 못했습니다. 상품을 찾을 수 없습니다.',
    );
  });
}
