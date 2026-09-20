import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
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
              _StorefrontHero(storeCount: stores.length),
              const SizedBox(height: 24),
              Text('판매자 사이트', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: AppTheme.brandTeal)),
              const SizedBox(height: 5),
              const Text('공식 스토어와 입점 판매자의 진열 상품·소개를 확인하세요.'),
              const SizedBox(height: 14),
              if (stores.isEmpty)
                const _MessageState(message: '현재 공개된 판매자 사이트가 없습니다.')
              else
                LayoutBuilder(builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 700 ? 3 : constraints.maxWidth >= 460 ? 2 : 1;
                  return GridView.count(
                    crossAxisCount: columns,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: columns == 1 ? 3.3 : 1.15,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [for (final store in stores) _StoreTile(store: store, onTap: () => context.push('/stores/${store.slug}'))],
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _StorefrontHero extends StatelessWidget {
  const _StorefrontHero({required this.storeCount});
  final int storeCount;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      gradient: const LinearGradient(colors: [AppTheme.brandTeal, Color(0xFF0B6A62)], begin: Alignment.topLeft, end: Alignment.bottomRight),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('공식 · 입점 스토어', style: TextStyle(color: Color(0xFFCDE8E4), fontWeight: FontWeight.w700)),
      const SizedBox(height: 7),
      const Text('입점 판매자 둘러보기', style: TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w700)),
      const SizedBox(height: 7),
      Text('현재 $storeCount개 판매자 사이트가 열려 있습니다.', style: const TextStyle(color: Color(0xFFD5E2E0))),
    ]),
  );
}

class _StoreTile extends StatelessWidget {
  const _StoreTile({required this.store, required this.onTap});
  final StorefrontModel store;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(backgroundColor: store.isOfficial ? const Color(0xFFCCFBF1) : const Color(0xFFEDE9FE), child: Icon(store.isOfficial ? Icons.verified_outlined : Icons.storefront_outlined, color: store.isOfficial ? const Color(0xFF0F766E) : const Color(0xFF7C3AED))),
            const Spacer(), const Icon(Icons.arrow_outward, size: 19, color: AppTheme.brandTeal),
          ]),
          const Spacer(),
          Text(store.shopName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          SellerBadge(shopName: store.isOfficial ? '공식 스토어' : '입점 스토어', isOfficial: store.isOfficial),
          const SizedBox(height: 10),
          Text(store.productCount > 0 ? '판매 중인 상품 ${store.productCount}개' : '상품 준비 중', style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    ),
  );
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
