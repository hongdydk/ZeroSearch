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
          'sellerName': null,
          'isBuyer': true,
          'isSeller': false,
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

  int catalogItemCalls = 0;
  int lastCatalogOffset = 0;
  String? lastCatalogQuery;
  String? lastCatalogL1Tag;
  bool lastIncludeRetired = false;
  List<AdminCatalogProductModel> catalogItems = const [];
  int catalogTotal = 0;

  @override
  Future<AdminCatalogProductPageModel> adminCatalogProducts({
    String? q,
    bool includeRetired = false,
    String? l1Tag,
    int offset = 0,
    int limit = 24,
  }) async {
    catalogItemCalls += 1;
    lastCatalogOffset = offset;
    lastCatalogQuery = q;
    lastCatalogL1Tag = l1Tag;
    lastIncludeRetired = includeRetired;
    return AdminCatalogProductPageModel(
      items: catalogItems,
      total: catalogTotal,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<void> adminApproveSeller(String sellerId) async {
    approveCalls += 1;
    if (approveBlock != null) await approveBlock!.future;
  }

  Map<String, dynamic>? lastUserUpdate;

  @override
  Future<void> adminUpdateUser(
    String userId, {
    required bool isAdmin,
    bool? isBuyer,
    bool? isSeller,
    String? displayName,
    String? sellerName,
  }) async {
    lastUserUpdate = {
      'id': userId,
      'isAdmin': isAdmin,
      'isBuyer': isBuyer,
      'isSeller': isSeller,
      'displayName': displayName,
      'sellerName': sellerName,
    };
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

  test('admin catalog section loads drafts and catalog items', () async {
    final api = _AdminApi();
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await container
        .read(adminDashboardProvider.notifier)
        .ensureSection(AdminSection.catalog);

    expect(api.draftsCalls, 1);
    expect(api.catalogItemCalls, 1);
    expect(api.sellersCalls, 0);
  });

  test('admin saveUser sends split names and all roles', () async {
    final api = _AdminApi();
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final dash = container.read(adminDashboardProvider.notifier);

    await dash.ensureSection(AdminSection.users);
    dash.setUserDraft(
      'u1',
      const AdminUserRowDraft(
        buyerName: '구매이름',
        sellerName: '청정마트',
        isBuyer: true,
        isSeller: true,
        isAdmin: true,
      ),
    );
    await dash.saveUser('u1');

    expect(api.lastUserUpdate, {
      'id': 'u1',
      'isAdmin': true,
      'isBuyer': true,
      'isSeller': true,
      'displayName': '구매이름',
      'sellerName': '청정마트',
    });
  });

  test('admin catalog pagination requests next offset and keeps query', () async {
    final api = _AdminApi();
    api.catalogTotal = 80;
    api.catalogItems = [
      AdminCatalogProductModel(
        id: 'c1',
        title: '백산수',
        manufacturer: '농심',
        category: '생수',
        status: 'active',
        offerCount: 2,
        publishedOfferCount: 2,
        shopCount: 2,
      ),
    ];
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final dash = container.read(adminDashboardProvider.notifier);

    await dash.ensureSection(AdminSection.catalog);
    expect(api.catalogItemCalls, 1);
    expect(api.lastCatalogOffset, 0);
    expect(container.read(adminDashboardProvider).catalogTotal, 80);

    await dash.loadCatalogItems(force: true, q: '백산', offset: 24);
    expect(api.catalogItemCalls, 2);
    expect(api.lastCatalogOffset, 24);
    expect(api.lastCatalogQuery, '백산');
    expect(container.read(adminDashboardProvider).catalogOffset, 24);
  });
}
