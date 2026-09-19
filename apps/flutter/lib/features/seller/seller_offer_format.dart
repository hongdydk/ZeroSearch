import '../../core/format/price_format.dart';
import '../../core/models/models.dart';

const sellerOfferUnits = ['ml', 'L', 'g', 'kg', '팩'];

final _unitLabelPattern = RegExp(
  r'^\s*(\d+(?:\.\d+)?)\s*(ml|l|g|kg|팩)\s*(?:[×xX*]\s*(\d+))?\s*$',
  caseSensitive: false,
);

String formatSellerUnitLabel({
  required num amount,
  required String unit,
  int packCount = 1,
}) {
  final amountText = amount == amount.roundToDouble()
      ? amount.round().toString()
      : amount.toString();
  final base = '$amountText$unit';
  if (packCount <= 1) return base;
  return '$base × $packCount';
}

({double amount, String unit, int packCount})? parseSellerUnitLabel(String? label) {
  final text = (label ?? '').trim();
  if (text.isEmpty) return null;
  final match = _unitLabelPattern.firstMatch(text);
  if (match == null) return null;
  final amount = double.parse(match.group(1)!);
  final rawUnit = match.group(2)!;
  final lowered = rawUnit.toLowerCase();
  final unit = switch (lowered) {
    'ml' => 'ml',
    'l' => 'L',
    'g' => 'g',
    'kg' => 'kg',
    _ => rawUnit,
  };
  final pack = int.parse(match.group(3) ?? '1');
  return (amount: amount, unit: unit, packCount: pack);
}

String sellerOfferOptionLabel(ProductModel product) {
  final unitLabel = product.unitAmount != null && (product.unit ?? '').isNotEmpty
      ? formatSellerUnitLabel(
          amount: product.unitAmount!,
          unit: product.unit!,
          packCount: product.packCount,
        )
      : (product.optionLabel ?? '').trim();
  final parts = <String>[
    if (unitLabel.isNotEmpty) unitLabel,
    if ((product.flavor ?? '').trim().isNotEmpty) product.flavor!.trim(),
  ];
  return parts.join(' · ');
}

String sellerOfferPriceLabel(ProductModel product) {
  if (!product.hasSellablePrice) return '가격 미입력';
  return formatWon(product.priceCredits);
}

String sellerOfferRowSubtitle(ProductModel product) {
  final option = sellerOfferOptionLabel(product);
  return [
    if (option.isNotEmpty) option,
    sellerOfferPriceLabel(product),
    if (product.hasSellablePrice) '재고 ${product.stock}',
  ].join(' · ');
}

String sellerOfferStatusLabel(ProductModel product) {
  if (product.status == 'archived') return '숨김';
  if (product.status == 'draft' && !product.hasSellablePrice) return '가격 미입력';
  if (product.status == 'draft') return '검수 대기';
  if (product.stock <= 0) return '품절';
  if (product.status == 'published') return '공개';
  return '숨김';
}

bool sellerOfferIsHidden(ProductModel product) => product.status == 'archived';

bool sellerOfferIsPublic(ProductModel product) =>
    product.status == 'published' && product.stock > 0;

bool sellerOfferMatchesFilter(ProductModel product, String filter) {
  return switch (filter) {
    'published' => sellerOfferIsPublic(product),
    'sold_out' =>
      product.stock <= 0 && product.status == 'published',
    'pending' => product.status == 'draft',
    'hidden' => product.status == 'archived',
    _ => true,
  };
}

String sellerOffersEmptyCopy({
  required bool hasAnyOffers,
  required bool hasQuery,
}) {
  if (!hasAnyOffers && !hasQuery) {
    return '아직 등록한 오퍼가 없습니다. 오퍼 등록으로 시작하세요.';
  }
  return '이 검색·조건에 맞는 오퍼가 없습니다.';
}

String sellerOfferReviewLabel(ProductModel product) {
  return switch (product.status) {
    'draft' when !product.hasSellablePrice => '가격 미입력',
    'draft' => '검수 대기',
    'published' => '공개',
    'archived' => '숨김',
    _ => product.status,
  };
}
