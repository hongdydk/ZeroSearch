/// API `priceCredits` 값을 화면용 원화 문자열로 표시.
String formatWon(int amount, {bool fromPrice = false}) {
  final digits = amount.toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buf.write(',');
    }
    buf.write(digits[i]);
  }
  return fromPrice ? '${buf.toString()}원~' : '${buf.toString()}원';
}

/// 대표 상품 카드 — 단위당 중앙값 또는 원화 중앙값. 최저가·「~」 없음.
String formatCatalogRepresentativePrice({
  required String priceUnit,
  required String displayPriceLabel,
  double? medianUnitPrice,
  int? medianPriceCredits,
}) {
  if (priceUnit == 'ml' && medianUnitPrice != null) {
    final perLiter = (medianUnitPrice * 1000).round();
    return '$displayPriceLabel ${formatWon(perLiter)}(중앙값)';
  }
  if (medianPriceCredits != null) {
    return '${formatWon(medianPriceCredits)}(중앙값)';
  }
  // 공개 오퍼가 없으면 카드는 유지하고 가격만 숨긴다.
  return '가격 정보 없음';
}

/// 수량·단가 줄: `12,000원 × 2`
String formatWonLine(int unitPrice, int qty) => '${formatWon(unitPrice)} × $qty';
