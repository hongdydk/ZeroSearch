import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_mall/core/network/api_mappers.dart';
import 'package:shopping_mall_api/shopping_mall_api.dart' as gen;

void main() {
  test('product mapper keeps option and catalog fields', () {
    final product = gen.ProductResponse(
      (b) => b
        ..id = 'p1'
        ..title = '백산수'
        ..priceCredits = 12500
        ..stock = 40
        ..category = '생수'
        ..catalogProductId = 'c1'
        ..optionLabel = '500ml × 20'
        ..flavor = '레몬'
        ..volumeMl = 10000
        ..imageUrl = 'https://img.example/water.jpg'
        ..status = gen.ProductResponseStatusEnum.archived
        ..seller.replace(
          gen.SellerSummary(
            (s) => s
              ..id = 's1'
              ..shopName = '입점마트'
              ..sellerType = gen.SellerSummarySellerTypeEnum.merchant,
          ),
        ),
    );

    final mapped = productModelFromGenerated(product);
    expect(mapped.optionLabel, '500ml × 20');
    expect(mapped.flavor, '레몬');
    expect(mapped.volumeMl, 10000);
    expect(mapped.catalogProductId, 'c1');
    expect(mapped.status, 'archived');
    expect(mapped.priceCredits, 12500);
    expect(mapped.stock, 40);
  });
}
