import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/fulfillment/fulfillment_labels.dart';
import '../../core/models/models.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';

enum AdminSection { home, stats, sellers, orders, catalog, users, tools }

class AdminDashboardState {
  const AdminDashboardState({
    this.stats,
    this.users = const [],
    this.pendingSellers = const [],
    this.orderItems = const [],
    this.catalogDrafts = const [],
    this.statsLoading = false,
    this.usersLoading = false,
    this.sellersLoading = false,
    this.ordersLoading = false,
    this.draftsLoading = false,
    this.statsLoaded = false,
    this.usersLoaded = false,
    this.sellersLoaded = false,
    this.ordersLoaded = false,
    this.draftsLoaded = false,
    this.userQuery = '',
    this.adminDraft = const {},
  });

  final Map<String, dynamic>? stats;
  final List<dynamic> users;
  final List<AdminSellerModel> pendingSellers;
  final List<SellerOrderItemModel> orderItems;
  final List<IntakeDraftModel> catalogDrafts;
  final bool statsLoading;
  final bool usersLoading;
  final bool sellersLoading;
  final bool ordersLoading;
  final bool draftsLoading;
  final bool statsLoaded;
  final bool usersLoaded;
  final bool sellersLoaded;
  final bool ordersLoaded;
  final bool draftsLoaded;
  final String userQuery;
  final Map<String, bool> adminDraft;

  AdminDashboardState copyWith({
    Map<String, dynamic>? stats,
    List<dynamic>? users,
    List<AdminSellerModel>? pendingSellers,
    List<SellerOrderItemModel>? orderItems,
    List<IntakeDraftModel>? catalogDrafts,
    bool? statsLoading,
    bool? usersLoading,
    bool? sellersLoading,
    bool? ordersLoading,
    bool? draftsLoading,
    bool? statsLoaded,
    bool? usersLoaded,
    bool? sellersLoaded,
    bool? ordersLoaded,
    bool? draftsLoaded,
    String? userQuery,
    Map<String, bool>? adminDraft,
    bool clearStats = false,
  }) {
    return AdminDashboardState(
      stats: clearStats ? null : (stats ?? this.stats),
      users: users ?? this.users,
      pendingSellers: pendingSellers ?? this.pendingSellers,
      orderItems: orderItems ?? this.orderItems,
      catalogDrafts: catalogDrafts ?? this.catalogDrafts,
      statsLoading: statsLoading ?? this.statsLoading,
      usersLoading: usersLoading ?? this.usersLoading,
      sellersLoading: sellersLoading ?? this.sellersLoading,
      ordersLoading: ordersLoading ?? this.ordersLoading,
      draftsLoading: draftsLoading ?? this.draftsLoading,
      statsLoaded: statsLoaded ?? this.statsLoaded,
      usersLoaded: usersLoaded ?? this.usersLoaded,
      sellersLoaded: sellersLoaded ?? this.sellersLoaded,
      ordersLoaded: ordersLoaded ?? this.ordersLoaded,
      draftsLoaded: draftsLoaded ?? this.draftsLoaded,
      userQuery: userQuery ?? this.userQuery,
      adminDraft: adminDraft ?? this.adminDraft,
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
      AdminSection.catalog => loadDrafts(),
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
      final pending = await _api.adminSellers(status: 'pending');
      state = state.copyWith(
        pendingSellers: pending,
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
        adminDraft: {
          for (final user in items)
            if (user is Map)
              user['id'] as String: user['isAdmin'] == true,
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

  void setAdminDraft(String userId, bool isAdmin) {
    state = state.copyWith(
      adminDraft: {...state.adminDraft, userId: isAdmin},
    );
  }

  Future<void> approveSeller(String sellerId) async {
    final previous = state.pendingSellers;
    final previousStats = state.stats;
    state = state.copyWith(
      pendingSellers: [
        for (final seller in previous)
          if (seller.id != sellerId) seller,
      ],
      stats: _bumpPendingCount(previousStats, -1),
    );
    try {
      await _api.adminApproveSeller(sellerId);
    } catch (_) {
      state = state.copyWith(
        pendingSellers: previous,
        stats: previousStats,
      );
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
    final isAdmin = state.adminDraft[userId] ?? false;
    await _api.adminUpdateUser(userId, isAdmin: isAdmin);
    state = state.copyWith(
      users: [
        for (final user in state.users)
          if (user is Map && user['id'] == userId)
            {...Map<String, dynamic>.from(user), 'isAdmin': isAdmin}
          else
            user,
      ],
    );
  }

  Future<void> deleteUser(String userId) async {
    final previousUsers = state.users;
    final previousDraft = state.adminDraft;
    state = state.copyWith(
      users: [
        for (final user in previousUsers)
          if (user is! Map || user['id'] != userId) user,
      ],
      adminDraft: {
        for (final entry in previousDraft.entries)
          if (entry.key != userId) entry.key: entry.value,
      },
    );
    try {
      await _api.adminDeleteUser(userId);
    } catch (_) {
      state = state.copyWith(users: previousUsers, adminDraft: previousDraft);
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
