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
import '../../shared/widgets/catalog_browse_card.dart';
import '../../shared/widgets/page_form_scaffold.dart';
import '../../shared/widgets/portal_workspace.dart';
import 'admin_dashboard.dart';
import '../seller/sales_stats_panel.dart';
import '../seller/seller_offer_format.dart';

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
  final _catalogSearchCtrl = TextEditingController();

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
    _catalogSearchCtrl.dispose();
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

  Future<String?> _askReason(String title) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '사유',
            hintText: '판매자에게 보이는 사유를 적으세요.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty) return null;
    return reason;
  }

  Future<void> _moderateSeller({
    required String sellerId,
    required String action,
    required String title,
    required String doneMessage,
    required Future<void> Function(String id, String reason) run,
  }) async {
    final reason = await _askReason(title);
    if (reason == null) return;
    await runBusy('$action:$sellerId', () async {
      try {
        await run(sellerId, reason);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(doneMessage)));
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    });
  }

  Future<void> _addCatalogItem() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _AdminCatalogCreateDialog(),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('카드를 추가했습니다.')));
    }
  }

  Future<void> _deleteCatalogItem(AdminCatalogProductModel item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('카드를 삭제할까요?'),
        content: Text(
          '${item.cardTitle}을(를) 공개 목록에서 내립니다. 주문 기록은 남고, 붙은 오퍼는 숨깁니다.',
        ),
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
    await runBusy('catalog:${item.id}', () async {
      try {
        await _dashNotifier.deleteCatalogItem(item.id);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('카드를 삭제했습니다.')));
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
        ).showSnackBar(const SnackBar(content: Text('저장했습니다.')));
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
        SalesStatsPanel(stats: stats),
        const SizedBox(height: 18),
        PortalSection(
          title: '몰 운영 현황',
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                Text('사용자 ${stats['userCount']}명'),
                Text('판매자 ${stats['sellerCount']}명'),
                Text('현재 오퍼 ${stats['productCount']}건'),
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
    return AdminSellersPanel(
      sellers: _dash.sellers,
      pendingSellers: _dash.pendingSellers,
      loading: _dash.sellersLoading && _dash.sellers.isEmpty,
      pageLocked: _pageLocked,
      isRowBusy: (key) => isBusy(key),
      onApprove: _approveSeller,
      onWarn: (id) => _moderateSeller(
        sellerId: id,
        action: 'warn',
        title: '경고 사유',
        doneMessage: '경고를 남겼습니다.',
        run: _dashNotifier.warnSeller,
      ),
      onSuspend: (id) => _moderateSeller(
        sellerId: id,
        action: 'suspend',
        title: '정지 사유',
        doneMessage: '판매자를 정지했습니다.',
        run: _dashNotifier.suspendSeller,
      ),
      onUnsuspend: (id) => _moderateSeller(
        sellerId: id,
        action: 'unsuspend',
        title: '정지 해제 사유',
        doneMessage: '정지를 해제했습니다.',
        run: _dashNotifier.unsuspendSeller,
      ),
      onRemove: (id) => _moderateSeller(
        sellerId: id,
        action: 'remove',
        title: '판매자 해제 사유',
        doneMessage: '판매자를 해제했습니다.',
        run: _dashNotifier.removeSeller,
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
        AdminCatalogItemsPanel(
          items: _dash.catalogItems,
          total: _dash.catalogTotal,
          offset: _dash.catalogOffset,
          limit: _dash.catalogLimit,
          l1Tag: _dash.catalogL1Tag,
          includeRetired: _dash.catalogIncludeRetired,
          loading: _dash.catalogItemsLoading && _dash.catalogItems.isEmpty,
          pageLocked: _pageLocked,
          queryController: _catalogSearchCtrl,
          isRowBusy: (id) => isBusy('catalog:$id'),
          onSearch: () {
            unawaited(
              _dashNotifier.loadCatalogItems(
                force: true,
                q: _catalogSearchCtrl.text.trim(),
                offset: 0,
              ),
            );
          },
          onQueryChanged: _dashNotifier.searchCatalog,
          onL1Tag: (tag) {
            unawaited(
              _dashNotifier.loadCatalogItems(
                force: true,
                l1Tag: tag ?? '',
                offset: 0,
              ),
            );
          },
          onIncludeRetired: (value) {
            unawaited(
              _dashNotifier.loadCatalogItems(
                force: true,
                includeRetired: value,
                offset: 0,
              ),
            );
          },
          onPrev: _dash.catalogOffset <= 0
              ? null
              : () {
                  final prev = _dash.catalogOffset - _dash.catalogLimit;
                  unawaited(
                    _dashNotifier.loadCatalogItems(
                      force: true,
                      offset: prev < 0 ? 0 : prev,
                    ),
                  );
                },
          onNext: _dash.catalogOffset + _dash.catalogItems.length >=
                  _dash.catalogTotal
              ? null
              : () {
                  unawaited(
                    _dashNotifier.loadCatalogItems(
                      force: true,
                      offset: _dash.catalogOffset + _dash.catalogLimit,
                    ),
                  );
                },
          onAdd: _addCatalogItem,
          onDelete: _deleteCatalogItem,
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
      userDrafts: _dash.userDrafts,
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
      onDraftChanged: _dashNotifier.setUserDraft,
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

class AdminSellersPanel extends StatelessWidget {
  const AdminSellersPanel({
    super.key,
    required this.sellers,
    required this.pendingSellers,
    required this.pageLocked,
    required this.isRowBusy,
    required this.onApprove,
    required this.onWarn,
    required this.onSuspend,
    required this.onUnsuspend,
    required this.onRemove,
    this.loading = false,
  });

  final List<AdminSellerModel> sellers;
  final List<AdminSellerModel> pendingSellers;
  final bool pageLocked;
  final bool Function(String key) isRowBusy;
  final void Function(String id) onApprove;
  final void Function(String id) onWarn;
  final void Function(String id) onSuspend;
  final void Function(String id) onUnsuspend;
  final void Function(String id) onRemove;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final active = [
      for (final seller in sellers)
        if (seller.status == 'active') seller,
    ];
    final suspended = [
      for (final seller in sellers)
        if (seller.status == 'suspended') seller,
    ];
    final removed = [
      for (final seller in sellers)
        if (seller.status == 'removed') seller,
    ];
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(22),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PortalSection(
          title: '승인 대기 ${pendingSellers.length}건',
          child: pendingSellers.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('대기 중인 입점 신청이 없습니다.'),
                )
              : Column(
                  children: [
                    for (final seller in pendingSellers)
                      ListTile(
                        leading: const Icon(Icons.storefront_outlined),
                        title: Text(seller.shopName),
                        subtitle: Text(
                          '${seller.userEmail} · ${seller.sellerType}',
                        ),
                        trailing: FilledButton(
                          onPressed: pageLocked || isRowBusy('approve:${seller.id}')
                              ? null
                              : () => onApprove(seller.id),
                          child: isRowBusy('approve:${seller.id}')
                              ? busyProgress()
                              : const Text('승인'),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 18),
        PortalSection(
          title: '운영 중 판매자',
          child: active.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('운영 중인 판매자가 없습니다.'),
                )
              : Column(
                  children: [
                    for (final seller in active)
                      _SellerModerationTile(
                        seller: seller,
                        pageLocked: pageLocked,
                        isRowBusy: isRowBusy,
                        onWarn: onWarn,
                        onSuspend: onSuspend,
                        onRemove: onRemove,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 18),
        PortalSection(
          title: '정지 · 해제',
          child: suspended.isEmpty && removed.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('정지·해제된 판매자가 없습니다.'),
                )
              : Column(
                  children: [
                    for (final seller in suspended)
                      _SellerModerationTile(
                        seller: seller,
                        pageLocked: pageLocked,
                        isRowBusy: isRowBusy,
                        onUnsuspend: onUnsuspend,
                        onRemove: onRemove,
                      ),
                    for (final seller in removed)
                      _SellerModerationTile(seller: seller, pageLocked: true),
                  ],
                ),
        ),
      ],
    );
  }
}

class _SellerModerationTile extends StatelessWidget {
  const _SellerModerationTile({
    required this.seller,
    required this.pageLocked,
    this.isRowBusy,
    this.onWarn,
    this.onSuspend,
    this.onUnsuspend,
    this.onRemove,
  });

  final AdminSellerModel seller;
  final bool pageLocked;
  final bool Function(String key)? isRowBusy;
  final void Function(String id)? onWarn;
  final void Function(String id)? onSuspend;
  final void Function(String id)? onUnsuspend;
  final void Function(String id)? onRemove;

  bool _busy(String action) => isRowBusy?.call('$action:${seller.id}') ?? false;

  @override
  Widget build(BuildContext context) {
    final subtitle = StringBuffer(seller.userEmail);
    if (seller.warningCount > 0) {
      subtitle.write(' · 경고 ${seller.warningCount}');
    }
    if (seller.lastModerationReason != null &&
        seller.lastModerationReason!.isNotEmpty) {
      subtitle.write(' · ${seller.lastModerationReason}');
    }
    return ListTile(
      leading: Icon(
        seller.status == 'removed'
            ? Icons.store_mall_directory_outlined
            : Icons.storefront_outlined,
      ),
      title: Text(
        '${seller.shopName}${seller.isPlatform ? ' (공식)' : ''}'
        '${seller.status == 'suspended' ? ' · 정지' : ''}'
        '${seller.status == 'removed' ? ' · 해제' : ''}',
      ),
      subtitle: Text(subtitle.toString()),
      trailing: seller.isPlatform
          ? const PortalStatusBadge(label: '공식')
          : Wrap(
              spacing: 6,
              children: [
                if (onWarn != null)
                  TextButton(
                    onPressed: pageLocked || _busy('warn')
                        ? null
                        : () => onWarn!(seller.id),
                    child: _busy('warn') ? busyProgress() : const Text('경고'),
                  ),
                if (onSuspend != null)
                  TextButton(
                    onPressed: pageLocked || _busy('suspend')
                        ? null
                        : () => onSuspend!(seller.id),
                    child: _busy('suspend') ? busyProgress() : const Text('정지'),
                  ),
                if (onUnsuspend != null)
                  FilledButton.tonal(
                    onPressed: pageLocked || _busy('unsuspend')
                        ? null
                        : () => onUnsuspend!(seller.id),
                    child: _busy('unsuspend')
                        ? busyProgress()
                        : const Text('정지 해제'),
                  ),
                if (onRemove != null)
                  TextButton(
                    onPressed: pageLocked || _busy('remove')
                        ? null
                        : () => onRemove!(seller.id),
                    child: _busy('remove') ? busyProgress() : const Text('해제'),
                  ),
              ],
            ),
    );
  }
}

class AdminCatalogItemsPanel extends StatelessWidget {
  const AdminCatalogItemsPanel({
    super.key,
    required this.items,
    required this.total,
    required this.offset,
    required this.limit,
    required this.l1Tag,
    required this.includeRetired,
    required this.pageLocked,
    required this.queryController,
    required this.isRowBusy,
    required this.onSearch,
    required this.onQueryChanged,
    required this.onL1Tag,
    required this.onIncludeRetired,
    required this.onAdd,
    required this.onDelete,
    this.onPrev,
    this.onNext,
    this.loading = false,
  });

  final List<AdminCatalogProductModel> items;
  final int total;
  final int offset;
  final int limit;
  final String l1Tag;
  final bool includeRetired;
  final bool pageLocked;
  final TextEditingController queryController;
  final bool Function(String id) isRowBusy;
  final VoidCallback onSearch;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String?> onL1Tag;
  final ValueChanged<bool> onIncludeRetired;
  final VoidCallback onAdd;
  final void Function(AdminCatalogProductModel item) onDelete;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final bool loading;

  String get _rangeLabel {
    if (total == 0) return '0건';
    final from = offset + 1;
    final to = offset + items.length;
    return '$from–$to / $total건';
  }

  @override
  Widget build(BuildContext context) {
    return PortalSection(
      title: '대표 카드 $total건',
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: queryController,
                    decoration: const InputDecoration(
                      labelText: '회사·품목·종류 검색',
                      hintText: '백산수, 농심, 생수',
                    ),
                    onChanged: onQueryChanged,
                    onSubmitted: (_) => onSearch(),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: pageLocked ? null : onSearch,
                  child: const Text('검색'),
                ),
                DropdownButton<String?>(
                  value: l1Tag.isEmpty ? null : l1Tag,
                  hint: const Text('1차 분류'),
                  onChanged: pageLocked ? null : onL1Tag,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('전체 1차'),
                    ),
                    for (final category in kGuestL1Categories)
                      DropdownMenuItem<String?>(
                        value: category.name,
                        child: Text(category.name),
                      ),
                  ],
                ),
                FilterChip(
                  label: const Text('삭제한 카드'),
                  selected: includeRetired,
                  onSelected: pageLocked ? null : onIncludeRetired,
                ),
                FilledButton(
                  onPressed: pageLocked ? null : onAdd,
                  child: const Text('카드 추가'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  _rangeLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                TextButton(
                  onPressed: pageLocked ? null : onPrev,
                  child: const Text('이전'),
                ),
                TextButton(
                  onPressed: pageLocked ? null : onNext,
                  child: const Text('다음'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(18),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('표시할 카드가 없습니다. 검색하거나 카드를 추가하세요.'),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final columns = width >= 980
                      ? 4
                      : width >= 720
                          ? 3
                          : 2;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: items.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      childAspectRatio: 0.62,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return CatalogBrowseCard(
                        title: item.title,
                        cardTitle: item.cardTitle,
                        offerCount: item.publishedOfferCount,
                        priceUnit: item.priceUnit,
                        displayPriceLabel: item.displayPriceLabel,
                        imageUrl: item.imageUrl,
                        medianUnitPrice: item.medianUnitPrice,
                        medianPriceCredits: item.medianPriceCredits,
                        shopCount: item.shopCount,
                        statusLabel: item.isRetired ? '삭제됨' : null,
                        action: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: pageLocked ||
                                    isRowBusy(item.id) ||
                                    item.isRetired
                                ? null
                                : () => onDelete(item),
                            child: isRowBusy(item.id)
                                ? busyProgress()
                                : const Text('삭제'),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _AdminCatalogCreateDialog extends ConsumerStatefulWidget {
  const _AdminCatalogCreateDialog();

  @override
  ConsumerState<_AdminCatalogCreateDialog> createState() =>
      _AdminCatalogCreateDialogState();
}

class _AdminCatalogCreateDialogState
    extends ConsumerState<_AdminCatalogCreateDialog> with AsyncBusyState {
  final _manufacturer = TextEditingController();
  final _title = TextEditingController();
  final _category = TextEditingController();
  final _imageUrl = TextEditingController();
  final _amount = TextEditingController();
  final _pack = TextEditingController(text: '1');
  final _volumeOptions = <String>[];
  String _unit = 'ml';
  String? _error;

  @override
  void dispose() {
    _manufacturer.dispose();
    _title.dispose();
    _category.dispose();
    _imageUrl.dispose();
    _amount.dispose();
    _pack.dispose();
    super.dispose();
  }

  void _addVolumeOption() {
    final amount = double.tryParse(_amount.text.trim());
    final pack = int.tryParse(_pack.text.trim());
    if (amount == null || amount <= 0 || pack == null || pack < 1) {
      setState(() => _error = '용량은 0보다 크게, 들이 개수는 1개 이상으로 입력하세요.');
      return;
    }
    final label = formatSellerUnitLabel(amount: amount, unit: _unit, packCount: pack);
    setState(() {
      if (!_volumeOptions.contains(label)) _volumeOptions.add(label);
      _amount.clear();
      _pack.text = '1';
      _error = null;
    });
  }

  Future<void> _submit() async {
    final manufacturer = _manufacturer.text.trim();
    final title = _title.text.trim();
    final category = _category.text.trim();
    if (manufacturer.isEmpty || title.isEmpty || category.isEmpty) {
      setState(() => _error = '회사·품목명·종류를 모두 적으세요.');
      return;
    }
    if (_amount.text.trim().isNotEmpty) {
      setState(() => _error = '입력한 용량은 먼저 옵션 추가를 누르세요.');
      return;
    }
    final priceUnit = _volumeOptions.isNotEmpty &&
            _volumeOptions.every((label) {
              final unit = parseSellerUnitLabel(label)?.unit;
              return unit == 'ml' || unit == 'L';
            })
        ? 'ml'
        : 'credits';
    await runBusy('create', () async {
      try {
        await ref.read(adminDashboardProvider.notifier).addCatalogItem(
              manufacturer: manufacturer,
              title: title,
              category: category,
              imageUrl: _imageUrl.text.trim(),
              volumeOptions: _volumeOptions,
              priceUnit: priceUnit,
            );
        if (mounted) Navigator.pop(context, true);
      } on ApiException catch (e) {
        if (mounted) setState(() => _error = e.message);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final busy = isBusy('create');
    return AlertDialog(
      title: const Text('대표 카드 추가'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
              decoration: const InputDecoration(labelText: '종류(소분류)'),
            ),
            TextField(
              controller: _imageUrl,
              decoration: const InputDecoration(labelText: '대표 사진 URL (선택)'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _amount,
                  decoration: const InputDecoration(labelText: '용량·팩 (선택)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _unit,
                items: [
                  for (final unit in sellerOfferUnits)
                    DropdownMenuItem(value: unit, child: Text(unit)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _unit = value);
                },
              ),
            ]),
            TextField(
              controller: _pack,
              decoration: const InputDecoration(labelText: '들이 개수', hintText: '낱개는 1'),
              keyboardType: TextInputType.number,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: busy ? null : _addVolumeOption,
                child: const Text('옵션 추가'),
              ),
            ),
            if (_volumeOptions.isNotEmpty)
              Wrap(
                spacing: 8,
                children: [
                  for (final option in _volumeOptions)
                    InputChip(
                      label: Text(option),
                      onDeleted: busy ? null : () => setState(() => _volumeOptions.remove(option)),
                    ),
                ],
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        )),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: busy ? null : _submit,
          child: busy ? busyProgress() : const Text('추가'),
        ),
      ],
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

class AdminUsersPanel extends StatefulWidget {
  const AdminUsersPanel({
    super.key,
    required this.users,
    required this.queryController,
    required this.userDrafts,
    required this.pageLocked,
    required this.isRowBusy,
    required this.onSearch,
    required this.onDraftChanged,
    required this.onSave,
    required this.onDelete,
    this.loading = false,
  });

  final List<Map<String, dynamic>> users;
  final TextEditingController queryController;
  final Map<String, AdminUserRowDraft> userDrafts;
  final bool pageLocked;
  final bool Function(String id) isRowBusy;
  final VoidCallback onSearch;
  final void Function(String id, AdminUserRowDraft draft) onDraftChanged;
  final void Function(String id) onSave;
  final void Function(String id) onDelete;
  final bool loading;

  @override
  State<AdminUsersPanel> createState() => _AdminUsersPanelState();
}

class _AdminUsersPanelState extends State<AdminUsersPanel> {
  final _buyerNames = <String, TextEditingController>{};
  final _sellerNames = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _syncNameControllers();
  }

  @override
  void didUpdateWidget(AdminUsersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncNameControllers();
  }

  @override
  void dispose() {
    for (final controller in _buyerNames.values) {
      controller.dispose();
    }
    for (final controller in _sellerNames.values) {
      controller.dispose();
    }
    super.dispose();
  }

  AdminUserRowDraft _draftFor(Map<String, dynamic> user) {
    final id = user['id'] as String;
    return widget.userDrafts[id] ?? adminUserDraftFromMap(user);
  }

  void _syncNameControllers() {
    final ids = {for (final user in widget.users) user['id'] as String};
    for (final id in [..._buyerNames.keys]) {
      if (ids.contains(id)) continue;
      _buyerNames.remove(id)?.dispose();
      _sellerNames.remove(id)?.dispose();
    }
    for (final user in widget.users) {
      final id = user['id'] as String;
      final draft = _draftFor(user);
      _buyerNames.putIfAbsent(
        id,
        () => TextEditingController(text: draft.buyerName),
      );
      _sellerNames.putIfAbsent(
        id,
        () => TextEditingController(text: draft.sellerName),
      );
    }
  }

  void _pushDraft(String id, AdminUserRowDraft draft) {
    widget.onDraftChanged(
      id,
      draft.copyWith(
        buyerName: _buyerNames[id]?.text ?? draft.buyerName,
        sellerName: _sellerNames[id]?.text ?? draft.sellerName,
      ),
    );
  }

  void _saveRow(String id, AdminUserRowDraft draft) {
    _pushDraft(id, draft);
    widget.onSave(id);
  }

  @override
  Widget build(BuildContext context) {
    return PortalSection(
      title: '사용자 ${widget.users.length}명',
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.queryController,
                    decoration: const InputDecoration(
                      labelText: '이메일·이름 검색',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (_) => widget.onSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: widget.onSearch,
                  child: const Text('검색'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.loading)
              const Padding(
                padding: EdgeInsets.all(22),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (widget.users.isEmpty)
              const Padding(
                padding: EdgeInsets.all(22),
                child: Text('사용자가 없습니다.'),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 48,
                  dataRowMinHeight: 72,
                  dataRowMaxHeight: 96,
                  columnSpacing: 20,
                  columns: const [
                    DataColumn(label: Text('이메일')),
                    DataColumn(label: Text('구매자 이름')),
                    DataColumn(label: Text('판매자 이름')),
                    DataColumn(label: Text('구매자')),
                    DataColumn(label: Text('판매자')),
                    DataColumn(label: Text('관리자')),
                    DataColumn(label: Text('저장')),
                    DataColumn(label: Text('삭제')),
                  ],
                  rows: [
                    for (final user in widget.users)
                      _userRow(user, _draftFor(user)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  DataRow _userRow(Map<String, dynamic> user, AdminUserRowDraft draft) {
    final id = user['id'] as String;
    final busy = widget.pageLocked || widget.isRowBusy(id);
    final isPlatform = user['sellerType'] == 'platform';
    final sellerHint = _sellerStatusHint(user['sellerStatus'] as String?);
    return DataRow(
      cells: [
        DataCell(Text(user['email'] as String? ?? '')),
        DataCell(
          SizedBox(
            width: 160,
            child: TextField(
              controller: _buyerNames[id]!,
              enabled: !busy,
              decoration: const InputDecoration(
                isDense: true,
                hintText: '구매자 표시 이름',
              ),
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 160,
            child: TextField(
              controller: _sellerNames[id]!,
              enabled: !busy,
              decoration: const InputDecoration(
                isDense: true,
                hintText: '가게 이름',
              ),
            ),
          ),
        ),
        DataCell(
          _RoleToggle(
            value: draft.isBuyer,
            enabled: !busy,
            onChanged: (value) => _pushDraft(id, draft.copyWith(isBuyer: value)),
          ),
        ),
        DataCell(
          _RoleToggle(
            value: draft.isSeller,
            enabled: !busy && !(isPlatform && draft.isSeller),
            hint: sellerHint,
            onChanged: (value) => _pushDraft(id, draft.copyWith(isSeller: value)),
          ),
        ),
        DataCell(
          _RoleToggle(
            value: draft.isAdmin,
            enabled: !busy,
            onChanged: (value) => _pushDraft(id, draft.copyWith(isAdmin: value)),
          ),
        ),
        DataCell(
          FilledButton(
            onPressed: busy ? null : () => _saveRow(id, draft),
            child: widget.isRowBusy(id) ? busyProgress() : const Text('저장'),
          ),
        ),
        DataCell(
          TextButton(
            onPressed: busy ? null : () => widget.onDelete(id),
            child: const Text('삭제'),
          ),
        ),
      ],
    );
  }
}

class _RoleToggle extends StatelessWidget {
  const _RoleToggle({
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.hint,
  });

  final bool value;
  final bool enabled;
  final String? hint;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 72,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Checkbox(
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            value: value,
            onChanged: enabled ? (next) => onChanged(next ?? false) : null,
          ),
          if (hint != null && hint!.isNotEmpty)
            Text(
              hint!,
              style: theme.textTheme.labelSmall,
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}

String? _sellerStatusHint(String? status) {
  return switch (status) {
    'pending' => '대기',
    'suspended' => '정지',
    'removed' => '해제',
    'active' => null,
    null => null,
    _ => status,
  };
}
