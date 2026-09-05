import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format/price_format.dart';
import '../../core/fulfillment/fulfillment_labels.dart';
import '../../core/layout/ui_platform.dart';
import '../../core/models/models.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../core/routing/app_back_navigation.dart';
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
      context.go(
        Uri(
          path: '/login',
          queryParameters: {'next': '/catalog/${widget.catalogId}'},
        ).toString(),
      );
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
      skipLoadingOnReload: true,
      loading: () => PageFormScaffold(
        maxWidth: isWebUi ? webContentMaxWidth : 960,
        padding: EdgeInsets.all(isWebUi ? 20 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailBackButton(onPressed: () => popBrowseOrHome(context)),
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
      error: (e, _) => PageFormScaffold(
        maxWidth: isWebUi ? webContentMaxWidth : 960,
        padding: EdgeInsets.all(isWebUi ? 20 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailBackButton(onPressed: () => popBrowseOrHome(context)),
            const SizedBox(height: 24),
            const Center(child: Text('상품을 불러오지 못했습니다.')),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () => ref.invalidate(catalogProductDetailProvider(widget.catalogId)),
                child: const Text('다시 시도'),
              ),
            ),
          ],
        ),
      ),
      data: (detail) => PageFormScaffold(
        maxWidth: isWebUi ? webContentMaxWidth : 960,
        padding: EdgeInsets.all(isWebUi ? 20 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: _DetailBackButton(onPressed: () => popBrowseOrHome(context)),
            ),
            const SizedBox(height: 8),
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
                child: Center(child: Text('지금은 비교할 판매 옵션이 없습니다.')),
              )
            else
              ...detail.offers.map((offer) {
                final loading = _loadingOfferId == offer.id;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _offerLabel(offer),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SellerBadge(
                              shopName: offer.seller.shopName,
                              isOfficial: offer.isOfficial,
                            ),
                            Text(
                              shippingOwnerLabel(offer.seller.sellerType),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (offer.volumeMl != null)
                              Text(
                                '용량 ${offer.volumeMl}ml',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                formatWon(offer.priceCredits),
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
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

class _DetailBackButton extends StatelessWidget {
  const _DetailBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.arrow_back, size: 18),
      label: const Text('뒤로'),
    );
  }
}
