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
import 'seller_visibility_row.dart';

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
  bool _step2 = false;
  CatalogProductModel? _catalog;
  ProductModel? _createdProduct;
  IntakeDraftModel? _createdDraft;

  final _search = TextEditingController();
  final _manufacturer = TextEditingController();
  final _title = TextEditingController();
  final _category = TextEditingController();
  final _flavor = TextEditingController();
  final _amount = TextEditingController();
  final _pack = TextEditingController(text: '1');
  final _imageUrl = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController();

  List<CatalogProductModel> _hits = [];
  bool _searching = false;
  bool _customUnit = false;
  String? _selectedOption;
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
    _price.dispose();
    _stock.dispose();
    super.dispose();
  }

  List<String> get _volumeOptions => _catalog?.volumeOptions ?? const [];

  void _applyOption(String option) {
    final parsed = parseSellerUnitLabel(option);
    setState(() {
      _selectedOption = option;
      _customUnit = parsed == null;
      if (parsed != null) {
        _amount.text = parsed.amount == parsed.amount.roundToDouble()
            ? parsed.amount.round().toString()
            : parsed.amount.toString();
        _unit = parsed.unit;
        _pack.text = parsed.packCount.toString();
      }
    });
  }

  Future<void> _searchCatalog() async {
    final q = _search.text.trim();
    if (q.isEmpty || _searching) return;
    setState(() => _searching = true);
    try {
      final items = await ref.read(apiClientProvider).sellerSearchCatalog(q: q);
      if (!mounted) return;
      setState(() => _hits = items);
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

  ({double? amount, String? unit, int pack, String? option})? _readUnits() {
    if (!_customUnit && _selectedOption != null && _selectedOption!.isNotEmpty) {
      final parsed = parseSellerUnitLabel(_selectedOption);
      return (
        amount: parsed?.amount,
        unit: parsed?.unit,
        pack: parsed?.packCount ?? 1,
        option: _selectedOption,
      );
    }
    final amount = double.tryParse(_amount.text.trim());
    final pack = int.tryParse(_pack.text.trim()) ?? 1;
    if (amount == null || amount <= 0 || pack < 1) return null;
    return (amount: amount, unit: _unit, pack: pack, option: null);
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
    final units = _readUnits();
    if (units == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('용량을 고르거나 들이·단위·묶음 수를 입력하세요.')),
      );
      return;
    }
    await runBusy('create', () async {
      try {
        final api = ref.read(apiClientProvider);
        final image = _imageUrl.text.trim();
        if (_missing) {
          final draft = await api.sellerCreateCardDraft(
            manufacturer: _manufacturer.text.trim(),
            title: _title.text.trim(),
            category: _category.text.trim(),
            optionLabel: units.option,
            unitAmount: units.amount,
            unit: units.unit,
            packCount: units.pack,
            flavor: _flavor.text.trim().isEmpty ? null : _flavor.text.trim(),
            imageUrl: image.isEmpty ? null : image,
          );
          if (!mounted) return;
          setState(() {
            _createdDraft = draft;
            _public = draft.isPublic;
            _step2 = false;
          });
        } else {
          final catalog = _catalog!;
          final created = await api.sellerCreateProduct(
            title: catalog.title,
            category: catalog.category,
            catalogProductId: catalog.id,
            optionLabel: units.option,
            unitAmount: units.amount,
            unit: units.unit,
            packCount: units.pack,
            flavor: _flavor.text.trim().isEmpty ? null : _flavor.text.trim(),
            imageUrl: image.isEmpty ? null : image,
          );
          if (!mounted) return;
          setState(() {
            _createdProduct = created;
            _step2 = false;
          });
        }
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    });
  }

  Future<void> _submitPrice() async {
    if (isBusy('price')) return;
    final price = int.tryParse(_price.text.trim());
    final stock = int.tryParse(_stock.text.trim());
    if (price == null || price <= 0 || stock == null || stock < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('가격과 재고를 숫자로 입력하세요.')),
      );
      return;
    }
    await runBusy('price', () async {
      try {
        final api = ref.read(apiClientProvider);
        if (_createdProduct != null) {
          await api.sellerUpdateProduct(
            _createdProduct!.id,
            priceCredits: price,
            stock: stock,
          );
        } else if (_createdDraft != null) {
          await api.sellerUpdateCardDraft(
            _createdDraft!.id,
            priceCredits: price,
            stock: stock,
            visibility: _public ? 'public' : 'hidden',
          );
        }
        if (!mounted) return;
        context.go('/seller/products');
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    });
  }

  void _goList() => context.go('/seller/products');

  void _continuePrice() {
    final product = _createdProduct;
    if (product != null) {
      context.go('/seller/products/${product.id}');
      return;
    }
    setState(() => _step2 = true);
  }

  @override
  Widget build(BuildContext context) {
    final created = _createdProduct != null || _createdDraft != null;
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
        Text(
          '1단계: 품목과 용량만 만듭니다. 가격·재고는 다음에서 붙일 수 있습니다. MD 검수 전에는 공개되지 않습니다.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
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
              _selectedOption = null;
            });
          },
        ),
        const SizedBox(height: 14),
        if (_missing) _buildMissingCard() else _buildCatalogCard(),
        const SizedBox(height: 14),
        PortalSection(title: '용량·묶음', child: _buildUnits()),
        const SizedBox(height: 14),
        PortalSection(
          title: '맛·사진 (선택)',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                TextField(
                  controller: _flavor,
                  decoration: const InputDecoration(labelText: '맛 (선택)'),
                ),
                TextField(
                  controller: _imageUrl,
                  decoration: const InputDecoration(
                    labelText: '사진 URL (선택)',
                    hintText: '파일을 올리거나 주소를 붙여 넣습니다',
                  ),
                ),
                const SizedBox(height: 8),
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
                if (_imageUrl.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 96,
                    child: ProductImage(
                      imageUrl: _imageUrl.text.trim(),
                      title: '미리보기',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: isBusy('create') ? null : _submitIdentity,
          child: isBusy('create') ? busyProgress() : const Text('오퍼 초안 만들기'),
        ),
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
                    _selectedOption = null;
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
                    if (item.volumeOptions.isNotEmpty) {
                      _applyOption(item.volumeOptions.first);
                    } else {
                      _customUnit = true;
                    }
                  }),
                ),
            ],
          ],
        ),
      ),
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
            TextField(
              controller: _manufacturer,
              decoration: const InputDecoration(labelText: '회사'),
            ),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: '품목명'),
            ),
            TextField(
              controller: _category,
              decoration: const InputDecoration(
                labelText: '종류 (짐작)',
                hintText: '생수, 떡갈비',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnits() {
    final preview = _previewLabel();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_volumeOptions.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in _volumeOptions)
                  ChoiceChip(
                    label: Text(option),
                    selected: !_customUnit && _selectedOption == option,
                    onSelected: (_) => _applyOption(option),
                  ),
                ChoiceChip(
                  label: const Text('직접 입력'),
                  selected: _customUnit || _volumeOptions.isEmpty,
                  onSelected: (_) => setState(() {
                    _customUnit = true;
                    _selectedOption = null;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (_customUnit || _volumeOptions.isEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    decoration: const InputDecoration(labelText: '들이'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: sellerOfferUnits.contains(_unit) ? _unit : 'ml',
                  items: [
                    for (final unit in sellerOfferUnits)
                      DropdownMenuItem(value: unit, child: Text(unit)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _unit = value);
                  },
                ),
              ],
            ),
            TextField(
              controller: _pack,
              decoration: const InputDecoration(
                labelText: '들이 개수',
                hintText: '낱개는 1',
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
          ],
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('표시 $preview', style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  String _previewLabel() {
    final units = _readUnits();
    if (units == null) return '';
    if (units.option != null && units.option!.isNotEmpty) return units.option!;
    if (units.amount == null || units.unit == null) return '';
    return formatSellerUnitLabel(
      amount: units.amount!,
      unit: units.unit!,
      packCount: units.pack,
    );
  }

  Widget _buildCreated() {
    final title = _createdProduct?.title ?? _createdDraft?.cardTitle ?? '오퍼';
    final option = _createdProduct != null
        ? sellerOfferOptionLabel(_createdProduct!)
        : (_createdDraft?.optionLabel ?? '');
    if (_step2 && _createdDraft != null) {
      return PortalSection(
        title: '2단계 가격·재고',
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              Text('$title · $option', style: Theme.of(context).textTheme.bodySmall),
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
              SellerVisibilityRow(
                isPublic: _public,
                onChanged: (value) => setState(() => _public = value),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: isBusy('price') ? null : _submitPrice,
                child: isBusy('price') ? busyProgress() : const Text('가격·재고 저장'),
              ),
            ],
          ),
        ),
      );
    }
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
