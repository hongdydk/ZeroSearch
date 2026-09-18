import '../../core/models/models.dart';

String sellerOfferOptionLabel(ProductModel product) {
  final parts = <String>[
    if ((product.optionLabel ?? '').trim().isNotEmpty) product.optionLabel!.trim(),
    if ((product.flavor ?? '').trim().isNotEmpty) product.flavor!.trim(),
  ];
  return parts.join(' · ');
}

String sellerOfferStatusLabel(ProductModel product) {
  if (product.status == 'archived') return '숨김';
  if (product.status == 'draft') return '검수 대기';
  if (product.stock <= 0) return '품절';
  if (product.status == 'published') return '공개';
  return '숨김';
}

bool sellerOfferIsHidden(ProductModel product) => product.status == 'archived';

bool sellerOfferMatchesFilter(ProductModel product, String filter) {
  return switch (filter) {
    'published' => product.status == 'published' && product.stock > 0,
    'sold_out' => product.stock <= 0 && product.status != 'archived',
    'pending' => product.status == 'draft',
    'hidden' => product.status == 'archived',
    _ => true,
  };
}

String sellerOfferReviewLabel(ProductModel product) {
  return switch (product.status) {
    'draft' => '검수 대기',
    'published' => '공개',
    'archived' => '숨김',
    _ => product.status,
  };
}
