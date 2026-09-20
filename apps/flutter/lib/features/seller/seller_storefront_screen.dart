import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/async_busy.dart';
import '../../shared/widgets/page_form_scaffold.dart';
import '../../shared/widgets/portal_workspace.dart';
import '../../shared/widgets/product_image.dart';

class SellerStorefrontScreen extends ConsumerStatefulWidget {
  const SellerStorefrontScreen({super.key});

  @override
  ConsumerState<SellerStorefrontScreen> createState() => _SellerStorefrontScreenState();
}

class _SellerStorefrontScreenState extends ConsumerState<SellerStorefrontScreen> with AsyncBusyState {
  final _description = TextEditingController();
  String? _logoUrl;
  String? _bannerUrl;
  bool _loading = true;
  SellerModel? _seller;
  List<ProductModel> _storeProducts = [];
  Set<String> _featuredProductIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final results = await Future.wait([api.sellerMe(), api.sellerProducts(limit: 100)]);
      final seller = results[0] as SellerModel?;
      final productPage = results[1] as SellerProductListPage;
      if (seller == null || !mounted) return;
      setState(() {
        _seller = seller;
        _description.text = seller.storeDescription ?? '';
        _logoUrl = seller.storeLogoUrl;
        _bannerUrl = seller.storeBannerUrl;
        _storeProducts = productPage.items.where((product) => product.status == 'published').toList()
          ..sort((a, b) => a.storefrontRank.compareTo(b.storefrontRank));
        _featuredProductIds = productPage.items
            .where((product) => product.status == 'published' && product.storefrontFeatured)
            .map((product) => product.id)
            .toSet();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickImage(bool banner) async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final file = picked?.files.single;
    if (file?.bytes == null) return;
    await runBusy(banner ? 'banner' : 'logo', () async {
      try {
        final url = await ref.read(apiClientProvider).sellerUploadImage(file!.bytes!, file.name);
        if (mounted) setState(() { if (banner) _bannerUrl = url; else _logoUrl = url; });
      } on ApiException catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    });
  }

  Future<void> _save() async {
    await runBusy('save', () async {
      try {
        await ref.read(apiClientProvider).sellerUpdateStorefront(
          storeDescription: _description.text.trim(), storeLogoUrl: _logoUrl, storeBannerUrl: _bannerUrl,
        );
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('판매자 사이트를 저장했습니다.')));
      } on ApiException catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    });
  }

  Future<void> _saveLayout() async {
    if (isBusy('layout')) return;
    await runBusy('layout', () async {
      try {
        await ref.read(apiClientProvider).sellerUpdateStorefrontLayout(
          productIds: _storeProducts.map((product) => product.id).toList(),
          featuredProductIds: _featuredProductIds.toList(),
        );
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('상품 진열을 저장했습니다.')));
      } on ApiException catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    });
  }

  void _moveProduct(int index, int delta) {
    final next = index + delta;
    if (next < 0 || next >= _storeProducts.length) return;
    setState(() {
      final products = [..._storeProducts];
      final product = products.removeAt(index);
      products.insert(next, product);
      _storeProducts = products;
    });
  }

  void _toggleFeatured(String productId) {
    setState(() {
      final featured = {..._featuredProductIds};
      if (featured.contains(productId)) {
        featured.remove(productId);
      } else if (featured.length < 6) {
        featured.add(productId);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('추천 상품은 최대 6개까지 고를 수 있습니다.')));
      }
      _featuredProductIds = featured;
    });
  }

  void _openStore() {
    final slug = _seller?.slug;
    if (slug == null || slug.isEmpty) return;
    context.push('/stores/$slug');
  }

  void _showPreview() {
    final seller = _seller;
    if (seller == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('판매자 사이트 미리보기', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            if (_bannerUrl != null) ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(height: 120, child: ProductImage(imageUrl: _bannerUrl, title: seller.shopName))),
            if (_bannerUrl != null) const SizedBox(height: 12),
            Row(children: [
              if (_logoUrl != null) SizedBox(width: 52, height: 52, child: ClipOval(child: ProductImage(imageUrl: _logoUrl, title: seller.shopName))),
              if (_logoUrl != null) const SizedBox(width: 10),
              Expanded(child: Text(seller.shopName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            ]),
            if (_description.text.trim().isNotEmpty) ...[const SizedBox(height: 10), Text(_description.text.trim(), maxLines: 3, overflow: TextOverflow.ellipsis)],
            const SizedBox(height: 14),
            const Text('공개된 상품은 이 아래에 진열되며, 상품을 선택하면 상세 정보와 상세 이미지가 표시됩니다.'),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: () { Navigator.pop(context); _openStore(); }, icon: const Icon(Icons.open_in_new), label: const Text('공개 사이트 열기')),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PortalWorkspaceScaffold(
      role: PortalWorkspaceRole.seller,
      activePath: '/seller/storefront',
      child: PortalPage(
        eyebrow: '공개 판매자 사이트',
        title: '내 판매자 사이트 관리',
        trailing: Wrap(spacing: 4, children: [
          TextButton.icon(onPressed: _seller == null ? null : _showPreview, icon: const Icon(Icons.visibility_outlined), label: const Text('미리보기')),
          TextButton.icon(onPressed: _seller == null ? null : _openStore, icon: const Icon(Icons.open_in_new), label: const Text('사이트 바로가기')),
          TextButton.icon(onPressed: () => context.go('/seller/products/new'), icon: const Icon(Icons.add), label: const Text('상품 등록')),
        ]),
        child: _loading ? const Center(child: CircularProgressIndicator()) : PageFormScaffold(
          maxWidth: 760,
          padding: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('이 화면에서 꾸민 정보는 구매자 메인의 판매자 목록과 판매자 사이트에 표시됩니다.', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 18),
            _ImageField(label: '배너 이미지', imageUrl: _bannerUrl, busy: isBusy('banner'), onUpload: () => _pickImage(true), onClear: () => setState(() => _bannerUrl = null)),
            const SizedBox(height: 16),
            _ImageField(label: '로고 이미지', imageUrl: _logoUrl, busy: isBusy('logo'), onUpload: () => _pickImage(false), onClear: () => setState(() => _logoUrl = null)),
            const SizedBox(height: 16),
            TextField(controller: _description, minLines: 3, maxLines: 5, maxLength: 500, decoration: const InputDecoration(labelText: '스토어 소개', hintText: '판매자 사이트에 보여 줄 소개를 입력하세요.')),
            const SizedBox(height: 8),
            FilledButton(onPressed: isBusy('save') ? null : _save, child: Text(isBusy('save') ? '저장 중…' : '판매자 사이트 저장')),
            const SizedBox(height: 24),
            PortalSection(
              title: '상품 진열',
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: _storeProducts.isEmpty
                    ? const Text('공개된 상품이 생기면 여기서 사이트 진열 순서와 추천 상품을 정할 수 있습니다.')
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('위·아래 버튼으로 상품 순서를 정하고, 별표를 누르면 사이트 상단의 추천 상품으로 표시됩니다.', style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 10),
                        for (var index = 0; index < _storeProducts.length; index++)
                          _MerchandisingProductRow(
                            product: _storeProducts[index],
                            featured: _featuredProductIds.contains(_storeProducts[index].id),
                            onMoveUp: index == 0 ? null : () => _moveProduct(index, -1),
                            onMoveDown: index == _storeProducts.length - 1 ? null : () => _moveProduct(index, 1),
                            onToggleFeatured: () => _toggleFeatured(_storeProducts[index].id),
                          ),
                        const SizedBox(height: 8),
                        FilledButton.icon(onPressed: isBusy('layout') ? null : _saveLayout, icon: const Icon(Icons.save_outlined), label: Text(isBusy('layout') ? '저장 중…' : '상품 진열 저장')),
                      ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _MerchandisingProductRow extends StatelessWidget {
  const _MerchandisingProductRow({required this.product, required this.featured, required this.onMoveUp, required this.onMoveDown, required this.onToggleFeatured});
  final ProductModel product;
  final bool featured;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onToggleFeatured;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: SizedBox(width: 44, height: 44, child: ProductImage(imageUrl: product.imageUrl, title: product.title)),
      title: Text(product.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${product.priceCredits}원'),
      trailing: Wrap(spacing: 0, children: [
        IconButton(onPressed: onToggleFeatured, tooltip: '추천 상품', icon: Icon(featured ? Icons.star : Icons.star_border, color: featured ? Colors.amber.shade700 : null)),
        IconButton(onPressed: onMoveUp, tooltip: '위로', icon: const Icon(Icons.keyboard_arrow_up)),
        IconButton(onPressed: onMoveDown, tooltip: '아래로', icon: const Icon(Icons.keyboard_arrow_down)),
      ]),
    ),
  );
}

class _ImageField extends StatelessWidget {
  const _ImageField({required this.label, required this.imageUrl, required this.busy, required this.onUpload, required this.onClear});
  final String label;
  final String? imageUrl;
  final bool busy;
  final VoidCallback onUpload;
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: Theme.of(context).textTheme.titleSmall), const SizedBox(height: 10),
    if (imageUrl != null) SizedBox(height: 120, width: double.infinity, child: ProductImage(imageUrl: imageUrl, title: label)),
    const SizedBox(height: 10), Wrap(spacing: 8, children: [OutlinedButton.icon(onPressed: busy ? null : onUpload, icon: const Icon(Icons.upload_file), label: Text(busy ? '업로드 중…' : '이미지 올리기')), if (imageUrl != null) TextButton(onPressed: onClear, child: const Text('제거'))]),
  ])));
}
