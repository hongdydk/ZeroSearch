import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/fulfillment/fulfillment_labels.dart';
import '../../core/models/models.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';

enum AdminSection { home, stats, sellers, orders, catalog, users, tools }

class AdminUserRowDraft {
  const AdminUserRowDraft({
    this.buyerName = '',
    this.sellerName = '',
    this.isBuyer = true,
    this.isSeller = false,
    this.isAdmin = false,
  });

  final String buyerName;
  final String sellerName;
  final bool isBuyer;
  final bool isSeller;
  final bool isAdmin;

  AdminUserRowDraft copyWith({
    String? buyerName,
    String? sellerName,
    bool? isBuyer,
    bool? isSeller,
    bool? isAdmin,
  }) {
    return AdminUserRowDraft(
      buyerName: buyerName ?? this.buyerName,
      sellerName: sellerName ?? this.sellerName,
      isBuyer: isBuyer ?? this.isBuyer,
      isSeller: isSeller ?? this.isSeller,
      isAdmin: isAdmin ?? this.isAdmin,
    );
  }
}

AdminUserRowDraft adminUserDraftFromMap(Map<String, dynamic> user) {
  final status = user['sellerStatus'] as String?;
  final isSeller =
      user['isSeller'] == true || (status != null && status != 'removed');
  return AdminUserRowDraft(
    buyerName: user['displayName'] as String? ?? '',
    sellerName: user['sellerName'] as String? ?? '',
    isBuyer: user['isBuyer'] != false,
    isSeller: isSeller,
    isAdmin: user['isAdmin'] == true,
  );
}

class AdminDashboardState {
  const AdminDashboardState({
    this.stats,
    this.users = const [],
    this.pendingSellers = const [],
    this.sellers = const [],
    this.orderItems = const [],
    this.catalogDrafts = const [],
    this.catalogItems = const [],
    this.statsLoading = false,
    this.usersLoading = false,
    this.sellersLoading = false,
    this.ordersLoading = false,
    this.draftsLoading = false,
    this.catalogItemsLoading = false,
    this.statsLoaded = false,
    this.usersLoaded = false,
    this.sellersLoaded = false,
    this.ordersLoaded = false,
    this.draftsLoaded = false,
    this.catalogItemsLoaded = false,
    this.userQuery = '',
    this.userDrafts = const {},
  });

  final Map<String, dynamic>? stats;
  final List<dynamic> users;
  final List<AdminSellerModel> pendingSellers;
  final List<AdminSellerModel> sellers;
  final List<SellerOrderItemModel> orderItems;
  final List<IntakeDraftModel> catalogDrafts;
  final List<AdminCatalogProductModel> catalogItems;
  final bool statsLoading;
  final bool usersLoading;
  final bool sellersLoading;
  final bool ordersLoading;
  final bool draftsLoading;
  final bool catalogItemsLoading;
  final bool statsLoaded;
  final bool usersLoaded;
  final bool sellersLoaded;
  final bool ordersLoaded;
  final bool draftsLoaded;
  final bool catalogItemsLoaded;
  final String userQuery;
  final Map<String, AdminUserRowDraft> userDrafts;

  AdminDashboardState copyWith({
    Map<String, dynamic>? stats,
    List<dynamic>? users,
    List<AdminSellerModel>? pendingSellers,
    List<AdminSellerModel>? sellers,
    List<SellerOrderItemModel>? orderItems,
    List<IntakeDraftModel>? catalogDrafts,
    List<AdminCatalogProductModel>? catalogItems,
    bool? statsLoading,
    bool? usersLoading,
    bool? sellersLoading,
    bool? ordersLoading,
    bool? draftsLoading,
    bool? catalogItemsLoading,
    bool? statsLoaded,
    bool? usersLoaded,
    bool? sellersLoaded,
    bool? ordersLoaded,
    bool? draftsLoaded,
    bool? catalogItemsLoaded,
    String? userQuery,
    Map<String, AdminUserRowDraft>? userDrafts,
    bool clearStats = false,
  }) {
    return AdminDashboardState(
      stats: clearStats ? null : (stats ?? this.stats),
      users: users ?? this.users,
      pendingSellers: pendingSellers ?? this.pendingSellers,
      sellers: sellers ?? this.sellers,
      orderItems: orderItems ?? this.orderItems,
      catalogDrafts: catalogDrafts ?? this.catalogDrafts,
      catalogItems: catalogItems ?? this.catalogItems,
      statsLoading: statsLoading ?? this.statsLoading,
      usersLoading: usersLoading ?? this.usersLoading,
      sellersLoading: sellersLoading ?? this.sellersLoading,
      ordersLoading: ordersLoading ?? this.ordersLoading,
      draftsLoading: draftsLoading ?? this.draftsLoading,
      catalogItemsLoading: catalogItemsLoading ?? this.catalogItemsLoading,
      statsLoaded: statsLoaded ?? this.statsLoaded,
      usersLoaded: usersLoaded ?? this.usersLoaded,
      sellersLoaded: sellersLoaded ?? this.sellersLoaded,
      ordersLoaded: ordersLoaded ?? this.ordersLoaded,
      draftsLoaded: draftsLoaded ?? this.draftsLoaded,
      catalogItemsLoaded: catalogItemsLoaded ?? this.catalogItemsLoaded,
      userQuery: userQuery ?? this.userQuery,
      userDrafts: userDrafts ?? this.userDrafts,
    );
  }
}

class AdminDashboardNotifier extends Notifier<AdminDashboardState> {
  final _orderInFlight = <String>{};
  Timer? _userSearchTimer;

  ApiClient get _api => ref.read(apiClientProvider);

  @override
  AdminDashboardState build() {
    ref.onDispose(() => _userSearchTimer?.cancel());
    return const AdminDashboardState();
  }

  Future<void> ensureSection(AdminSection? section) {
    return switch (section ?? AdminSection.home) {
      AdminSection.home => Future.wait([loadStats(), loadSellers()]),
      AdminSection.stats => loadStats(),
      AdminSection.sellers => loadSellers(),
      AdminSection.orders => loadOrders(),
      AdminSection.catalog => Future.wait([loadDrafts(), loadCatalogItems()]),
      AdminSection.users => loadUsers(),
      AdminSection.tools => Future.value(),
    };
  }

  Future<void> reloadAll() {
    return Future.wait([
      loadStats(force: true),
      loadSellers(force: true),
      loadOrders(force: true),
      loadDrafts(force: true),
      loadCatalogItems(force: true),
      loadUsers(force: true),
    ]);
  }

  Future<void> loadStats({bool force = false}) async {
    if (state.statsLoaded && !force) return;
    state = state.copyWith(statsLoading: !state.statsLoaded);
    try {
      final stats = await _api.adminStats();
      state = state.copyWith(
        stats: stats,
        statsLoading: false,
        statsLoaded: true,
      );
    } catch (_) {
      state = state.copyWith(statsLoading: false, statsLoaded: true);
    }
  }

  Future<void> loadSellers({bool force = false}) async {
    if (state.sellersLoaded && !force) return;
    state = state.copyWith(sellersLoading: !state.sellersLoaded);
    try {
      final all = await _api.adminSellers();
      state = state.copyWith(
        sellers: all,
        pendingSellers: [
          for (final seller in all)
            if (seller.status == 'pending') seller,
        ],
        sellersLoading: false,
        sellersLoaded: true,
      );
    } catch (_) {
      state = state.copyWith(sellersLoading: false, sellersLoaded: true);
    }
  }

  Future<void> loadOrders({bool force = false, bool silent = false}) async {
    if (_orderInFlight.isNotEmpty) return;
    if (state.ordersLoaded && !force && !silent) return;
    if (!silent && !state.ordersLoaded) {
      state = state.copyWith(ordersLoading: true);
    }
    try {
      final items = await _api.adminOrders();
      state = state.copyWith(
        orderItems: items,
        ordersLoading: false,
        ordersLoaded: true,
      );
    } catch (_) {
      state = state.copyWith(ordersLoading: false, ordersLoaded: true);
    }
  }

  Future<void> loadDrafts({bool force = false}) async {
    if (state.draftsLoaded && !force) return;
    state = state.copyWith(draftsLoading: !state.draftsLoaded);
    try {
      final drafts = await _api.adminCatalogDrafts();
      state = state.copyWith(
        catalogDrafts: drafts,
        draftsLoading: false,
        draftsLoaded: true,
      );
    } catch (_) {
      state = state.copyWith(draftsLoading: false, draftsLoaded: true);
    }
  }

  Future<void> loadCatalogItems({bool force = false, String? q}) async {
    if (state.catalogItemsLoaded && !force && q == null) return;
    state = state.copyWith(catalogItemsLoading: !state.catalogItemsLoaded);
    try {
      final items = await _api.adminCatalogProducts(q: q);
      state = state.copyWith(
        catalogItems: items,
        catalogItemsLoading: false,
        catalogItemsLoaded: true,
      );
    } catch (_) {
      state = state.copyWith(
        catalogItemsLoading: false,
        catalogItemsLoaded: true,
      );
    }
  }

  Future<void> loadUsers({bool force = false, String? q}) async {
    final query = q ?? state.userQuery;
    if (state.usersLoaded && !force && q == null) return;
    state = state.copyWith(
      usersLoading: true,
      userQuery: query,
    );
    try {
      final users = await _api.adminUsers(q: query);
      final items = users['items'] as List<dynamic>? ?? [];
      state = state.copyWith(
        users: items,
        usersLoading: false,
        usersLoaded: true,
        userDrafts: {
          for (final user in items)
            if (user is Map)
              user['id'] as String: adminUserDraftFromMap(
                Map<String, dynamic>.from(user),
              ),
        },
      );
    } catch (_) {
      state = state.copyWith(usersLoading: false, usersLoaded: true);
    }
  }

  void searchUsers(String query) {
    _userSearchTimer?.cancel();
    _userSearchTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(loadUsers(force: true, q: query.trim()));
    });
  }

  void setUserDraft(String userId, AdminUserRowDraft draft) {
    state = state.copyWith(
      userDrafts: {...state.userDrafts, userId: draft},
    );
  }

  Future<void> approveSeller(String sellerId) async {
    final previousPending = state.pendingSellers;
    final previousSellers = state.sellers;
    final previousStats = state.stats;
    state = state.copyWith(
      pendingSellers: [
        for (final seller in previousPending)
          if (seller.id != sellerId) seller,
      ],
      sellers: [
        for (final seller in previousSellers)
          if (seller.id == sellerId)
            seller.copyWith(status: 'active')
          else
            seller,
      ],
      stats: _bumpPendingCount(previousStats, -1),
    );
    try {
      await _api.adminApproveSeller(sellerId);
    } catch (_) {
      state = state.copyWith(
        pendingSellers: previousPending,
        sellers: previousSellers,
        stats: previousStats,
      );
      rethrow;
    }
  }

  Future<void> applySellerModeration(
    String sellerId,
    Future<AdminSellerModel> Function(String id, String reason) request, {
    required String reason,
  }) async {
    final previous = state.sellers;
    final previousPending = state.pendingSellers;
    try {
      final updated = await request(sellerId, reason);
      state = state.copyWith(
        sellers: [
          for (final seller in previous)
            if (seller.id == sellerId) updated else seller,
        ],
        pendingSellers: [
          for (final seller in previousPending)
            if (seller.id != sellerId) seller,
        ],
      );
    } catch (_) {
      state = state.copyWith(sellers: previous, pendingSellers: previousPending);
      rethrow;
    }
  }

  Future<void> warnSeller(String sellerId, String reason) {
    return applySellerModeration(sellerId, _api.adminWarnSeller, reason: reason);
  }

  Future<void> suspendSeller(String sellerId, String reason) {
    return applySellerModeration(
      sellerId,
      _api.adminSuspendSeller,
      reason: reason,
    );
  }

  Future<void> unsuspendSeller(String sellerId, String reason) {
    return applySellerModeration(
      sellerId,
      _api.adminUnsuspendSeller,
      reason: reason,
    );
  }

  Future<void> removeSeller(String sellerId, String reason) {
    return applySellerModeration(
      sellerId,
      _api.adminRemoveSeller,
      reason: reason,
    );
  }

  Future<void> addCatalogItem({
    required String manufacturer,
    required String title,
    required String category,
    String? description,
  }) async {
    final created = await _api.adminCreateCatalogProduct(
      manufacturer: manufacturer,
      title: title,
      category: category,
      description: description,
    );
    state = state.copyWith(catalogItems: [created, ...state.catalogItems]);
  }

  Future<void> deleteCatalogItem(String id) async {
    final previous = state.catalogItems;
    state = state.copyWith(
      catalogItems: [
        for (final item in previous)
          if (item.id != id) item,
      ],
    );
    try {
      await _api.adminDeleteCatalogProduct(id);
    } catch (_) {
      state = state.copyWith(catalogItems: previous);
      rethrow;
    }
  }

  Future<void> advanceOrder(SellerOrderItemModel item) async {
    final next = nextFulfillmentStatus(item.fulfillmentStatus);
    if (next == null || _orderInFlight.contains(item.id)) return;
    _orderInFlight.add(item.id);
    state = state.copyWith(
      orderItems: [
        for (final row in state.orderItems)
          if (row.id == item.id)
            row.copyWith(fulfillmentStatus: next)
          else
            row,
      ],
    );
    try {
      await _api.adminUpdateOrderStatus(item.id, next);
    } catch (_) {
      state = state.copyWith(
        orderItems: [
          for (final row in state.orderItems)
            if (row.id == item.id) item else row,
        ],
      );
      rethrow;
    } finally {
      _orderInFlight.remove(item.id);
    }
  }

  Future<void> removeDraft(String draftId) async {
    state = state.copyWith(
      catalogDrafts: [
        for (final draft in state.catalogDrafts)
          if (draft.id != draftId) draft,
      ],
    );
  }

  Future<void> restoreDraft(IntakeDraftModel draft) async {
    if (state.catalogDrafts.any((item) => item.id == draft.id)) return;
    state = state.copyWith(catalogDrafts: [draft, ...state.catalogDrafts]);
  }

  Future<void> saveUser(String userId) async {
    final draft = state.userDrafts[userId] ?? const AdminUserRowDraft();
    await _api.adminUpdateUser(
      userId,
      isAdmin: draft.isAdmin,
      isBuyer: draft.isBuyer,
      isSeller: draft.isSeller,
      displayName: draft.buyerName,
      sellerName: draft.sellerName,
    );
    state = state.copyWith(
      users: [
        for (final user in state.users)
          if (user is Map && user['id'] == userId)
            {
              ...Map<String, dynamic>.from(user),
              'displayName': draft.buyerName,
              'sellerName': draft.sellerName,
              'isBuyer': draft.isBuyer,
              'isSeller': draft.isSeller,
              'isAdmin': draft.isAdmin,
            }
          else
            user,
      ],
    );
  }

  Future<void> deleteUser(String userId) async {
    final previousUsers = state.users;
    final previousDraft = state.userDrafts;
    state = state.copyWith(
      users: [
        for (final user in previousUsers)
          if (user is! Map || user['id'] != userId) user,
      ],
      userDrafts: {
        for (final entry in previousDraft.entries)
          if (entry.key != userId) entry.key: entry.value,
      },
    );
    try {
      await _api.adminDeleteUser(userId);
    } catch (_) {
      state = state.copyWith(users: previousUsers, userDrafts: previousDraft);
      rethrow;
    }
  }

  Map<String, dynamic>? _bumpPendingCount(
    Map<String, dynamic>? stats,
    int delta,
  ) {
    if (stats == null) return stats;
    final next = Map<String, dynamic>.from(stats);
    final current = next['pendingSellerCount'] as int? ?? 0;
    next['pendingSellerCount'] = (current + delta).clamp(0, 1 << 30);
    return next;
  }
}

final adminDashboardProvider =
    NotifierProvider<AdminDashboardNotifier, AdminDashboardState>(
  AdminDashboardNotifier.new,
);
