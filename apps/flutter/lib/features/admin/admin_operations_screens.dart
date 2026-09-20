import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/portal_workspace.dart';

class AdminAlertsScreen extends ConsumerStatefulWidget {
  const AdminAlertsScreen({super.key});
  @override
  ConsumerState<AdminAlertsScreen> createState() => _AdminAlertsScreenState();
}

class _AdminAlertsScreenState extends ConsumerState<AdminAlertsScreen> {
  int _pendingSellers = 0;
  int _pendingDrafts = 0;
  bool _loading = true;
  String? _error;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      final values = await Future.wait([api.adminSellers(status: 'pending'), api.adminCatalogDrafts()]);
      if (mounted) setState(() { _pendingSellers = (values[0] as List).length; _pendingDrafts = (values[1] as List<IntakeDraftModel>).where((item) => item.status == 'pending').length; _error = null; });
    } on ApiException catch (e) { if (mounted) setState(() => _error = e.message); }
    finally { if (mounted) setState(() => _loading = false); }
  }
  @override
  Widget build(BuildContext context) => PortalWorkspaceScaffold(
    role: PortalWorkspaceRole.admin, activePath: '/admin/alerts',
    child: PortalPage(eyebrow: '관리자', title: '알림', trailing: IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)), child: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? Center(child: Text(_error!)) : Column(children: [
      Card(child: ListTile(leading: const Icon(Icons.storefront_outlined), title: const Text('입점 신청 대기'), subtitle: Text('$_pendingSellers건의 판매자 신청이 있습니다.'), trailing: const Icon(Icons.chevron_right), onTap: () => context.go('/admin/sellers'))),
      Card(child: ListTile(leading: const Icon(Icons.inventory_2_outlined), title: const Text('카탈로그 제안 대기'), subtitle: Text('$_pendingDrafts건의 카드·오퍼 제안이 있습니다.'), trailing: const Icon(Icons.chevron_right), onTap: () => context.go('/admin/catalog'))),
    ])),
  );
}

class AdminAuditScreen extends ConsumerStatefulWidget {
  const AdminAuditScreen({super.key});
  @override
  ConsumerState<AdminAuditScreen> createState() => _AdminAuditScreenState();
}

class _AdminAuditScreenState extends ConsumerState<AdminAuditScreen> {
  List<SellerModerationEventModel> _events = const [];
  bool _loading = true;
  String? _error;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async { try { final events = await ref.read(apiClientProvider).adminAuditEvents(); if (mounted) setState(() { _events = events; _error = null; }); } on ApiException catch (e) { if (mounted) setState(() => _error = e.message); } finally { if (mounted) setState(() => _loading = false); } }
  @override
  Widget build(BuildContext context) => PortalWorkspaceScaffold(
    role: PortalWorkspaceRole.admin, activePath: '/admin/audit',
    child: PortalPage(eyebrow: '관리자', title: '감사 로그', trailing: IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)), child: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? Center(child: Text(_error!)) : PortalSection(title: '판매자 관리 기록', child: _events.isEmpty ? const Padding(padding: EdgeInsets.all(16), child: Text('기록이 없습니다.')) : Column(children: [for (final event in _events) ListTile(leading: const Icon(Icons.manage_history), title: Text('${event.shopName ?? '판매자'} · ${event.actionLabel}'), subtitle: Text('${event.reason}\n${event.adminEmail ?? ''}'), isThreeLine: event.adminEmail != null)]))),
  );
}
