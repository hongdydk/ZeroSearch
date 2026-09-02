import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/page_form_scaffold.dart';

class SellerScreen extends ConsumerStatefulWidget {
  const SellerScreen({super.key});

  @override
  ConsumerState<SellerScreen> createState() => _SellerScreenState();
}

class _SellerScreenState extends ConsumerState<SellerScreen> {
  final _shopController = TextEditingController();
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _shopController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await ref.read(apiClientProvider).sellerMe();
    } catch (_) {
      // no seller yet
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _apply() async {
    final name = _shopController.text.trim();
    if (name.length < 2) return;
    setState(() => _submitting = true);
    try {
      await ref.read(apiClientProvider).sellerApply(name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('입점 신청이 접수되었습니다.')),
      );
      setState(() {});
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return FutureBuilder(
      future: ref.read(apiClientProvider).sellerMe(),
      builder: (context, snapshot) {
        final seller = snapshot.data;

        if (seller == null) {
          return PageFormScaffold(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('판매자 센터', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                const Text('스토어를 등록하고 상품을 판매해 보세요.'),
                const SizedBox(height: 16),
                TextField(
                  controller: _shopController,
                  decoration: const InputDecoration(labelText: '스토어 이름'),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _submitting ? null : _apply,
                  child: Text(_submitting ? '신청 중…' : '입점 신청'),
                ),
              ],
            ),
          );
        }

        if (seller.status == 'pending') {
          return const Center(child: Text('입점 승인 대기 중입니다.'));
        }

        if (seller.status == 'suspended') {
          return const Center(child: Text('정지된 판매자 계정입니다.'));
        }

        return PageFormScaffold(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(seller.shopName, style: Theme.of(context).textTheme.headlineSmall),
              Text(seller.sellerType == 'platform' ? '공식 스토어' : '입점 스토어'),
              const SizedBox(height: 24),
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('내 상품'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/seller/products'),
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('주문 관리'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/seller/orders'),
              ),
            ],
          ),
        );
      },
    );
  }
}
