import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/guest_l1.dart';
import '../../core/fulfillment/fulfillment_labels.dart';
import '../../core/layout/ui_platform.dart';
import '../../core/models/models.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/async_busy.dart';
import '../../shared/widgets/page_form_scaffold.dart';
import '../../shared/widgets/portal_workspace.dart';
import 'admin_dashboard.dart';

export 'admin_dashboard.dart' show AdminSection;

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key, this.section});

  final AdminSection? section;

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> with AsyncBusyState {
  String _resetMode = 'seed';

  String? _message;

  Timer? _pollTimer;

  bool _importProcessing = false;

  double _importSend = 0;

  String? _importFileName;

  String? _importResult;

  final _userSearchCtrl = TextEditingController();

  bool get _resetting => isBusy('reset');

  bool get _pageLocked => isBusy('reset') || isBusy('import');

  AdminDashboardState get _dash => ref.watch(adminDashboardProvider);

  AdminDashboardNotifier get _dashNotifier =>
      ref.read(adminDashboardProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_dashNotifier.ensureSection(widget.section));
      _syncPoll();
    });
  }

  @override
  void didUpdateWidget(covariant AdminScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) {
      unawaited(_dashNotifier.ensureSection(widget.section));
      _syncPoll();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _userSearchCtrl.dispose();
    super.dispose();
  }

  void _syncPoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (widget.section == AdminSection.orders) {
      _pollTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => unawaited(_dashNotifier.loadOrders(silent: true)),
      );
    }
  }

  Future<void> _advanceOrder(SellerOrderItemModel item) async {
    try {
      await _dashNotifier.advanceOrder(item);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('주문 상태를 바꾸지 못했습니다.')));
      }
    }
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
        await _dashNotifier.reloadAll();
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

  Future<void> _attachDraft(IntakeDraftModel draft) async {
    String? catalogId = draft.catalogProductId;
    if (draft.isCard || catalogId == null || catalogId.isEmpty) {
      catalogId = await showDialog<String>(
        context: context,
        builder: (ctx) => const _AdminCatalogPickDialog(),
      );
      if (catalogId == null || catalogId.isEmpty) return;
    }
    await runBusy('draft:${draft.id}', () async {
      try {
        await ref.read(apiClientProvider).adminAttachCatalogDraft(
          draftId: draft.id,
          kind: draft.kind,
          catalogProductId: catalogId,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('기존 카드에 붙였습니다.')));
        await _dashNotifier.removeDraft(draft.id);
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    });
  }

  Future<void> _promoteDraft(IntakeDraftModel draft) async {
    final categoryCtrl = TextEditingController(text: draft.category);
    final manufacturerCtrl = TextEditingController(text: draft.manufacturer);
    final titleCtrl = TextEditingController(text: draft.title);
    final selected = <String>{
      ...draft.l1Tags,
      ...draft.suggestedL1Tags
          .where((s) => s.confidence == 'high')
          .map((s) => s.tag),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('카드로 승격'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: manufacturerCtrl,
                      decoration: const InputDecoration(labelText: '회사'),
                    ),
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(labelText: '품목명'),
                    ),
                    TextField(
                      controller: categoryCtrl,
                      decoration: const InputDecoration(labelText: '종류'),
                    ),
                    const SizedBox(height: 12),
                    const Text('손님 1차 태그 (겹침 허용)'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final name in kGuestL1Categories.map((e) => e.name))
                          FilterChip(
                            label: Text(name),
                            selected: selected.contains(name),
                            onSelected: (on) {
                              setLocal(() {
                                if (on) {
                                  selected.add(name);
                                } else {
                                  selected.remove(name);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('승격'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;
    final category = categoryCtrl.text.trim();
    if (category.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('종류를 적어 주세요.')));
      return;
    }
    await runBusy('draft:${draft.id}', () async {
      try {
        await ref.read(apiClientProvider).adminPromoteCatalogDraft(
          draftId: draft.id,
          category: category,
          manufacturer: manufacturerCtrl.text.trim(),
          title: titleCtrl.text.trim(),
          l1Tags: selected.toList(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('초안을 카탈로그 카드로 올렸습니다.')));
        await _dashNotifier.removeDraft(draft.id);
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    });
  }

  Future<void> _approveSeller(String sellerId) async {
    await runBusy('approve:$sellerId', () async {
      try {
        await _dashNotifier.approveSeller(sellerId);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('입점을 승인했습니다.')));
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
    await runBusy('user:$userId', () async {
      try {
        await _dashNotifier.saveUser(userId);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('역할을 저장했습니다.')));
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
        await _dashNotifier.deleteUser(userId);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('사용자를 삭제했습니다.')));
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_dash.stats == null && _dash.statsLoading)
          const Center(child: CircularProgressIndicator())
        else if (_dash.stats == null)
          const Center(child: Text('통계를 불러오지 못했습니다.'))
        else
          PortalMetricGrid(
            children: [
              PortalMetricCard(
                label: '판매 품목 수',
                value: '${_dash.stats!['soldItemCount'] ?? 0}',
                hint: '팔린 품목',
              ),
              PortalMetricCard(
                label: '수량',
                value: '${_dash.stats!['soldQtySum'] ?? 0}',
                hint: '판매 수량 합',
              ),
              PortalMetricCard(
                label: '총액',
                value: '${_dash.stats!['soldAmountSum'] ?? 0}',
                hint: '원',
              ),
              PortalMetricCard(
                label: '승인 대기',
                value: '${_dash.stats!['pendingSellerCount']}',
                hint: '검토 필요',
                attention: (_dash.stats!['pendingSellerCount'] as int? ?? 0) > 0,
              ),
            ],
          ),
        const SizedBox(height: 18),
        PortalSection(
          title: '입점 승인 대기',
          child: _dash.sellersLoading && _dash.pendingSellers.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _dash.pendingSellers.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('대기 중인 입점 신청이 없습니다.'),
                )
              : Column(
                  children: [
                    for (final seller in _dash.pendingSellers.take(4))
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
    final stats = _dash.stats;
    if (stats == null) {
      return Center(
        child: _dash.statsLoading
            ? const CircularProgressIndicator()
            : const Text('통계를 불러오지 못했습니다.'),
      );
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
      child: _dash.sellersLoading && _dash.pendingSellers.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(22),
              child: Center(child: CircularProgressIndicator()),
            )
          : _dash.pendingSellers.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(22),
              child: Text('대기 중인 입점 신청이 없습니다.'),
            )
          : Column(
              children: [
                for (final seller in _dash.pendingSellers)
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
      child: _dash.ordersLoading && _dash.orderItems.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(22),
              child: Center(child: CircularProgressIndicator()),
            )
          : _dash.orderItems.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(22),
              child: Text('주문 줄이 없습니다.'),
            )
          : Column(
              children: [
                for (final item in _dash.orderItems)
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
        AdminCatalogDraftsPanel(
          drafts: _dash.catalogDrafts,
          loading: _dash.draftsLoading && _dash.catalogDrafts.isEmpty,
          pageLocked: _pageLocked,
          isRowBusy: (id) => isBusy('draft:$id'),
          onAttach: _attachDraft,
          onPromote: _promoteDraft,
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
        for (final user in _dash.users)
          if (user is Map) Map<String, dynamic>.from(user),
      ],
      queryController: _userSearchCtrl,
      adminDraft: _dash.adminDraft,
      pageLocked: _pageLocked,
      loading: _dash.usersLoading && _dash.users.isEmpty,
      isRowBusy: (id) => isBusy('user:$id'),
      onSearch: () {
        unawaited(
          _dashNotifier.loadUsers(
            force: true,
            q: _userSearchCtrl.text.trim(),
          ),
        );
      },
      onAdminChanged: (id, value) => _dashNotifier.setAdminDraft(id, value),
      onSave: _saveUserRole,
      onDelete: (id) {
        final match = _dash.users.where(
          (item) => item is Map && item['id'] == id,
        );
        final email = match.isEmpty
            ? ''
            : (match.first as Map)['email'] as String? ?? '';
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

      if (_dash.stats != null) ...[
        if (isWebUi)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),

              child: Wrap(
                spacing: 24,

                runSpacing: 12,

                children: [
                  _StatCell(label: '사용자', value: '${_dash.stats!['userCount']}'),

                  _StatCell(label: '상품', value: '${_dash.stats!['productCount']}'),

                  _StatCell(label: '주문', value: '${_dash.stats!['orderCount']}'),

                  _StatCell(label: '판매자', value: '${_dash.stats!['sellerCount']}'),

                  _StatCell(
                    label: '승인 대기',
                    value: '${_dash.stats!['pendingSellerCount']}',
                  ),
                ],
              ),
            ),
          )
        else ...[
          Text('사용자: ${_dash.stats!['userCount']}'),

          Text('상품: ${_dash.stats!['productCount']}'),

          Text('주문: ${_dash.stats!['orderCount']}'),

          Text('판매자: ${_dash.stats!['sellerCount']}'),

          Text('승인 대기: ${_dash.stats!['pendingSellerCount']}'),
        ],
      ],

      const Divider(),

      Text('입점 승인', style: Theme.of(context).textTheme.titleMedium),

      if (_dash.pendingSellers.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),

          child: Text('대기 중인 입점 신청이 없습니다.'),
        )
      else
        ..._dash.pendingSellers.map(
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

      if (_dash.orderItems.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),

          child: Text('주문 라인이 없습니다.'),
        )
      else
        ..._dash.orderItems.map(
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

class AdminCatalogDraftsPanel extends StatelessWidget {
  const AdminCatalogDraftsPanel({
    super.key,
    required this.drafts,
    required this.pageLocked,
    required this.isRowBusy,
    required this.onAttach,
    required this.onPromote,
    this.loading = false,
  });

  final List<IntakeDraftModel> drafts;
  final bool pageLocked;
  final bool Function(String id) isRowBusy;
  final void Function(IntakeDraftModel draft) onAttach;
  final void Function(IntakeDraftModel draft) onPromote;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return PortalSection(
      title: '카드 검수 큐 ${drafts.length}건',
      child: loading
          ? const Padding(
              padding: EdgeInsets.all(18),
              child: Center(child: CircularProgressIndicator()),
            )
          : drafts.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(18),
              child: Text('대기 중인 오퍼·카드 초안이 없습니다.'),
            )
          : Column(
              children: [
                for (final draft in drafts)
                  ListTile(
                    leading: Icon(
                      draft.isCard
                          ? Icons.category_outlined
                          : Icons.inventory_2_outlined,
                    ),
                    title: Text(draft.cardTitle),
                    subtitle: Text(
                      '${draft.isCard ? '카드 초안' : '오퍼 초안'} · '
                      '${draft.shopName} · ${draft.category} · '
                      '${draft.optionLabel ?? ''} · ${draft.priceCredits}원',
                    ),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed:
                              pageLocked || isRowBusy(draft.id)
                              ? null
                              : () => onAttach(draft),
                          child: isRowBusy(draft.id)
                              ? busyProgress()
                              : Text(draft.isCard ? '기존 카드에 붙이기' : '승인'),
                        ),
                        if (draft.isCard)
                          FilledButton(
                            onPressed:
                                pageLocked || isRowBusy(draft.id)
                                ? null
                                : () => onPromote(draft),
                            child: const Text('카드로 승격'),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _AdminCatalogPickDialog extends ConsumerStatefulWidget {
  const _AdminCatalogPickDialog();

  @override
  ConsumerState<_AdminCatalogPickDialog> createState() =>
      _AdminCatalogPickDialogState();
}

class _AdminCatalogPickDialogState
    extends ConsumerState<_AdminCatalogPickDialog> {
  final _q = TextEditingController();
  List<CatalogProductModel> _items = [];
  bool _loading = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _q.text.trim();
    if (q.isEmpty || _loading) return;
    setState(() => _loading = true);
    try {
      final page = await ref.read(apiClientProvider).catalogProducts(q: q);
      setState(() => _items = page.items);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('붙일 카드 찾기'),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _q,
              decoration: const InputDecoration(
                labelText: '품목·제조사·분류',
                hintText: '백산수, 떡갈비',
              ),
              onSubmitted: _loading ? null : (_) => _search(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _loading ? null : _search,
                child: Text(_loading ? '검색 중…' : '검색'),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Column(
                children: [
                  if (_loading) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return ListTile(
                          title: Text(item.cardTitle),
                          subtitle: Text(item.category),
                          onTap: () => Navigator.pop(context, item.id),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
      ],
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
    this.loading = false,
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
  final bool loading;

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
            if (loading)
              const Padding(
                padding: EdgeInsets.all(22),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (users.isEmpty)
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
