import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format/price_format.dart';
import '../../core/models/models.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/async_busy.dart';
import '../../shared/widgets/portal_workspace.dart';
import '../../shared/widgets/product_image.dart';
import 'seller_offer_format.dart';

class SellerProductDetailScreen extends ConsumerStatefulWidget {
  const SellerProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  ConsumerState<SellerProductDetailScreen> createState() =>
      _SellerProductDetailScreenState();
}

class _SellerProductDetailScreenState
    extends ConsumerState<SellerProductDetailScreen>
    with AsyncBusyState {
  ProductModel? _product;
  CatalogProductDetailModel? _catalog;
  bool _loading = true;
  bool _hidden = false;
  final _price = TextEditingController();
  final _stock = TextEditingController();
  final _image = TextEditingController();
  final _description = TextEditingController();
  List<String> _detailImages = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _price.dispose();
    _stock.dispose();
    _image.dispose();
    _description.dispose();
    super.dispose();
  }

  void _fill(ProductModel product) {
    _product = product;
    _hidden = sellerOfferIsHidden(product);
    _price.text = product.hasSellablePrice ? product.priceCredits.toString() : '';
    _stock.text = product.hasSellablePrice ? product.stock.toString() : '';
    _image.text = product.imageUrl ?? '';
    _description.text = product.description ?? '';
    _detailImages = [...product.detailImageUrls];
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      ProductModel? found;
      try {
        found = await api.sellerProduct(widget.productId);
      } on ApiException {
        found = null;
      }
      CatalogProductDetailModel? catalog;
      final catalogId = found?.catalogProductId;
      if (catalogId != null && catalogId.isNotEmpty) {
        try {
          catalog = await api.catalogProduct(catalogId);
        } on ApiException {
          catalog = null;
        }
      }
      if (!mounted) return;
      setState(() {
        if (found != null) _fill(found);
        _catalog = catalog;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _pickImage({bool detail = false}) async {
    final key = detail ? 'detailPhoto' : 'photo';
    if (isBusy(key)) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = picked?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    await runBusy(key, () async {
      try {
        final url = await ref.read(apiClientProvider).sellerUploadImage(
          bytes,
          file.name,
        );
        if (!mounted) return;
        setState(() {
          if (detail) {
            _detailImages = [..._detailImages, url];
          } else {
            _image.text = url;
          }
        });
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    });
  }

  void _goList() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/seller/products');
    }
  }

  String? _statusForSave(ProductModel product) {
    if (_hidden && product.status != 'archived') return 'archived';
    if (!_hidden && product.status == 'archived') return 'published';
    return null;
  }

  Future<void> _save() async {
    final product = _product;
    if (product == null || isBusy('save')) return;
    final price = int.tryParse(_price.text.trim());
    final stock = int.tryParse(_stock.text.trim());
    if (price == null || price <= 0 || stock == null || stock < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('가격과 재고를 숫자로 입력하세요.')),
      );
      return;
    }
    await runBusy('save', () async {
      try {
        final updated = await ref.read(apiClientProvider).sellerUpdateProduct(
          product.id,
          priceCredits: price,
          stock: stock,
          imageUrl: _image.text.trim(),
          description: _description.text.trim(),
          detailImageUrls: _detailImages,
          status: _statusForSave(product),
        );
        if (!mounted) return;
        setState(() => _fill(updated));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('오퍼를 저장했습니다.')),
        );
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    });
  }

  Future<void> _confirmDelete() async {
    final product = _product;
    if (product == null || isBusy('delete')) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('오퍼 삭제'),
        content: const Text('오퍼를 영구 삭제합니다. 되돌릴 수 없습니다. 기존 주문과 판매 기록은 유지됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await runBusy('delete', () async {
      try {
        await ref.read(apiClientProvider).sellerDeleteProduct(product.id);
        if (!mounted) return;
        _goList();
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final product = _product;
    return PortalWorkspaceScaffold(
      role: PortalWorkspaceRole.seller,
      activePath: '/seller/products',
      child: PortalPage(
        eyebrow: '판매자 센터',
        title: product?.title ?? '오퍼',
        trailing: TextButton.icon(
          onPressed: _goList,
          icon: const Icon(Icons.arrow_back),
          label: const Text('목록'),
        ),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            : product == null
            ? const Padding(
                padding: EdgeInsets.all(22),
                child: Text('오퍼를 찾을 수 없습니다.'),
              )
            : _buildForm(product),
      ),
    );
  }

  Widget _buildForm(ProductModel product) {
    final option = sellerOfferOptionLabel(product);
    final catalogTitle = _catalog?.title ?? product.title;
    final catalogCategory = _catalog?.category ?? product.category;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PortalSection(
          title: '연결된 카드',
          child: ListTile(
            leading: SizedBox(
              width: 48,
              height: 48,
              child: ProductImage(
                imageUrl: _catalog?.imageUrl ?? product.imageUrl,
                title: catalogTitle,
              ),
            ),
            title: Text(catalogTitle),
            subtitle: Text(
              [
                catalogCategory,
                if (option.isNotEmpty) option,
              ].join(' · '),
            ),
          ),
        ),
        const SizedBox(height: 14),
        PortalSection(
          title: '검수 상태',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PortalStatusBadge(
                  label: sellerOfferReviewLabel(product),
                  attention: product.status != 'published',
                ),
                if (product.status == 'draft') ...[
                  const SizedBox(height: 8),
                  Text(
                    product.hasSellablePrice
                        ? 'MD 검수가 끝나기 전에는 구매자에게 공개되지 않습니다.'
                        : '가격·재고를 붙인 뒤에도 MD 검수가 끝나기 전에는 공개되지 않습니다.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        PortalSection(
          title: '판매 정보',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                TextField(
                  controller: _price,
                  decoration: const InputDecoration(labelText: '가격(원)'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: _stock,
                  decoration: const InputDecoration(labelText: '재고'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: _image,
                  decoration: const InputDecoration(
                    labelText: '사진 URL',
                    hintText: '파일을 올리거나 주소를 붙여 넣습니다',
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: isBusy('photo') ? null : _pickImage,
                    icon: isBusy('photo')
                        ? busyProgress()
                        : const Icon(Icons.photo_outlined),
                    label: Text(isBusy('photo') ? '올리는 중…' : '사진 파일 올리기'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _description,
                  minLines: 3,
                  maxLines: 7,
                  maxLength: 3000,
                  decoration: const InputDecoration(
                    labelText: '상품 상세 설명',
                    hintText: '구매자 상품 상세 화면에 표시할 정보를 입력하세요',
                  ),
                ),
                const SizedBox(height: 8),
                Text('상세 이미지', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text('상품 성분, 규격, 구성처럼 구매 판단에 필요한 이미지를 최대 12장 올릴 수 있습니다.', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                if (_detailImages.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var index = 0; index < _detailImages.length; index++)
                        SizedBox(
                          width: 112,
                          child: Stack(children: [
                            AspectRatio(aspectRatio: 1, child: ClipRRect(borderRadius: BorderRadius.circular(8), child: ProductImage(imageUrl: _detailImages[index], title: '상세 이미지 ${index + 1}'))),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: Material(
                                color: Colors.black54,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () => setState(() => _detailImages = [..._detailImages]..removeAt(index)),
                                  child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close, size: 16, color: Colors.white)),
                                ),
                              ),
                            ),
                          ]),
                        ),
                    ],
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _detailImages.length >= 12 || isBusy('detailPhoto') ? null : () => _pickImage(detail: true),
                    icon: isBusy('detailPhoto') ? busyProgress() : const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(isBusy('detailPhoto') ? '올리는 중…' : '상세 이미지 추가'),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('구매자에게 숨김'),
                  value: _hidden,
                  onChanged: (value) => setState(() => _hidden = value),
                ),
                if (option.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '옵션 $option · 현재 ${formatWon(product.priceCredits)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: isBusy('save') ? null : _save,
              child: isBusy('save') ? busyProgress() : const Text('저장'),
            ),
            OutlinedButton(
              onPressed: isBusy('delete') ? null : _confirmDelete,
              child: isBusy('delete') ? busyProgress() : const Text('삭제'),
            ),
          ],
        ),
      ],
    );
  }
}
