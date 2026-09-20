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
      final seller = await ref.read(apiClientProvider).sellerMe();
      if (seller == null || !mounted) return;
      setState(() {
        _description.text = seller.storeDescription ?? '';
        _logoUrl = seller.storeLogoUrl;
        _bannerUrl = seller.storeBannerUrl;
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

  @override
  Widget build(BuildContext context) {
    return PortalWorkspaceScaffold(
      role: PortalWorkspaceRole.seller,
      activePath: '/seller/storefront',
      child: PortalPage(
        eyebrow: '공개 판매자 사이트',
        title: '내 판매자 사이트 관리',
        trailing: TextButton.icon(onPressed: () => context.go('/seller/products/new'), icon: const Icon(Icons.add), label: const Text('상품 등록')),
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
          ]),
        ),
      ),
    );
  }
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
