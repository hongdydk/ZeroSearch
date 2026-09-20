import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cart/cart_actions.dart';
import '../../core/cart/cart_feedback.dart';
import '../../core/cart/guest_cart.dart';
import '../../core/models/models.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../core/format/price_format.dart';
import '../../core/fulfillment/fulfillment_labels.dart';
import '../../core/layout/ui_platform.dart';
import '../../core/routing/app_back_navigation.dart';
import '../../shared/widgets/async_busy.dart';
import '../../shared/widgets/page_form_scaffold.dart';
import '../../shared/widgets/product_image.dart';
import '../../shared/widgets/qty_stepper.dart';
import '../../shared/widgets/seller_badge.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen>
    with AsyncBusyState {
  Future<ProductModel>? _productFuture;
  int _qty = 1;

  Future<ProductModel> _loadProduct() =>
      _productFuture ??= ref.read(apiClientProvider).product(widget.productId);

  Future<void> _addToCart(ProductModel product) async {
    if (isBusy()) return;
    if (ref.read(authStateProvider).isLoading) return;
    final qty = _qty.clamp(1, product.stock < 1 ? 1 : product.stock);

    await runBusy('add', () async {
      try {
        await addOfferToCart(
          ref,
          productId: widget.productId,
          qty: qty,
          snapshot: guestSnapshot(
            productId: widget.productId,
            qty: qty,
            productTitle: product.title,
            priceCredits: product.priceCredits,
            sellerId: product.seller.id,
            shopName: product.seller.shopName,
            sellerType: product.seller.sellerType,
            maxQty: product.stock < 1 ? 99 : product.stock,
          ),
        );
        if (!mounted) return;
        showAddedToCartSnackBar(context);
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authStateProvider);
    return FutureBuilder(
      future: _loadProduct(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return PageFormScaffold(
            maxWidth: isWebUi ? webContentMaxWidth : 720,
            padding: EdgeInsets.all(isWebUi ? 20 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton.icon(
                  onPressed: () => popBrowseOrHome(context),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('뒤로'),
                ),
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
              ],
            ),
          );
        }
        if (snapshot.hasError) {
          return PageFormScaffold(
            maxWidth: isWebUi ? webContentMaxWidth : 720,
            padding: EdgeInsets.all(isWebUi ? 20 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton.icon(
                  onPressed: () => popBrowseOrHome(context),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('뒤로'),
                ),
                const SizedBox(height: 24),
                const Center(child: Text('상품을 불러오지 못했습니다.')),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: () => setState(() => _productFuture = null),
                    child: const Text('다시 시도'),
                  ),
                ),
              ],
            ),
          );
        }
        final product = snapshot.data!;

        return PageFormScaffold(
          maxWidth: isWebUi ? webContentMaxWidth : 720,
          padding: EdgeInsets.all(isWebUi ? 20 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => popBrowseOrHome(context),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('뒤로'),
                ),
              ),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ProductImage(imageUrl: product.imageUrl, title: product.title),
              ),
              const SizedBox(height: 16),
              Text(product.title, style: Theme.of(context).textTheme.headlineSmall),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SellerBadge(
                    shopName: product.seller.shopName,
                    isOfficial: product.isOfficial,
                  ),
                  Text(
                    shippingOwnerLabel(product.seller.sellerType),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                product.category,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                formatWon(product.priceCredits),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text('재고 ${product.stock}개'),
              if (product.description != null && product.description!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(product.description!, style: Theme.of(context).textTheme.bodyLarge),
              ],
              if (product.detailImageUrls.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('상품 상세 정보', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                ...product.detailImageUrls.map((url) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ProductImage(imageUrl: url, title: '${product.title} 상세 이미지'),
                  ),
                )),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  if (product.stock >= 1)
                    QtyStepper(
                      value: _qty.clamp(1, product.stock),
                      max: product.stock,
                      enabled: !isBusy(),
                      onChanged: (v) => setState(() => _qty = v),
                    ),
                  if (product.stock >= 1) const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isBusy() || product.stock < 1
                          ? null
                          : () => _addToCart(product),
                      icon: isBusy()
                          ? busyProgress(size: 18)
                          : const Icon(Icons.add_shopping_cart),
                      label: Text(product.stock < 1 ? '품절' : '장바구니 담기'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
