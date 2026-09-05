import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../core/format/price_format.dart';
import '../../core/fulfillment/fulfillment_labels.dart';
import '../../core/layout/ui_platform.dart';
import '../../core/routing/app_back_navigation.dart';
import '../../shared/widgets/page_form_scaffold.dart';
import '../../shared/widgets/product_image.dart';
import '../../shared/widgets/seller_badge.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  bool _loading = false;

  Future<void> _addToCart() async {
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth?.isLoggedIn != true) {
      if (!mounted) return;
      context.go(
        Uri(
          path: '/login',
          queryParameters: {'next': '/products/${widget.productId}'},
        ).toString(),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(apiClientProvider).addToCart(widget.productId);
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
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: ref.read(apiClientProvider).product(widget.productId),
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
                    onPressed: () => setState(() {}),
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
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loading || product.stock < 1 ? null : _addToCart,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_shopping_cart),
                label: Text(product.stock < 1 ? '품절' : '장바구니 담기'),
              ),
            ],
          ),
        );
      },
    );
  }
}
