import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format/price_format.dart';
import '../../core/layout/ui_platform.dart';
import '../../core/models/models.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/page_form_scaffold.dart';
import '../../shared/widgets/product_image.dart';
import '../../shared/widgets/seller_badge.dart';

class CatalogDetailScreen extends ConsumerStatefulWidget {
  const CatalogDetailScreen({super.key, required this.catalogId});

  final String catalogId;

  @override
  ConsumerState<CatalogDetailScreen> createState() => _CatalogDetailScreenState();
}

class _CatalogDetailScreenState extends ConsumerState<CatalogDetailScreen> {
  String? _loadingOfferId;

  Future<void> _addToCart(String offerId) async {
    if (_loadingOfferId != null) return;
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth?.isLoggedIn != true) {
      if (!mounted) return;
      context.go('/login');
      return;
    }

    setState(() => _loadingOfferId = offerId);
    try {
      await ref.read(apiClientProvider).addToCart(offerId);
      ref.invalidate(cartProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('장바구니에 담았습니다.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Theme.of(context).colorScheme.error),
      );
    } finally {
      if (mounted) setState(() => _loadingOfferId = null);
    }
  }

  String _offerLabel(CatalogOfferModel offer) {
    final parts = <String>[];
    if (offer.optionLabel != null && offer.optionLabel!.isNotEmpty) {
      parts.add(offer.optionLabel!);
    }
    if (offer.flavor != null && offer.flavor!.isNotEmpty) {
      parts.add(offer.flavor!);
    }
    return parts.isEmpty ? '기본' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(catalogProductDetailProvider(widget.catalogId));

    return detailAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('상품을 불러오지 못했습니다: $e')),
      data: (detail) => PageFormScaffold(
        maxWidth: isWebUi ? webContentMaxWidth : 960,
        padding: EdgeInsets.all(isWebUi ? 20 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: isWebUi ? 160 : 120,
                  height: isWebUi ? 160 : 120,
                  child: ProductImage(imageUrl: detail.imageUrl, title: detail.title),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(detail.title, style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text(
                        detail.category,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      if (detail.description != null && detail.description!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(detail.description!),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('판매 옵션', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (detail.offers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('표시할 오퍼가 없습니다.')),
              )
            else
              ...detail.offers.map((offer) {
                final loading = _loadingOfferId == offer.id;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(_offerLabel(offer)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SellerBadge(
                          shopName: offer.seller.shopName,
                          isOfficial: offer.isOfficial,
                        ),
                        if (offer.volumeMl != null)
                          Text(
                            '용량 ${offer.volumeMl}ml',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formatWon(offer.priceCredits),
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _loadingOfferId != null || offer.stock < 1
                              ? null
                              : () => _addToCart(offer.id),
                          child: loading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(offer.stock < 1 ? '품절' : '담기'),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            if (detail.offerCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '전체 ${detail.offerCount}건 · 필터 적용 시 목록과 동일',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
