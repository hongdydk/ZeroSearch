import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/login_portal.dart';
import '../cart/guest_cart.dart';
import '../models/models.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import '../storage/token_storage.dart';

/// 홈 카탈로그 검색어 — 웹 헤더·카탈로그 화면 공유 (즉시 반영).
final catalogSearchProvider = StateProvider<String>((ref) => '');

/// Fetch·URL 커밋용 검색어 (debounce 후).
final catalogDebouncedSearchProvider = StateProvider<String>((ref) => '');

/// 랜딩·중분류 ListView 스크롤 복원.
final catalogLandingScrollOffsetProvider = StateProvider<double>((ref) => 0);
final catalogMidScrollOffsetProvider = StateProvider<double>((ref) => 0);

/// 카드 그리드 스크롤 복원 (필터·검색 조합별).
final catalogGridScrollOffsetProvider = StateProvider<double>((ref) => 0);

/// 식탁 대분류 (AI-Hub). 제품 유무와 무관.
final catalogMajorProvider = StateProvider<String?>((ref) => null);

/// 식탁 중분류.
final catalogMidProvider = StateProvider<String?>((ref) => null);

/// 소분류(대표 상품 category) — 목록 세부 필터.
final catalogCategoryProvider = StateProvider<String?>((ref) => null);

/// 게스트 1차 태그 (손님 브라우즈 입구).
final catalogL1Provider = StateProvider<String?>((ref) => null);

/// `brand` | `menu`
final catalogL1AxisProvider = StateProvider<String?>((ref) => null);

final catalogL1BrandProvider = StateProvider<String?>((ref) => null);
final catalogL1MenuProvider = StateProvider<String?>((ref) => null);
final catalogStorageFilterProvider = StateProvider<String?>((ref) => null);
final catalogL1AllProvider = StateProvider<bool>((ref) => false);
final catalogL1AxisScrollOffsetProvider = StateProvider<double>((ref) => 0);

/// 맛·용량 옵션 필터 — catalog_screen 본문 전용.
final catalogFlavorFilterProvider = StateProvider<String?>((ref) => null);
final catalogVolumeMinFilterProvider = StateProvider<int?>((ref) => null);
final catalogVolumeMaxFilterProvider = StateProvider<int?>((ref) => null);

final apiClientProvider = Provider<ApiClient>((ref) {
  final tokens = ref.watch(tokenStorageProvider);
  return ApiClient(tokenReader: () => tokens.readActiveToken());
});

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final guestCartStorageProvider =
    Provider<GuestCartStorage>((ref) => GuestCartStorage());

final authStateProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<AuthState>>((ref) {
  return AuthNotifier(
    ref.watch(apiClientProvider),
    ref.watch(tokenStorageProvider),
  );
});

class PortalSession {
  const PortalSession({required this.token, required this.user});

  final String token;
  final UserModel user;
}

class AuthState {
  const AuthState({
    this.active = LoginPortal.buyer,
    this.buyer,
    this.seller,
    this.admin,
  });

  final LoginPortal active;
  final PortalSession? buyer;
  final PortalSession? seller;
  final PortalSession? admin;

  PortalSession? session(LoginPortal portal) => switch (portal) {
        LoginPortal.buyer => buyer,
        LoginPortal.seller => seller,
        LoginPortal.admin => admin,
      };

  UserModel? get user => session(active)?.user;
  String? get token => session(active)?.token;
  LoginPortal get portal => active;

  bool get isLoggedIn => token != null && token!.isNotEmpty;

  /// 몰 헤더·장바구니·결제는 구매자 슬롯만 본다.
  bool get isMallBuyer => buyer != null;

  bool isPortal(LoginPortal value) => session(value) != null;

  /// 포털 입장은 그 포털에 저장된 JWT만. 구매자 `isAdmin`으로 /admin에 타지 않는다.
  bool canAccess(LoginPortal required) => isPortal(required);

  AuthState withActive(LoginPortal portal) => AuthState(
        active: portal,
        buyer: buyer,
        seller: seller,
        admin: admin,
      );

  AuthState withSession(LoginPortal portal, PortalSession? value) => AuthState(
        active: active,
        buyer: portal == LoginPortal.buyer ? value : buyer,
        seller: portal == LoginPortal.seller ? value : seller,
        admin: portal == LoginPortal.admin ? value : admin,
      );
}

class AuthNotifier extends StateNotifier<AsyncValue<AuthState>> {
  AuthNotifier(
    this._api,
    this._tokens, {
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now,
        super(const AsyncValue.loading()) {
    _bootstrap();
  }

  final ApiClient _api;
  final TokenStorage _tokens;
  final DateTime Function() _clock;

  Future<void> _bootstrap() async {
    await _tokens.loadLeftAts();
    var next = const AuthState();
    for (final portal in LoginPortal.values) {
      final slot = await _restore(portal);
      if (slot != null) {
        next = next.withSession(portal, slot);
      }
    }
    _tokens.activePortal = LoginPortal.buyer;
    state = AsyncValue.data(next);
  }

  Future<PortalSession?> _restore(LoginPortal portal) async {
    if (_tokens.isPortalAwayExpired(portal, _clock())) {
      await _tokens.clearPortal(portal);
      return null;
    }
    final token = await _tokens.readPortalToken(portal);
    if (token == null || token.isEmpty) return null;
    _tokens.activePortal = portal;
    try {
      final user = await _api.me();
      return PortalSession(token: token, user: user);
    } catch (_) {
      await _tokens.clearPortal(portal);
      return null;
    }
  }

  void setActive(LoginPortal portal) {
    final current = state.valueOrNull;
    final previous = current?.active;
    if (previous != null && previous != portal) {
      if (TokenStorage.usesAwaySessionTtl(previous)) {
        unawaited(_tokens.markPortalLeft(previous, _clock()));
      }
    }

    if (current == null || current.active == portal) {
      _tokens.activePortal = portal;
      return;
    }

    if (_tokens.isPortalAwayExpired(portal, _clock())) {
      unawaited(_tokens.clearPortal(portal));
      _tokens.activePortal = portal;
      state = AsyncValue.data(
        current.withSession(portal, null).withActive(portal),
      );
      return;
    }

    if (TokenStorage.usesAwaySessionTtl(portal)) {
      unawaited(_tokens.clearPortalLeft(portal));
    }
    _tokens.activePortal = portal;
    state = AsyncValue.data(current.withActive(portal));
  }

  Future<void> login(
    String email,
    String password, {
    LoginPortal portal = LoginPortal.buyer,
  }) async {
    // 전역 loading/error로 바꾸면 PortalAuthGate가 로그인 폼을 내려 403 문구가 사라진다.
    final token = await _api.login(email, password, portal: portal);
    await _tokens.writePortalToken(portal, token);
    await _tokens.clearPortalLeft(portal);
    _tokens.activePortal = portal;
    final user = await _api.me();
    final current = state.valueOrNull ?? const AuthState();
    state = AsyncValue.data(
      current
          .withSession(portal, PortalSession(token: token, user: user))
          .withActive(portal),
    );
  }

  Future<void> register(
    String email,
    String password, {
    String? displayName,
    LoginPortal portal = LoginPortal.buyer,
  }) async {
    state = const AsyncValue.loading();
    try {
      final token =
          await _api.register(email, password, displayName: displayName);
      await _tokens.writePortalToken(portal, token);
      _tokens.activePortal = portal;
      final user = await _api.me();
      state = AsyncValue.data(
        const AuthState()
            .withSession(portal, PortalSession(token: token, user: user))
            .withActive(portal),
      );
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> logout([LoginPortal? portal]) async {
    final current = state.valueOrNull ?? const AuthState();
    final target = portal ?? current.active;
    await _tokens.clearPortal(target);
    state = AsyncValue.data(current.withSession(target, null));
  }

  Future<void> refreshUser() async {
    final current = state.valueOrNull;
    final token = current?.token;
    if (current == null || token == null) return;
    _tokens.activePortal = current.active;
    final user = await _api.me();
    state = AsyncValue.data(
      current.withSession(
        current.active,
        PortalSession(token: token, user: user),
      ),
    );
  }
}

final creditsProvider = FutureProvider.autoDispose<int?>((ref) async {
  final auth = ref.watch(authStateProvider).valueOrNull;
  if (auth?.buyer == null) return null;
  return ref.watch(apiClientProvider).credits();
});

final productsProvider = FutureProvider.autoDispose<List<ProductModel>>((ref) async {
  return ref.watch(apiClientProvider).products();
});

/// 구매자 수량 동기 debounce. 테스트에서 `Duration.zero`로 덮어쓴다.
final cartSyncDelayProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 300),
);

/// 백그라운드 카트 동기 실패 메시지. 화면에서 스낵바 후 null로 비운다.
final cartSyncErrorProvider = StateProvider<String?>((ref) => null);

class CartNotifier extends AsyncNotifier<CartModel> {
  final Map<String, Timer> _qtyTimers = {};
  final Map<String, int> _pendingQty = {};
  final Set<String> _pendingRemove = {};
  CartModel? _authoritative;

  bool get _isBuyer =>
      ref.read(authStateProvider).valueOrNull?.isMallBuyer == true;

  GuestCartStorage get _store => ref.read(guestCartStorageProvider);

  ApiClient get _api => ref.read(apiClientProvider);

  @override
  Future<CartModel> build() async {
    ref.onDispose(_cancelTimers);
    final auth = ref.watch(authStateProvider);
    if (auth.isLoading) {
      return CartModel.empty;
    }
    final isBuyer = auth.valueOrNull?.isMallBuyer == true;
    if (!isBuyer) {
      _authoritative = null;
      return cartModelFromGuestLines(await _store.load());
    }
    await mergeGuestCartIntoUser(api: _api, guest: _store);
    final cart = await _api.cart();
    _authoritative = cart;
    return cart;
  }

  /// `/cart` 진입 시 구매자 서버 카트를 한 번 맞춘다. 게스트는 이미 로컬 스냅샷이 있으므로 다시 읽지 않는다.
  Future<void> refreshAuthoritative() async {
    if (!_isBuyer) return;
    try {
      final cart = await _api.cart();
      _authoritative = cart;
      state = AsyncData(_applyPendingOnTop(cart));
    } on ApiException catch (e) {
      _setSyncError(e.message);
    }
  }

  void replaceWith(CartModel cart) {
    _authoritative = cart;
    _pendingQty.clear();
    _pendingRemove.clear();
    _cancelTimers();
    state = AsyncData(cart);
  }

  Future<void> addItem({
    required String productId,
    required String productTitle,
    required int qty,
    required int priceCredits,
    required String sellerId,
    required String shopName,
    required String sellerType,
    int maxQty = 99,
  }) async {
    final incoming = CartItemModel(
      id: productId,
      productId: productId,
      productTitle: productTitle,
      qty: qty.clamp(1, 99),
      priceCredits: priceCredits,
      lineTotalCredits: priceCredits * qty.clamp(1, 99),
      sellerId: sellerId,
      shopName: shopName,
      sellerType: sellerType,
      maxQty: maxQty < 1 ? 99 : maxQty,
    );
    if (!_isBuyer) {
      final current = state.valueOrNull ?? CartModel.empty;
      final next = current.addingOrMerging(incoming);
      state = AsyncData(next);
      unawaited(_persistGuest(next));
      return;
    }
    final current = state.valueOrNull ?? CartModel.empty;
    state = AsyncData(current.addingOrMerging(incoming));
    try {
      final cart = await _api.addToCart(productId, qty: incoming.qty);
      _authoritative = cart;
      state = AsyncData(_applyPendingOnTop(cart));
    } on ApiException catch (e) {
      await _rollbackBuyer(e.message);
      rethrow;
    } catch (_) {
      await _rollbackBuyer('장바구니에 담지 못했습니다.');
      rethrow;
    }
  }

  void updateQty(String productId, int qty) {
    final current = state.valueOrNull;
    if (current == null) return;
    final item = _item(current, productId);
    if (item == null) return;
    final nextQty = qty.clamp(1, item.maxQty < 1 ? 1 : item.maxQty);
    if (nextQty == item.qty) return;
    _pendingRemove.remove(productId);
    state = AsyncData(current.withItemQty(productId, nextQty));
    if (!_isBuyer) {
      unawaited(_persistGuest(state.valueOrNull ?? current));
      return;
    }
    _pendingQty[productId] = nextQty;
    _qtyTimers[productId]?.cancel();
    _qtyTimers[productId] = Timer(ref.read(cartSyncDelayProvider), () {
      unawaited(_flushQty(productId));
    });
  }

  void remove(String productId) {
    final current = state.valueOrNull;
    if (current == null) return;
    if (_item(current, productId) == null) return;
    _qtyTimers.remove(productId)?.cancel();
    _pendingQty.remove(productId);
    state = AsyncData(current.withoutItem(productId));
    if (!_isBuyer) {
      unawaited(_persistGuest(state.valueOrNull ?? CartModel.empty));
      return;
    }
    _pendingRemove.add(productId);
    unawaited(_flushRemove(productId));
  }

  /// 주문서 진입 전 미전송 수량·삭제를 보낸다.
  Future<void> flushPending() async {
    _cancelTimers();
    final qtyIds = _pendingQty.keys.toList();
    for (final id in qtyIds) {
      await _flushQty(id);
    }
    final removes = _pendingRemove.toList();
    for (final id in removes) {
      await _flushRemove(id);
    }
  }

  Future<void> _flushQty(String productId) async {
    final qty = _pendingQty.remove(productId);
    _qtyTimers.remove(productId)?.cancel();
    if (qty == null || _pendingRemove.contains(productId)) return;
    try {
      final cart = await _api.updateCartItem(productId, qty);
      _authoritative = cart;
      state = AsyncData(_applyPendingOnTop(cart));
    } on ApiException catch (e) {
      await _rollbackBuyer(e.message);
    } catch (_) {
      await _rollbackBuyer('장바구니 수량을 저장하지 못했습니다.');
    }
  }

  Future<void> _flushRemove(String productId) async {
    if (!_pendingRemove.contains(productId)) return;
    try {
      final cart = await _api.removeFromCart(productId);
      _pendingRemove.remove(productId);
      _authoritative = cart;
      state = AsyncData(_applyPendingOnTop(cart));
    } on ApiException catch (e) {
      _pendingRemove.remove(productId);
      await _rollbackBuyer(e.message);
    } catch (_) {
      _pendingRemove.remove(productId);
      await _rollbackBuyer('장바구니에서 삭제하지 못했습니다.');
    }
  }

  Future<void> _rollbackBuyer(String message) async {
    _setSyncError(message);
    _pendingQty.clear();
    _pendingRemove.clear();
    _cancelTimers();
    try {
      final cart = await _api.cart();
      _authoritative = cart;
      state = AsyncData(cart);
    } catch (_) {
      final fallback = _authoritative;
      if (fallback != null) {
        state = AsyncData(fallback);
      }
    }
  }

  CartModel _applyPendingOnTop(CartModel base) {
    var next = base;
    for (final id in _pendingRemove) {
      next = next.withoutItem(id);
    }
    for (final entry in _pendingQty.entries) {
      if (_pendingRemove.contains(entry.key)) continue;
      next = next.withItemQty(entry.key, entry.value);
    }
    return next;
  }

  CartItemModel? _item(CartModel cart, String productId) {
    for (final item in cart.items) {
      if (item.productId == productId) return item;
    }
    return null;
  }

  Future<void> _persistGuest(CartModel cart) async {
    await _store.save(guestLinesFromCart(cart));
  }

  void _setSyncError(String message) {
    ref.read(cartSyncErrorProvider.notifier).state = message;
  }

  void _cancelTimers() {
    for (final timer in _qtyTimers.values) {
      timer.cancel();
    }
    _qtyTimers.clear();
  }
}

final cartProvider = AsyncNotifierProvider<CartNotifier, CartModel>(CartNotifier.new);

class CatalogListState {
  const CatalogListState({
    required this.items,
    required this.total,
    this.loadingMore = false,
  });

  final List<CatalogProductModel> items;
  final int total;
  final bool loadingMore;

  bool get hasMore => items.length < total;
}

class CatalogProductsNotifier extends AutoDisposeAsyncNotifier<CatalogListState> {
  @override
  Future<CatalogListState> build() async {
    final q = ref.watch(catalogDebouncedSearchProvider).trim();
    final l1 = ref.watch(catalogL1Provider);
    final brand = ref.watch(catalogL1BrandProvider);
    final menu = ref.watch(catalogL1MenuProvider);
    final storage = ref.watch(catalogStorageFilterProvider);
    final allInL1 = ref.watch(catalogL1AllProvider);
    final major = ref.watch(catalogMajorProvider);
    final mid = ref.watch(catalogMidProvider);
    final category = ref.watch(catalogCategoryProvider);
    final flavor = ref.watch(catalogFlavorFilterProvider);
    final volumeMin = ref.watch(catalogVolumeMinFilterProvider);
    final volumeMax = ref.watch(catalogVolumeMaxFilterProvider);
    final page = await ref.watch(apiClientProvider).catalogProducts(
          q: q.isEmpty ? null : q,
          category: category,
          categoryMajor: major,
          categoryMid: mid,
          l1Tag: l1,
          storage: storage,
          brand: allInL1 ? null : brand,
          menu: allInL1 ? null : menu,
          flavor: flavor,
          volumeMlMin: volumeMin,
          volumeMlMax: volumeMax,
          offset: 0,
          limit: 50,
        );
    return CatalogListState(items: page.items, total: page.total);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.loadingMore || !current.hasMore) return;
    state = AsyncData(
      CatalogListState(
        items: current.items,
        total: current.total,
        loadingMore: true,
      ),
    );
    try {
      final q = ref.read(catalogDebouncedSearchProvider).trim();
      final page = await ref.read(apiClientProvider).catalogProducts(
            q: q.isEmpty ? null : q,
            category: ref.read(catalogCategoryProvider),
            categoryMajor: ref.read(catalogMajorProvider),
            categoryMid: ref.read(catalogMidProvider),
            l1Tag: ref.read(catalogL1Provider),
            storage: ref.read(catalogStorageFilterProvider),
            brand: ref.read(catalogL1AllProvider)
                ? null
                : ref.read(catalogL1BrandProvider),
            menu: ref.read(catalogL1AllProvider)
                ? null
                : ref.read(catalogL1MenuProvider),
            flavor: ref.read(catalogFlavorFilterProvider),
            volumeMlMin: ref.read(catalogVolumeMinFilterProvider),
            volumeMlMax: ref.read(catalogVolumeMaxFilterProvider),
            offset: current.items.length,
            limit: 50,
          );
      state = AsyncData(
        CatalogListState(
          items: [...current.items, ...page.items],
          total: page.total,
        ),
      );
    } catch (_) {
      state = AsyncData(
        CatalogListState(items: current.items, total: current.total),
      );
      rethrow;
    }
  }
}

final catalogProductsProvider =
    AsyncNotifierProvider.autoDispose<CatalogProductsNotifier, CatalogListState>(
  CatalogProductsNotifier.new,
);

final guestL1FacetsProvider =
    FutureProvider.autoDispose<GuestL1FacetsModel?>((ref) async {
  final l1 = ref.watch(catalogL1Provider);
  if (l1 == null || l1.isEmpty) return null;
  final storage = ref.watch(catalogStorageFilterProvider);
  return ref.watch(apiClientProvider).guestL1Facets(l1Tag: l1, storage: storage);
});

final catalogProductDetailProvider =
    FutureProvider.autoDispose.family<CatalogProductDetailModel, String>((ref, id) async {
  final flavor = ref.watch(catalogFlavorFilterProvider);
  final volumeMin = ref.watch(catalogVolumeMinFilterProvider);
  final volumeMax = ref.watch(catalogVolumeMaxFilterProvider);
  return ref.watch(apiClientProvider).catalogProduct(
        id,
        flavor: flavor,
        volumeMlMin: volumeMin,
        volumeMlMax: volumeMax,
      );
});

final ordersProvider = FutureProvider.autoDispose<List<OrderModel>>((ref) async {
  return ref.watch(apiClientProvider).orders();
});

final addressesProvider =
    FutureProvider.autoDispose<List<ShippingAddressModel>>((ref) async {
  return ref.watch(apiClientProvider).addresses();
});

final membershipPlansProvider = FutureProvider.autoDispose<List<MembershipPlanModel>>((ref) async {
  return ref.watch(apiClientProvider).membershipPlans();
});

final myMembershipProvider = FutureProvider.autoDispose<SubscriptionModel?>((ref) async {
  final auth = ref.watch(authStateProvider).valueOrNull;
  if (auth?.buyer == null) return null;
  return ref.watch(apiClientProvider).myMembership();
});
