import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_mall/core/models/models.dart';
import 'package:shopping_mall/core/network/api_client.dart';
import 'package:shopping_mall/core/providers/app_providers.dart';
import 'package:shopping_mall/features/admin/admin_dashboard.dart';

class _AdminApi extends ApiClient {
  _AdminApi() : super(tokenReader: () async => 'tok');

  int statsCalls = 0;
  int usersCalls = 0;
  int sellersCalls = 0;
  int ordersCalls = 0;
  int draftsCalls = 0;
  int approveCalls = 0;
  Completer<void>? approveBlock;

  @override
  Future<Map<String, dynamic>> adminStats() async {
    statsCalls += 1;
    return {
      'userCount': 1,
      'productCount': 1,
      'orderCount': 1,
      'sellerCount': 1,
      'pendingSellerCount': 1,
    };
  }

  @override
  Future<Map<String, dynamic>> adminUsers({String? q}) async {
    usersCalls += 1;
    return {
      'items': [
        {
          'id': 'u1',
          'email': 'buyer@mall.local',
          'displayName': '구매자',
          'isAdmin': false,
        },
      ],
    };
  }

  @override
  Future<List<AdminSellerModel>> adminSellers({String? status}) async {
    sellersCalls += 1;
    return [
      AdminSellerModel(
        id: 's1',
        shopName: '입점마트',
        userEmail: 'shop@mall.local',
        status: 'pending',
        sellerType: 'merchant',
      ),
    ];
  }

  @override
  Future<List<SellerOrderItemModel>> adminOrders() async {
    ordersCalls += 1;
    return const [];
  }

  @override
  Future<List<IntakeDraftModel>> adminCatalogDrafts() async {
    draftsCalls += 1;
    return const [];
  }

  @override
  Future<void> adminApproveSeller(String sellerId) async {
    approveCalls += 1;
    if (approveBlock != null) await approveBlock!.future;
  }
}

void main() {
  test('admin sellers section does not fetch users drafts or orders', () async {
    final api = _AdminApi();
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await container
        .read(adminDashboardProvider.notifier)
        .ensureSection(AdminSection.sellers);

    expect(api.sellersCalls, 1);
    expect(api.statsCalls, 0);
    expect(api.usersCalls, 0);
    expect(api.draftsCalls, 0);
    expect(api.ordersCalls, 0);
    expect(
      container.read(adminDashboardProvider).pendingSellers,
      hasLength(1),
    );
  });

  test('admin section remount reuses loaded sellers without refetch', () async {
    final api = _AdminApi();
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final dash = container.read(adminDashboardProvider.notifier);

    await dash.ensureSection(AdminSection.sellers);
    await dash.ensureSection(AdminSection.users);
    await dash.ensureSection(AdminSection.sellers);

    expect(api.sellersCalls, 1);
    expect(api.usersCalls, 1);
    expect(api.statsCalls, 0);
  });

  test('admin user search hits users only', () async {
    final api = _AdminApi();
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final dash = container.read(adminDashboardProvider.notifier);

    await dash.ensureSection(AdminSection.users);
    expect(api.usersCalls, 1);
    await dash.loadUsers(force: true, q: 'buyer');
    expect(api.usersCalls, 2);
    expect(api.statsCalls, 0);
    expect(api.sellersCalls, 0);
  });

  test('admin approve removes the row before PATCH returns', () async {
    final api = _AdminApi();
    api.approveBlock = Completer<void>();
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final dash = container.read(adminDashboardProvider.notifier);
    await dash.ensureSection(AdminSection.sellers);
    expect(container.read(adminDashboardProvider).pendingSellers, hasLength(1));

    final pending = dash.approveSeller('s1');
    await Future<void>.delayed(Duration.zero);
    expect(container.read(adminDashboardProvider).pendingSellers, isEmpty);
    expect(api.approveBlock!.isCompleted, isFalse);

    api.approveBlock!.complete();
    await pending;
    expect(api.approveCalls, 1);
  });
}
