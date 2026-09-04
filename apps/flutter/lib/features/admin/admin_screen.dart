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



class AdminScreen extends ConsumerStatefulWidget {

  const AdminScreen({super.key});



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

  bool get _resetting => isBusy('reset');

  bool get _pageLocked => isBusy('reset') || isBusy('import');

  @override

  void initState() {

    super.initState();

    _load();

    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _loadOrders(silent: true));

  }

  @override

  void dispose() {

    _pollTimer?.cancel();

    super.dispose();

  }



  Future<void> _load() async {

    final api = ref.read(apiClientProvider);

    final stats = await api.adminStats();

    final users = await api.adminUsers();

    List<AdminSellerModel> pending = [];

    try {

      pending = await api.adminSellers(status: 'pending');

    } catch (_) {}

    await _loadOrders(silent: true);

    setState(() {

      _stats = stats;

      _users = users['items'] as List<dynamic>? ?? [];

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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('실행')),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
        await _load();
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() => _message = e.message);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      } catch (e) {
        if (!mounted) return;
        const text = '초기화에 실패했습니다.';
        setState(() => _message = text);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(text)));
      }
    });
  }

  Future<void> _approveSeller(String sellerId) async {
    await runBusy('approve:$sellerId', () async {
      try {
        await ref.read(apiClientProvider).adminApproveSeller(sellerId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('입점을 승인했습니다.')));
        await _load();
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    });
  }

  Future<void> _promoteUser(String userId) async {
    await runBusy('user:$userId', () async {
      try {
        await ref.read(apiClientProvider).adminPromote(userId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('관리자로 올렸습니다.')));
        await _load();
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    });
  }

  Future<void> _grantCredits(String userId) async {
    await runBusy('user:$userId', () async {
      try {
        await ref.read(apiClientProvider).adminGrantCredits(userId, 100);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('크레딧 100을 지급했습니다.')));
        await _load();
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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
        final result = await ref.read(apiClientProvider).adminImportCatalog(
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() => _importResult = e.message);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    });
  }



  @override

  Widget build(BuildContext context) {

    final user = ref.watch(authStateProvider).valueOrNull?.user;

    if (user?.isAdmin != true) {

      return const Center(child: Text('관리자 권한이 필요합니다.'));

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

                  _StatCell(label: '승인 대기', value: '${_stats!['pendingSellerCount']}'),

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

              onPressed: _pageLocked || isBusy('approve:${s.id}') ? null : () => _approveSeller(s.id),

              child: isBusy('approve:${s.id}') ? busyProgress() : const Text('승인'),

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

                      onPressed: _pageLocked || isBusy('order:${item.id}') ? null : () => _advanceOrder(item),

                      child: isBusy('order:${item.id}')
                          ? busyProgress()
                          : Text(nextFulfillmentActionLabel(item.fulfillmentStatus)),

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
          DropdownMenuItem(value: 'truncate_except_users', child: Text('사용자 제외 초기화 (카탈로그 삭제)')),
          DropdownMenuItem(value: 'truncate_all', child: Text('전체 초기화')),
        ],
        onChanged: _pageLocked ? null : (v) => setState(() => _resetMode = v ?? 'seed'),
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
      if (_message != null) ...[
        const SizedBox(height: 8),
        Text(_message!),
      ],

      const Divider(),

      const Text('사용자'),

      ..._users.map(

        (u) => ListTile(

          title: Text(u['email'] as String? ?? ''),

          subtitle: Text(u['isAdmin'] == true ? '관리자' : '일반'),

          trailing: Row(

            mainAxisSize: MainAxisSize.min,

            children: [

              IconButton(

                icon: isBusy('user:${u['id']}') ? busyProgress() : const Icon(Icons.star),

                onPressed: _pageLocked || isBusy('user:${u['id']}')
                    ? null
                    : () => _promoteUser(u['id'] as String),

              ),

              IconButton(

                icon: isBusy('user:${u['id']}') ? busyProgress() : const Icon(Icons.monetization_on),

                onPressed: _pageLocked || isBusy('user:${u['id']}')
                    ? null
                    : () => _grantCredits(u['id'] as String),

              ),

            ],

          ),

        ),

      ),

    ];



    if (isWebUi) {

      return PageFormScaffold(

        maxWidth: 900,

        padding: const EdgeInsets.all(24),

        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),

      );

    }

    return ListView(

      padding: const EdgeInsets.all(16),

      children: children,

    );

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
                style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '카탈로그에 넣는 중 — 창을 닫지 마세요.',
                textAlign: TextAlign.center,
              ),
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



