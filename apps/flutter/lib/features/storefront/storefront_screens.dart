import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/page_form_scaffold.dart';
import '../../shared/widgets/product_image.dart';
import '../../shared/widgets/seller_badge.dart';

class StorefrontListScreen extends ConsumerStatefulWidget {
  const StorefrontListScreen({super.key});

  @override
  ConsumerState<StorefrontListScreen> createState() => _StorefrontListScreenState();
}

class _StorefrontListScreenState extends ConsumerState<StorefrontListScreen> {
  late Future<List<StorefrontModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<StorefrontModel>> _load() => ref.read(apiClientProvider).storefronts();

  void _retry() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return PageFormScaffold(
      maxWidth: 940,
      child: FutureBuilder<List<StorefrontModel>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException
                ? (snapshot.error! as ApiException).message
                : '판매자 목록을 불러오지 못했습니다.';
            return _MessageState(message: message, actionLabel: '다시 시도', onAction: _retry);
          }
          final stores = snapshot.data ?? const [];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('입점 판매자', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('공식 스토어와 입점 판매자의 사이트를 둘러보세요. 상품이 준비 중인 가게도 확인할 수 있습니다.'),
              const SizedBox(height: 18),
              if (stores.isEmpty)
                const _MessageState(message: '현재 공개된 판매자 사이트가 없습니다.')
              else
                ...stores.map(
                  (store) => Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Icon(store.isOfficial ? Icons.verified_outlined : Icons.storefront_outlined)),
                      title: SellerBadge(shopName: store.shopName, isOfficial: store.isOfficial),
                      subtitle: Text(store.productCount > 0 ? '판매 중인 상품 ${store.productCount}개' : '상품 준비 중'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/stores/${store.slug}'),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class StorefrontDetailScreen extends ConsumerStatefulWidget {
  const StorefrontDetailScreen({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<StorefrontDetailScreen> createState() => _StorefrontDetailScreenState();
}

class _StorefrontDetailScreenState extends ConsumerState<StorefrontDetailScreen> {
  late Future<StorefrontDetailModel> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<StorefrontDetailModel> _load() => ref.read(apiClientProvider).storefront(widget.slug);

  @override
  Widget build(BuildContext context) {
    return PageFormScaffold(
      maxWidth: 940,
      child: FutureBuilder<StorefrontDetailModel>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException
                ? (snapshot.error! as ApiException).message
                : '판매자 사이트를 불러오지 못했습니다.';
            return _MessageState(message: message, actionLabel: '판매자 목록', onAction: () => context.go('/stores'));
          }
          final store = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(onPressed: () => context.go('/stores'), icon: const Icon(Icons.arrow_back), label: const Text('입점 판매자')),
              const SizedBox(height: 8),
              if (store.storeBannerUrl != null)
                ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(height: 180, width: double.infinity, child: ProductImage(imageUrl: store.storeBannerUrl, title: store.shopName))),
              if (store.storeBannerUrl != null) const SizedBox(height: 14),
              if (store.storeLogoUrl != null)
                SizedBox(width: 64, height: 64, child: ClipOval(child: ProductImage(imageUrl: store.storeLogoUrl, title: store.shopName))),
              if (store.storeLogoUrl != null) const SizedBox(height: 10),
              SellerBadge(shopName: store.shopName, isOfficial: store.isOfficial),
              const SizedBox(height: 14),
              Text('${store.shopName} 판매자 사이트', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              if ((store.storeDescription ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(store.storeDescription!),
              ],
              const SizedBox(height: 18),
              if (store.products.isEmpty)
                const _MessageState(message: '상품을 준비하고 있습니다. 판매자 사이트는 정상적으로 열렸습니다.')
              else
                ...store.products.map(
                  (product) => Card(
                    child: ListTile(
                      leading: SizedBox(width: 52, height: 52, child: ProductImage(imageUrl: product.imageUrl, title: product.title)),
                      title: Text(product.title),
                      subtitle: Text('${product.priceCredits}원 · 재고 ${product.stock}개'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/products/${product.id}'),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.storefront_outlined, size: 42),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              if (onAction != null) ...[
                const SizedBox(height: 12),
                TextButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      );
}
