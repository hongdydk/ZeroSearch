import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/fulfillment/fulfillment_labels.dart';
import '../../core/layout/ui_platform.dart';
import '../../core/models/models.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/page_form_scaffold.dart';



class AdminScreen extends ConsumerStatefulWidget {

  const AdminScreen({super.key});



  @override

  ConsumerState<AdminScreen> createState() => _AdminScreenState();

}



class _AdminScreenState extends ConsumerState<AdminScreen> {

  Map<String, dynamic>? _stats;

  List<dynamic> _users = [];

  List<AdminSellerModel> _pendingSellers = [];

  List<SellerOrderItemModel> _orderItems = [];

  String _resetMode = 'seed';

  String? _message;

  Timer? _pollTimer;

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

    try {

      await ref.read(apiClientProvider).adminUpdateOrderStatus(item.id, next);

      await _loadOrders(silent: true);

    } on ApiException catch (e) {

      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));

      }

    }

  }



  Future<void> _reset() async {

    try {

      final res = await ref.read(apiClientProvider).adminDbReset(_resetMode);

      setState(() => _message = res['message'] as String? ?? '완료');

    } catch (e) {

      setState(() => _message = e.toString());

    }

  }



  Future<void> _approveSeller(String sellerId) async {

    await ref.read(apiClientProvider).adminApproveSeller(sellerId);

    await _load();

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

              onPressed: () => _approveSeller(s.id),

              child: const Text('승인'),

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

                      onPressed: () => _advanceOrder(item),

                      child: Text(nextFulfillmentActionLabel(item.fulfillmentStatus)),

                    ),

            ),

          ),

        ),

      const Divider(),

      const Text('DB 초기화'),

      DropdownButton<String>(

        value: _resetMode,

        items: const [

          DropdownMenuItem(value: 'seed', child: Text('시드만')),

          DropdownMenuItem(value: 'truncate_except_users', child: Text('사용자 제외 초기화')),

          DropdownMenuItem(value: 'truncate_all', child: Text('전체 초기화')),

        ],

        onChanged: (v) => setState(() => _resetMode = v ?? 'seed'),

      ),

      FilledButton(onPressed: _reset, child: const Text('DB 초기화 실행')),

      if (_message != null) Text(_message!),

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

                icon: const Icon(Icons.star),

                onPressed: () => ref.read(apiClientProvider).adminPromote(u['id'] as String),

              ),

              IconButton(

                icon: const Icon(Icons.monetization_on),

                onPressed: () =>

                    ref.read(apiClientProvider).adminGrantCredits(u['id'] as String, 100),

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


