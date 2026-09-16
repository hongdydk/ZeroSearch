import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/fulfillment/fulfillment_labels.dart';
import '../../core/layout/ui_platform.dart';
import '../../core/models/models.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/async_busy.dart';
import '../../shared/widgets/page_form_scaffold.dart';
import '../../shared/widgets/portal_workspace.dart';

enum AdminSection { home, stats, sellers, orders, catalog, users, tools }

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key, this.section});

  final AdminSection? section;

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> with AsyncBusyState {
  Map<String, dynamic>? _stats;

  List<dynamic> _users = [];

  List<AdminSellerModel> _pendingSellers = [];

  List<SellerOrderItemModel> _orderItems = [];

  String _resetMode = 'seed';

  String? _message;

  Timer? _pollTimer;

  bool _importProcessing = false;

  double _importSend = 0;

  String? _importFileName;

  String? _importResult;

  String _userQuery = '';
  final _userSearchCtrl = TextEditingController();
  final Map<String, bool> _adminDraft = {};

  bool get _resetting => isBusy('reset');

  bool get _pageLocked => isBusy('reset') || isBusy('import');

  @override
  void initState() {
    super.initState();

    _load();

    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _loadOrders(silent: true),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _userSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);

    final stats = await api.adminStats();

    final users = await api.adminUsers(q: _userQuery);

    List<AdminSellerModel> pending = [];

    try {
      pending = await api.adminSellers(status: 'pending');
    } catch (_) {}

    await _loadOrders(silent: true);

    setState(() {
      _stats = stats;

      _users = users['items'] as List<dynamic>? ?? [];
      _adminDraft
        ..clear()
        ..addEntries(
          _users.map(
            (user) => MapEntry(
              user['id'] as String,
              user['isAdmin'] == true,
            ),
          ),
        );
      _pendingSellers = pending;
    });
  }

  Future<void> _loadOrders({bool silent = false}) async {
    try {
      final items = await ref.read(apiClientProvider).adminOrders();

      if (mounted) setState(() => _orderItems = items);
    } on ApiException catch (_) {
      if (!silent && mounted) {
        setState(() => _orderItems = []);
      }
    }
  }

  Future<void> _advanceOrder(SellerOrderItemModel item) async {
    final next = nextFulfillmentStatus(item.fulfillmentStatus);
    if (next == null) return;
    await runBusy('order:${item.id}', () async {
      try {
        await ref.read(apiClientProvider).adminUpdateOrderStatus(item.id, next);
        await _loadOrders(silent: true);
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    });
  }

  String _resetBusyLabel() {
    return _resetMode == 'seed' ? '시드 확인 중…' : '데이터를 지우는 중 — 창을 닫지 마세요.';
  }

  Future<void> _reset() async {
    if (_pageLocked) return;
    final wipe = _resetMode != 'seed';
    if (wipe) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('초기화할까요?'),
          content: Text(
            _resetMode == 'truncate_all'
                ? '계정·주문·가게·카탈로그를 모두 지웁니다. 몇 분 걸릴 수 있습니다.'
                : '주문·가게·카탈로그를 지웁니다. 계정은 남습니다. 몇 분 걸릴 수 있습니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('실행'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    await runBusy('reset', () async {
      setState(() => _message = _resetBusyLabel());
      try {
        final res = await ref.read(apiClientProvider).adminDbReset(_resetMode);
        final text = res['message'] as String? ?? '완료했습니다.';
        if (!mounted) return;
        setState(() => _message = text);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(text)));
        await _load();
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() => _message = e.message);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      } catch (e) {
        if (!mounted) return;
        const text = '초기화에 실패했습니다.';
        setState(() => _message = text);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(text)));
      }
    });
  }

  Future<void> _approveSeller(String sellerId) async {
    await runBusy('approve:$sellerId', () async {
      try {
        await ref.read(apiClientProvider).adminApproveSeller(sellerId);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('입점을 승인했습니다.')));
        await _load();
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    });
  }

  Future<void> _saveUserRole(String userId) async {
    final isAdmin = _adminDraft[userId] ?? false;
    await runBusy('user:$userId', () async {
      try {
        await ref
            .read(apiClientProvider)
            .adminUpdateUser(userId, isAdmin: isAdmin);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('역할을 저장했습니다.')));
        await _load();
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    });
  }

  Future<void> _deleteUser(String userId, String email) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('사용자를 삭제할까요?'),
        content: Text('$email 계정을 삭제합니다. 주문·가게 데이터도 함께 지워질 수 있습니다.'),
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
    if (ok != true) return;
    await runBusy('user:$userId', () async {
      try {
        await ref.read(apiClientProvider).adminDeleteUser(userId);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('사용자를 삭제했습니다.')));
        await _load();
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    });
  }

  Future<void> _importCatalog() async {
    if (_pageLocked) return;

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,

      allowedExtensions: const ['csv'],

      withData: true,
    );

    final file = picked?.files.single;

    final bytes = file?.bytes;

    if (bytes == null || file == null) return;

    await runBusy('import', () async {
      setState(() {
        _importProcessing = false;
        _importSend = 0;
        _importFileName = file.name;
        _importResult = null;
        _message = null;
      });
      try {
        final result = await ref
            .read(apiClientProvider)
            .adminImportCatalog(
              bytes,
              file.name,
              onSendProgress: (fraction) {
                if (!mounted) return;
                setState(() => _importSend = fraction);
              },
              onProcessing: () {
                if (!mounted) return;
                setState(() {
                  _importSend = 1;
                  _importProcessing = true;
                });
              },
            );
        if (!mounted) return;
        final text = '반영 ${result.upserted}건 (원본 ${result.sourceRows}줄)';
        setState(() => _importResult = text);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(text)));
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() => _importResult = e.message);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    });
  }

  Widget _buildWorkspace(AdminSection section) {
    return PortalWorkspaceScaffold(
      role: PortalWorkspaceRole.admin,
      activePath: _sectionPath(section),
      child: PortalPage(
        eyebrow: '관리자',
        title: _sectionTitle(section),
        child: switch (section) {
          AdminSection.home => _buildAdminHome(),
          AdminSection.stats => _buildStats(),
          AdminSection.sellers => _buildSellers(),
          AdminSection.orders => _buildOrders(),
          AdminSection.catalog => _buildCatalog(),
          AdminSection.users => _buildUsers(),
          AdminSection.tools => _buildTools(),
        },
      ),
    );
  }

  String _sectionPath(AdminSection section) => switch (section) {
    AdminSection.home => '/admin',
    AdminSection.stats => '/admin/stats',
    AdminSection.sellers => '/admin/sellers',
    AdminSection.orders => '/admin/orders',
    AdminSection.catalog => '/admin/catalog',
    AdminSection.users => '/admin/users',
    AdminSection.tools => '/admin/tools',
  };

  String _sectionTitle(AdminSection section) => switch (section) {
    AdminSection.home => '운영 홈',
    AdminSection.stats => '통계',
    AdminSection.sellers => '입점 관리',
    AdminSection.orders => '주문 관리',
    AdminSection.catalog => '카탈로그',
    AdminSection.users => '사용자',
    AdminSection.tools => '시스템 도구',
  };

  Widget _buildAdminHome() {
    final stats = _stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stats == null)
          const Center(child: CircularProgressIndicator())
        else
          PortalMetricGrid(
            children: [
              PortalMetricCard(
                label: '판매 품목 수',
                value: '${stats['soldItemCount'] ?? 0}',
                hint: '팔린 품목',
              ),
              PortalMetricCard(
                label: '수량',
                value: '${stats['soldQtySum'] ?? 0}',
                hint: '판매 수량 합',
              ),
              PortalMetricCard(
                label: '총액',
                value: '${stats['soldAmountSum'] ?? 0}',
                hint: '원',
              ),
              PortalMetricCard(
                label: '승인 대기',
                value: '${stats['pendingSellerCount']}',
                hint: '검토 필요',
                attention: (stats['pendingSellerCount'] as int? ?? 0) > 0,
              ),
            ],
          ),
        const SizedBox(height: 18),
        PortalSection(
          title: '입점 승인 대기',
          child: _pendingSellers.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('대기 중인 입점 신청이 없습니다.'),
                )
              : Column(
                  children: [
                    for (final seller in _pendingSellers.take(4))
                      ListTile(
                        title: Text(seller.shopName),
                        subtitle: Text(seller.userEmail),
                        trailing: FilledButton(
                          onPressed:
                              _pageLocked || isBusy('approve:${seller.id}')
                              ? null
                              : () => _approveSeller(seller.id),
                          child: isBusy('approve:${seller.id}')
                              ? busyProgress()
                              : const Text('승인'),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildStats() {
    final stats = _stats;
    if (stats == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PortalMetricGrid(
          children: [
            PortalMetricCard(label: '사용자', value: '${stats['userCount']}'),
            PortalMetricCard(label: '오퍼', value: '${stats['productCount']}'),
            PortalMetricCard(label: '주문', value: '${stats['orderCount']}'),
            PortalMetricCard(label: '판매자', value: '${stats['sellerCount']}'),
          ],
        ),
        const SizedBox(height: 18),
        PortalSection(
          title: '현재 제공되는 통계',
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const Expanded(
                  child: Text('기간별 추이와 카탈로그 건강 통계는 아직 API가 없어 준비 중입니다.'),
                ),
                PortalStatusBadge(
                  label: '승인 대기 ${stats['pendingSellerCount']}',
                  attention: (stats['pendingSellerCount'] as int? ?? 0) > 0,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSellers() {
    return PortalSection(
      title: '승인 대기 판매자',
      child: _pendingSellers.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(22),
              child: Text('대기 중인 입점 신청이 없습니다.'),
            )
          : Column(
              children: [
                for (final seller in _pendingSellers)
                  ListTile(
                    leading: const Icon(Icons.storefront_outlined),
                    title: Text(seller.shopName),
                    subtitle: Text(
                      '${seller.userEmail} · ${seller.sellerType}',
                    ),
                    trailing: FilledButton(
                      onPressed: _pageLocked || isBusy('approve:${seller.id}')
                          ? null
                          : () => _approveSeller(seller.id),
                      child: isBusy('approve:${seller.id}')
                          ? busyProgress()
                          : const Text('승인'),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildOrders() {
    return PortalSection(
      title: '전체 주문 줄',
      child: _orderItems.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(22),
              child: Text('주문 줄이 없습니다.'),
            )
          : Column(
              children: [
                for (final item in _orderItems)
                  ListTile(
                    title: Text(item.productTitle),
                    subtitle: Text(
                      '${item.shopName ?? ''} · '
                      '${shippingOwnerLabel(item.sellerType ?? 'merchant')} · '
                      '${fulfillmentStatusLabel(item.fulfillmentStatus)}',
                    ),
                    trailing:
                        nextFulfillmentStatus(item.fulfillmentStatus) == null
                        ? PortalStatusBadge(
                            label: fulfillmentStatusLabel(
                              item.fulfillmentStatus,
                            ),
                          )
                        : TextButton(
                            onPressed: _pageLocked || isBusy('order:${item.id}')
                                ? null
                                : () => _advanceOrder(item),
                            child: isBusy('order:${item.id}')
                                ? busyProgress()
                                : Text(
                                    nextFulfillmentActionLabel(
                                      item.fulfillmentStatus,
                                    ),
                                  ),
                          ),
                  ),
              ],
            ),
    );
  }

  Widget _buildCatalog() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PortalSection(
          title: '카드 검수 큐',
          child: Padding(
            padding: EdgeInsets.all(18),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.category_outlined),
              title: Text('준비 중'),
              subtitle: Text('카드 초안 연결·승격 API가 추가되면 이곳에서 검수합니다.'),
            ),
          ),
        ),
        const SizedBox(height: 18),
        PortalSection(
          title: '카탈로그 CSV 비상 업로드',
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _CatalogImportPanel(
              importing: isBusy('import'),
              locked: _pageLocked,
              processing: _importProcessing,
              sendProgress: _importSend,
              fileName: _importFileName,
              resultText: _importResult,
              onUpload: _importCatalog,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUsers() {
    return AdminUsersPanel(
      users: [
        for (final user in _users)
          if (user is Map) Map<String, dynamic>.from(user),
      ],
      queryController: _userSearchCtrl,
      adminDraft: _adminDraft,
      pageLocked: _pageLocked,
      isRowBusy: (id) => isBusy('user:$id'),
      onSearch: () {
        setState(() => _userQuery = _userSearchCtrl.text.trim());
        _load();
      },
      onAdminChanged: (id, value) => setState(() => _adminDraft[id] = value),
      onSave: _saveUserRole,
      onDelete: (id) {
        final match = _users.cast<dynamic>().where((item) => item['id'] == id);
        final email = match.isEmpty
            ? ''
            : match.first['email'] as String? ?? '';
        _deleteUser(id, email);
      },
    );
  }

  Widget _buildTools() {
    return PortalSection(
      title: 'DB 초기화 (개발용)',
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '시드만 = 카탈로그를 유지합니다. 삭제 모드는 복구할 수 없습니다.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _resetMode,
              decoration: const InputDecoration(labelText: '초기화 범위'),
              items: const [
                DropdownMenuItem(value: 'seed', child: Text('시드만 (카탈로그 유지)')),
                DropdownMenuItem(
                  value: 'truncate_except_users',
                  child: Text('사용자 제외 초기화'),
                ),
                DropdownMenuItem(value: 'truncate_all', child: Text('전체 초기화')),
              ],
              onChanged: _pageLocked
                  ? null
                  : (value) => setState(() => _resetMode = value ?? 'seed'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _pageLocked ? null : _reset,
              icon: _resetting
                  ? busyProgress()
                  : const Icon(Icons.delete_outline),
              label: Text(_resetting ? _resetBusyLabel() : 'DB 초기화 실행'),
            ),
            if (_message != null) ...[
              const SizedBox(height: 10),
              Text(_message!),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull?.user;

    if (user?.isAdmin != true) {
      return const Center(child: Text('관리자 권한이 필요합니다.'));
    }

    if (widget.section != null) {
      return _buildWorkspace(widget.section!);
    }

    final children = <Widget>[
      Text('관리자', style: Theme.of(context).textTheme.headlineSmall),

      if (_stats != null) ...[
        if (isWebUi)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),

              child: Wrap(
                spacing: 24,

                runSpacing: 12,

                children: [
                  _StatCell(label: '사용자', value: '${_stats!['userCount']}'),

                  _StatCell(label: '상품', value: '${_stats!['productCount']}'),

                  _StatCell(label: '주문', value: '${_stats!['orderCount']}'),

                  _StatCell(label: '판매자', value: '${_stats!['sellerCount']}'),

                  _StatCell(
                    label: '승인 대기',
                    value: '${_stats!['pendingSellerCount']}',
                  ),
                ],
              ),
            ),
          )
        else ...[
          Text('사용자: ${_stats!['userCount']}'),

          Text('상품: ${_stats!['productCount']}'),

          Text('주문: ${_stats!['orderCount']}'),

          Text('판매자: ${_stats!['sellerCount']}'),

          Text('승인 대기: ${_stats!['pendingSellerCount']}'),
        ],
      ],

      const Divider(),

      Text('입점 승인', style: Theme.of(context).textTheme.titleMedium),

      if (_pendingSellers.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),

          child: Text('대기 중인 입점 신청이 없습니다.'),
        )
      else
        ..._pendingSellers.map(
          (s) => ListTile(
            title: Text(s.shopName),

            subtitle: Text(s.userEmail),

            trailing: FilledButton(
              onPressed: _pageLocked || isBusy('approve:${s.id}')
                  ? null
                  : () => _approveSeller(s.id),

              child: isBusy('approve:${s.id}')
                  ? busyProgress()
                  : const Text('승인'),
            ),
          ),
        ),

      const Divider(),

      Text('주문 배송', style: Theme.of(context).textTheme.titleMedium),

      if (_orderItems.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),

          child: Text('주문 라인이 없습니다.'),
        )
      else
        ..._orderItems.map(
          (item) => Card(
            child: ListTile(
              title: Text(item.productTitle),

              subtitle: Text(
                '${item.shopName ?? ''} · '
                '${shippingOwnerLabel(item.sellerType ?? 'merchant')} · '
                '${fulfillmentStatusLabel(item.fulfillmentStatus)}',
              ),

              trailing: nextFulfillmentStatus(item.fulfillmentStatus) == null
                  ? null
                  : TextButton(
                      onPressed: _pageLocked || isBusy('order:${item.id}')
                          ? null
                          : () => _advanceOrder(item),

                      child: isBusy('order:${item.id}')
                          ? busyProgress()
                          : Text(
                              nextFulfillmentActionLabel(
                                item.fulfillmentStatus,
                              ),
                            ),
                    ),
            ),
          ),
        ),

      const Divider(),

      _CatalogImportPanel(
        importing: isBusy('import'),
        locked: _pageLocked,

        processing: _importProcessing,

        sendProgress: _importSend,

        fileName: _importFileName,

        resultText: _importResult,

        onUpload: _importCatalog,
      ),

      const Divider(),

      const Text('DB 초기화'),
      const SizedBox(height: 4),
      Text(
        '시드만 = 카탈로그를 유지합니다. 식약처 데이터를 비우려면 사용자 제외를 고르세요.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      DropdownButton<String>(
        value: _resetMode,
        items: const [
          DropdownMenuItem(value: 'seed', child: Text('시드만 (카탈로그 유지)')),
          DropdownMenuItem(
            value: 'truncate_except_users',
            child: Text('사용자 제외 초기화 (카탈로그 삭제)'),
          ),
          DropdownMenuItem(value: 'truncate_all', child: Text('전체 초기화')),
        ],
        onChanged: _pageLocked
            ? null
            : (v) => setState(() => _resetMode = v ?? 'seed'),
      ),
      FilledButton.icon(
        onPressed: _pageLocked ? null : _reset,
        icon: _resetting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.delete_outline),
        label: Text(_resetting ? _resetBusyLabel() : 'DB 초기화 실행'),
      ),
      if (_message != null) ...[const SizedBox(height: 8), Text(_message!)],

      const Divider(),

      _buildUsers(),
    ];

    if (isWebUi) {
      return PageFormScaffold(
        maxWidth: 900,

        padding: const EdgeInsets.all(24),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
    }

    return ListView(padding: const EdgeInsets.all(16), children: children);
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value});

  final String label;

  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.headlineSmall),

        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _CatalogImportPanel extends StatelessWidget {
  const _CatalogImportPanel({
    required this.importing,
    required this.processing,
    required this.sendProgress,
    required this.onUpload,
    this.locked = false,
    this.fileName,
    this.resultText,
  });

  final bool importing;
  final bool processing;
  final bool locked;
  final double sendProgress;
  final String? fileName;
  final String? resultText;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (sendProgress * 100).round().clamp(0, 100);
    final status = importing
        ? '카탈로그에 넣는 중 $percent% — 창을 닫지 마세요.'
        : (resultText ??
              'data/aihub-catalog.csv만 올리세요. 식약처 원본·mfds 30만 줄은 여기서 올리면 연결이 끊깁니다.');

    return Card(
      color: importing ? const Color(0xFFEFF6FF) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('카탈로그 CSV', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (fileName != null)
              Text(fileName!, style: theme.textTheme.bodySmall),
            if (importing) ...[
              const SizedBox(height: 8),
              Text(
                '$percent%',
                textAlign: TextAlign.center,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text('카탈로그에 넣는 중 — 창을 닫지 마세요.', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: sendProgress.clamp(0.0, 1.0)),
            ] else
              Text(status),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: importing || locked ? null : onUpload,
              icon: importing ? busyProgress() : const Icon(Icons.upload_file),
              label: Text(importing ? '업로드 중 $percent%' : 'CSV 업로드'),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminUsersPanel extends StatelessWidget {
  const AdminUsersPanel({
    super.key,
    required this.users,
    required this.queryController,
    required this.adminDraft,
    required this.pageLocked,
    required this.isRowBusy,
    required this.onSearch,
    required this.onAdminChanged,
    required this.onSave,
    required this.onDelete,
  });

  final List<Map<String, dynamic>> users;
  final TextEditingController queryController;
  final Map<String, bool> adminDraft;
  final bool pageLocked;
  final bool Function(String id) isRowBusy;
  final VoidCallback onSearch;
  final void Function(String id, bool isAdmin) onAdminChanged;
  final void Function(String id) onSave;
  final void Function(String id) onDelete;

  @override
  Widget build(BuildContext context) {
    return PortalSection(
      title: '사용자 ${users.length}명',
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: queryController,
                    decoration: const InputDecoration(
                      labelText: '이메일·이름 검색',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (_) => onSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: onSearch, child: const Text('검색')),
              ],
            ),
            const SizedBox(height: 12),
            if (users.isEmpty)
              const Padding(
                padding: EdgeInsets.all(22),
                child: Text('사용자가 없습니다.'),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('이메일')),
                    DataColumn(label: Text('이름')),
                    DataColumn(label: Text('역할')),
                    DataColumn(label: Text('관리자')),
                    DataColumn(label: Text('저장')),
                    DataColumn(label: Text('삭제')),
                  ],
                  rows: [
                    for (final user in users)
                      DataRow(
                        cells: [
                          DataCell(Text(user['email'] as String? ?? '')),
                          DataCell(Text(user['displayName'] as String? ?? '—')),
                          DataCell(_RoleChips(user: user)),
                          DataCell(
                            Checkbox(
                              value:
                                  adminDraft[user['id'] as String] ??
                                  user['isAdmin'] == true,
                              onChanged:
                                  pageLocked || isRowBusy(user['id'] as String)
                                  ? null
                                  : (value) => onAdminChanged(
                                      user['id'] as String,
                                      value ?? false,
                                    ),
                            ),
                          ),
                          DataCell(
                            FilledButton(
                              onPressed:
                                  pageLocked || isRowBusy(user['id'] as String)
                                  ? null
                                  : () => onSave(user['id'] as String),
                              child: isRowBusy(user['id'] as String)
                                  ? busyProgress()
                                  : const Text('저장'),
                            ),
                          ),
                          DataCell(
                            TextButton(
                              onPressed:
                                  pageLocked || isRowBusy(user['id'] as String)
                                  ? null
                                  : () => onDelete(user['id'] as String),
                              child: const Text('삭제'),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoleChips extends StatelessWidget {
  const _RoleChips({required this.user});

  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context) {
    final sellerStatus = user['sellerStatus'] as String?;
    final isAdmin = user['isAdmin'] == true;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        const Chip(label: Text('구매자'), visualDensity: VisualDensity.compact),
        if (sellerStatus != null)
          Chip(
            label: Text('판매자${_sellerStatusLabel(sellerStatus)}'),
            visualDensity: VisualDensity.compact,
          ),
        if (isAdmin)
          const Chip(label: Text('관리자'), visualDensity: VisualDensity.compact),
      ],
    );
  }
}

String _sellerStatusLabel(String status) {
  return switch (status) {
    'pending' => ' · 대기',
    'active' => '',
    'suspended' => ' · 정지',
    _ => ' · $status',
  };
}
