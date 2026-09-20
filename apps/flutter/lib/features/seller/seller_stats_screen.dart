import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/portal_workspace.dart';
import 'sales_stats_panel.dart';

class SellerStatsScreen extends ConsumerStatefulWidget {
  const SellerStatsScreen({super.key});

  @override
  ConsumerState<SellerStatsScreen> createState() => _SellerStatsScreenState();
}

class _SellerStatsScreenState extends ConsumerState<SellerStatsScreen> {
  Map<String, dynamic>? _stats;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final stats = await ref.read(apiClientProvider).sellerStats();
      if (mounted) setState(() { _stats = stats; _error = null; });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => PortalWorkspaceScaffold(
    role: PortalWorkspaceRole.seller,
    activePath: '/seller/stats',
    child: PortalPage(
      eyebrow: '판매자 센터',
      title: '통계',
      trailing: IconButton(
        tooltip: '새로고침',
        onPressed: _loading ? null : _load,
        icon: const Icon(Icons.refresh),
      ),
      child: _loading && _stats == null
          ? const Center(child: CircularProgressIndicator())
          : _stats == null
          ? Center(child: Text(_error ?? '통계를 불러오지 못했습니다.'))
          : Column(children: [
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              if (_loading) const SizedBox(height: 12),
              SalesStatsPanel(stats: _stats!),
            ]),
    ),
  );
}
