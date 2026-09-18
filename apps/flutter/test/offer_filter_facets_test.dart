import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_mall/core/catalog/browse_location.dart';

void main() {
  test('sikhye/plain samdasoo result set does not get lemon grapefruit chips', () {
    final facets = offerFilterFacets(
      availableFlavors: const [],
      hasVolumeMin2000: false,
    );
    expect(facets.hasChips, isFalse);
    expect(facets.flavors, isEmpty);
  });

  test('flavors stay scoped to the current result set', () {
    final facets = offerFilterFacets(
      availableFlavors: const ['레몬', '레몬', ' 자몽 '],
      hasVolumeMin2000: true,
    );
    expect(facets.flavors, ['레몬', '자몽']);
    expect(facets.hasVolumeMin2000, isTrue);
    expect(facets.hasChips, isTrue);
  });

  test('생수/음료 L1 alone does not force water chips', () {
    expect(
      showsWaterFilters(l1: '생수/음료'),
      isFalse,
    );
  });

  test('browseLocation keeps axis=seller without collapsing to brand', () {
    final l1Uri = Uri.parse(browseLocation(l1: '라면/면류', axis: 'seller'));
    expect(l1Uri.queryParameters['l1'], '라면/면류');
    expect(l1Uri.queryParameters['axis'], 'seller');
    expect(l1Uri.queryParameters.containsKey('brand'), isFalse);
    expect(l1Uri.queryParameters.containsKey('menu'), isFalse);

    final searchUri = Uri.parse(browseLocation(q: '신라면', axis: 'seller'));
    expect(searchUri.queryParameters['q'], '신라면');
    expect(searchUri.queryParameters['axis'], 'seller');
  });
}
