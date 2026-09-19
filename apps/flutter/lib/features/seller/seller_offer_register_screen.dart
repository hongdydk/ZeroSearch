import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/async_busy.dart';
import '../../shared/widgets/portal_workspace.dart';
import '../../shared/widgets/product_image.dart';
import 'seller_offer_format.dart';

class SellerOfferRegisterScreen extends ConsumerStatefulWidget {
  const SellerOfferRegisterScreen({super.key, this.missingItem = false});

  final bool missingItem;

  @override
  ConsumerState<SellerOfferRegisterScreen> createState() =>
      _SellerOfferRegisterScreenState();
}

class _SellerOfferRegisterScreenState
    extends ConsumerState<SellerOfferRegisterScreen>
    with AsyncBusyState {
  late bool _missing;
  CatalogProductModel? _catalog;
  ProductModel? _createdProduct;

  final _search = TextEditingController();
  final _manufacturer = TextEditingController();
  final _title = TextEditingController();
  final _category = TextEditingController();
  final _flavor = TextEditingController();
  final _amount = TextEditingController();
  final _pack = TextEditingController(text: '1');
  final _imageUrl = TextEditingController();

  List<CatalogProductModel> _hits = [];
  bool _searching = false;
  bool _didSearch = false;
  int _catalogTotal = 0;
  String? _selectedVariantId;
  bool _proposingVariant = false;
  final List<Map<String, dynamic>> _proposedVariants = [];
  String _unit = 'ml';
  bool _public = true;

  @override
  void initState() {
    super.initState();
    _missing = widget.missingItem;
  }

  @override
  void dispose() {
    _search.dispose();
    _manufacturer.dispose();
    _title.dispose();
    _category.dispose();
    _flavor.dispose();
    _amount.dispose();
    _pack.dispose();
    _imageUrl.dispose();
    super.dispose();
  }

  void _addProposedVariant() {
    final amount = double.tryParse(_amount.text.trim());
    final pack = int.tryParse(_pack.text.trim());
    final name = _flavor.text.trim().isEmpty ? '기본' : _flavor.text.trim();
    if (amount == null || amount <= 0 || pack == null || pack < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('옵션의 용량과 묶음 수를 확인하세요.')),
      );
      return;
    }
    final option = <String, dynamic>{
      'name': name,
      'unitAmount': amount,
      'unit': _unit,
      'packCount': pack,
      if (_imageUrl.text.trim().isNotEmpty) 'imageUrl': _imageUrl.text.trim(),
    };
    if (_proposedVariants.any((existing) =>
        existing['name'] == name && existing['unitAmount'] == amount &&
        existing['unit'] == _unit && existing['packCount'] == pack)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('같은 옵션이 이미 목록에 있습니다.')),
      );
      return;
    }
    setState(() {
      _proposedVariants.add(option);
      _flavor.clear();
      _amount.clear();
      _pack.text = '1';
      _imageUrl.clear();
    });
  }

  Future<void> _searchCatalog({bool nextPage = false}) async {
    final q = _search.text.trim();
    if (q.isEmpty || _searching) return;
    setState(() => _searching = true);
    try {
      final offset = nextPage ? _hits.length : 0;
      final page = await ref.read(apiClientProvider).sellerSearchCatalog(
        q: q,
        offset: offset,
        limit: 30,
      );
      if (!mounted) return;
      setState(() {
        _didSearch = true;
        _catalogTotal = page.total;
        _hits = nextPage ? [..._hits, ...page.items] : page.items;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _pickImage() async {
    if (isBusy('photo')) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = picked?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    await runBusy('photo', () async {
      try {
        final url = await ref.read(apiClientProvider).sellerUploadImage(
          bytes,
          file.name,
        );
        if (!mounted) return;
        setState(() => _imageUrl.text = url);
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    });
  }

  Future<void> _submitIdentity() async {
    if (isBusy('create')) return;
    if (_missing) {
      if (_manufacturer.text.trim().isEmpty ||
          _title.text.trim().isEmpty ||
          _category.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('회사·품목명·종류를 적어 주세요.')),
        );
        return;
      }
    } else if (_catalog == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('카탈로그 카드를 고르세요.')),
      );
      return;
    }
    if ((_missing || _proposingVariant) && _proposedVariants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('상품 옵션을 하나 이상 추가하세요.')),
      );
      return;
    }
    if (!_missing && !_proposingVariant && _selectedVariantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('상품 옵션을 고르세요.')),
      );
      return;
    }
    await runBusy('create', () async {
      try {
        final api = ref.read(apiClientProvider);
        final image = _imageUrl.text.trim();
        if (_missing || _proposingVariant) {
          await api.sellerCreateCardDraft(
            manufacturer: _missing ? _manufacturer.text.trim() : _catalog!.manufacturer,
            title: _missing ? _title.text.trim() : _catalog!.title,
            category: _missing ? _category.text.trim() : _catalog!.category,
            catalogProductId: _missing ? null : _catalog!.id,
            variants: _proposedVariants,
            imageUrl: _proposedVariants.first['imageUrl'] as String?,
            priceCredits: null,
            stock: null,
            visibility: _public ? 'public' : 'hidden',
          );
          if (!mounted) return;
          _goList();
          return;
        } else {
          final catalog = _catalog!;
          final created = await api.sellerCreateProduct(
            title: catalog.title,
            category: catalog.category,
            catalogProductId: catalog.id,
            variantId: _selectedVariantId,
            imageUrl: image.isEmpty ? null : image,
          );
          if (!mounted) return;
          setState(() {
            _createdProduct = created;
          });
        }
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

  void _openMissingDraft() {
    setState(() {
      _missing = true;
      _catalog = null;
      _selectedVariantId = null;
      _proposingVariant = false;
    });
  }

  void _continuePrice() {
    final product = _createdProduct;
    if (product == null) return;
    context.go('/seller/products/${product.id}');
  }

  @override
  Widget build(BuildContext context) {
    final created = _createdProduct != null;
    return PortalWorkspaceScaffold(
      role: PortalWorkspaceRole.seller,
      activePath: '/seller/products',
      child: PortalPage(
        eyebrow: '판매자 센터',
        title: created ? '오퍼 초안' : '오퍼 등록',
        trailing: TextButton.icon(
          onPressed: _goList,
          icon: const Icon(Icons.arrow_back),
          label: const Text('목록'),
        ),
        child: created ? _buildCreated() : _buildIdentity(),
      ),
    );
  }

  Widget _buildIdentity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_missing) ...[
          Text(
            '1단계: 품목과 용량만 만듭니다. 가격·재고는 다음에서 붙일 수 있습니다. MD 검수 전에는 공개되지 않습니다.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
        ],
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('있는 품목')),
            ButtonSegment(value: true, label: Text('없는 품목')),
          ],
          selected: {_missing},
          onSelectionChanged: (value) {
            setState(() {
              _missing = value.first;
              _catalog = null;
              _selectedVariantId = null;
              _proposingVariant = false;
              _proposedVariants.clear();
            });
          },
        ),
        const SizedBox(height: 14),
        if (_missing) _buildMissingCard() else ...[
          _buildCatalogCard(),
          const SizedBox(height: 14),
          PortalSection(title: '상품 옵션', child: _buildVariantSelector()),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: isBusy('create') ? null : _submitIdentity,
            child: isBusy('create') ? busyProgress() : Text(_proposingVariant ? '옵션 제안' : '오퍼 초안 만들기'),
          ),
        ],
      ],
    );
  }

  Widget _buildCatalogCard() {
    return PortalSection(
      title: '카탈로그 카드',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          children: [
            if (_catalog != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: SizedBox(
                  width: 48,
                  height: 48,
                  child: ProductImage(
                    imageUrl: _catalog!.imageUrl,
                    title: _catalog!.cardTitle,
                  ),
                ),
                title: Text(_catalog!.cardTitle),
                subtitle: Text(_catalog!.category),
                trailing: TextButton(
                  onPressed: () => setState(() {
                    _catalog = null;
                    _selectedVariantId = null;
                    _proposingVariant = false;
                    _proposedVariants.clear();
                  }),
                  child: const Text('다시 고르기'),
                ),
              )
            else ...[
              TextField(
                controller: _search,
                decoration: const InputDecoration(
                  labelText: '품목·제조사·분류',
                  hintText: '김치, 만두, 풀무원',
                ),
                onSubmitted: _searching ? null : (_) => _searchCatalog(),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _searching ? null : _searchCatalog,
                  child: Text(_searching ? '검색 중…' : '검색'),
                ),
              ),
              if (_searching) const LinearProgressIndicator(minHeight: 2),
              if (_didSearch && !_searching && _hits.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('검색 결과가 없습니다. 카탈로그에 없으면 없는 품목 초안으로 요청하세요.'),
                      TextButton(
                        onPressed: _openMissingDraft,
                        child: const Text('없는 품목 초안 만들기'),
                      ),
                    ],
                  ),
                ),
              for (final item in _hits)
                ListTile(
                  title: Text(item.cardTitle),
                  subtitle: Text(
                    [
                      item.category,
                      if (item.volumeOptions.isNotEmpty)
                        item.volumeOptions.join(', '),
                    ].join(' · '),
                  ),
                  onTap: () => setState(() {
                    _catalog = item;
                    _hits = [];
                    _didSearch = false;
                    _selectedVariantId = item.variants.isNotEmpty ? item.variants.first.id : null;
                    _proposingVariant = item.variants.isEmpty;
                  }),
                ),
              if (_hits.isNotEmpty && _hits.length < _catalogTotal)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _searching ? null : () => _searchCatalog(nextPage: true),
                    child: const Text('다음 페이지'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVariantSelector() {
    final catalog = _catalog;
    if (catalog == null) return const Padding(
      padding: EdgeInsets.all(16), child: Text('먼저 카탈로그 카드를 고르세요.'),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final variant in catalog.variants)
                ChoiceChip(
                  label: Text(variant.displayLabel),
                  selected: !_proposingVariant && _selectedVariantId == variant.id,
                  onSelected: (_) => setState(() {
                    _selectedVariantId = variant.id;
                    _proposingVariant = false;
                  }),
                ),
              ChoiceChip(
                label: const Text('없는 옵션 제안'),
                selected: _proposingVariant,
                onSelected: (_) => setState(() {
                  _selectedVariantId = null;
                  _proposingVariant = true;
                }),
              ),
            ],
          ),
          if (_proposingVariant) ...[
            const SizedBox(height: 12),
            _buildVariantProposal(),
          ],
        ],
      ),
    );
  }

  Widget _buildVariantProposal() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _flavor,
          decoration: const InputDecoration(labelText: '옵션명', hintText: '오리지널, 매운맛, 제로 등'),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(
            controller: _amount,
            decoration: const InputDecoration(labelText: '들이 용량'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          )),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: sellerOfferUnits.contains(_unit) ? _unit : 'ml',
            items: [for (final unit in sellerOfferUnits) DropdownMenuItem(value: unit, child: Text(unit))],
            onChanged: (value) { if (value != null) setState(() => _unit = value); },
          ),
        ]),
        TextField(
          controller: _pack,
          decoration: const InputDecoration(labelText: '들이 개수', hintText: '낱개는 1'),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _imageUrl,
          decoration: const InputDecoration(labelText: '옵션 사진 URL (선택)'),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: isBusy('photo') ? null : _pickImage,
            icon: const Icon(Icons.photo_outlined),
            label: const Text('사진 파일 올리기'),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _addProposedVariant,
            icon: const Icon(Icons.add),
            label: const Text('옵션 추가'),
          ),
        ),
        for (var index = 0; index < _proposedVariants.length; index++)
          ListTile(
            title: Text('${_proposedVariants[index]['name']} · ${formatSellerUnitLabel(amount: _proposedVariants[index]['unitAmount'] as double, unit: _proposedVariants[index]['unit'] as String, packCount: _proposedVariants[index]['packCount'] as int)}'),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              tooltip: '옵션 제거',
              onPressed: () => setState(() => _proposedVariants.removeAt(index)),
            ),
          ),
      ],
    );
  }

  Widget _buildMissingCard() {
    return PortalSection(
      title: '없는 품목 카드 초안',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          children: [
            Text(
              '공개 목록에 바로 올라가지 않습니다. MD가 기존 카드에 붙이거나 새 카드로 승격합니다.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _manufacturer,
              decoration: const InputDecoration(labelText: '회사'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: '품목명'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _category,
              decoration: const InputDecoration(
                labelText: '종류 (짐작)',
                hintText: '생수, 떡갈비',
              ),
            ),
            const SizedBox(height: 8),
            _buildVariantProposal(),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: isBusy('create') ? null : _goList,
                  child: const Text('취소'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: isBusy('create') ? null : _submitIdentity,
                  child: isBusy('create') ? busyProgress() : const Text('초안 제출'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreated() {
    final product = _createdProduct!;
    final title = product.title;
    final option = sellerOfferOptionLabel(product);
    return PortalSection(
      title: '초안이 만들어졌습니다',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$title · $option'),
            const SizedBox(height: 8),
            const Text('아직 가격·재고는 없습니다. MD 검수 전에는 구매자에게 공개되지 않습니다.'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _continuePrice,
                  child: const Text('이어서 가격·재고'),
                ),
                OutlinedButton(
                  onPressed: _goList,
                  child: const Text('나중에'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
