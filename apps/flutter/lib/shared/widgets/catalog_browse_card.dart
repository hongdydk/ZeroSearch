import 'package:flutter/material.dart';

import '../../core/format/price_format.dart';
import '../../core/theme/app_theme.dart';
import 'product_image.dart';

/// 구매자 목록과 같은 대표 카드 레이아웃. 관리자 목록에서도 재사용한다.
class CatalogBrowseCard extends StatelessWidget {
  const CatalogBrowseCard({
    super.key,
    required this.title,
    required this.cardTitle,
    required this.offerCount,
    required this.priceUnit,
    required this.displayPriceLabel,
    this.imageUrl,
    this.medianUnitPrice,
    this.medianPriceCredits,
    this.shopCount,
    this.statusLabel,
    this.optionSummary,
    this.onTap,
    this.action,
  });

  final String title;
  final String cardTitle;
  final int offerCount;
  final String priceUnit;
  final String displayPriceLabel;
  final String? imageUrl;
  final double? medianUnitPrice;
  final int? medianPriceCredits;
  final int? shopCount;
  final String? statusLabel;
  final String? optionSummary;
  final VoidCallback? onTap;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final hasPrice = medianUnitPrice != null || medianPriceCredits != null;
    final priceLabel = formatCatalogRepresentativePrice(
      priceUnit: priceUnit,
      displayPriceLabel: displayPriceLabel,
      medianUnitPrice: medianUnitPrice,
      medianPriceCredits: medianPriceCredits,
    );
    final offerLine = offerCount > 0 ? '오퍼 $offerCount' : '오퍼 없음';
    final meta = [
      if (shopCount != null) '가게 $shopCount',
      if (statusLabel != null && statusLabel!.isNotEmpty) statusLabel!,
    ].join(' · ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _CatalogCardThumb(imageUrl: imageUrl, title: title)),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    cardTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    priceLabel,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: hasPrice ? FontWeight.w700 : FontWeight.w500,
                          color: hasPrice
                              ? AppTheme.priceBurgundy
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    offerLine,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  if (optionSummary != null && optionSummary!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '옵션: $optionSummary',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                  ?action,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogCardThumb extends StatelessWidget {
  const _CatalogCardThumb({this.imageUrl, required this.title});

  final String? imageUrl;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ProductImage(imageUrl: imageUrl, title: title);
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD5E2E0), Color(0xFFEFF5F5)],
        ),
      ),
      child: Center(
        child: Text(
          title.isNotEmpty ? title.substring(0, 1) : '?',
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w600,
            color: AppTheme.brandTeal,
          ),
        ),
      ),
    );
  }
}
