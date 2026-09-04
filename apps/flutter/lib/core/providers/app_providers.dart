import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/login_portal.dart';
import '../models/models.dart';
import '../network/api_client.dart';
import '../storage/token_storage.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

/// 홈 카탈로그 검색어 — 웹 헤더·카탈로그 화면 공유.
final catalogSearchProvider = StateProvider<String>((ref) => '');

/// 식탁 대분류 (AI-Hub). 제품 유무와 무관.
final catalogMajorProvider = StateProvider<String?>((ref) => null);

/// 식탁 중분류.
final catalogMidProvider = StateProvider<String?>((ref) => null);

/// 소분류(대표 상품 category) — 목록 세부 필터.
final catalogCategoryProvider = StateProvider<String?>((ref) => null);

/// 맛·용량 옵션 필터 — catalog_screen 본문 전용.
final catalogFlavorFilterProvider = StateProvider<String?>((ref) => null);
final catalogVolumeMinFilterProvider = StateProvider<int?>((ref) => null);
final catalogVolumeMaxFilterProvider = StateProvider<int?>((ref) => null);

final authStateProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<AuthState>>((ref) {
  return AuthNotifier(
    ref.watch(apiClientProvider),
    ref.watch(tokenStorageProvider),
  );
});

class AuthState {
  const AuthState({
    this.user,
    this.token,
    this.portal = LoginPortal.buyer,
  });

  final UserModel? user;
  final String? token;
  final LoginPortal portal;

  bool get isLoggedIn => token != null && token!.isNotEmpty;

  bool isPortal(LoginPortal value) => isLoggedIn && portal == value;
}

class AuthNotifier extends StateNotifier<AsyncValue<AuthState>> {
  AuthNotifier(this._api, this._tokens) : super(const AsyncValue.loading()) {
    _bootstrap();
  }

  final ApiClient _api;
  final TokenStorage _tokens;

  Future<void> _bootstrap() async {
    try {
      final token = await _tokens.read();
      if (token == null || token.isEmpty) {
        state = const AsyncValue.data(AuthState());
        return;
      }
      final portal = LoginPortal.parse(await _tokens.readPortal());
      final user = await _api.me();
      state = AsyncValue.data(AuthState(user: user, token: token, portal: portal));
    } catch (e) {
      await _tokens.clear();
      state = const AsyncValue.data(AuthState());
    }
  }

  Future<void> login(
    String email,
    String password, {
    LoginPortal portal = LoginPortal.buyer,
  }) async {
    state = const AsyncValue.loading();
    try {
      final token = await _api.login(email, password, portal: portal);
      await _tokens.write(token);
      await _tokens.writePortal(portal.name);
      final user = await _api.me();
      state = AsyncValue.data(AuthState(user: user, token: token, portal: portal));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> register(
    String email,
    String password, {
    String? displayName,
    LoginPortal portal = LoginPortal.buyer,
  }) async {
    state = const AsyncValue.loading();
    try {
      final token = await _api.register(email, password, displayName: displayName);
      await _tokens.write(token);
      await _tokens.writePortal(portal.name);
      final user = await _api.me();
      state = AsyncValue.data(AuthState(user: user, token: token, portal: portal));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> logout() async {
    await _tokens.clear();
    state = const AsyncValue.data(AuthState());
  }

  Future<void> refreshUser() async {
    final current = state.valueOrNull;
    if (current?.token == null) return;
    final user = await _api.me();
    state = AsyncValue.data(
      AuthState(user: user, token: current!.token, portal: current.portal),
    );
  }
}

final creditsProvider = FutureProvider.autoDispose<int?>((ref) async {
  final auth = ref.watch(authStateProvider).valueOrNull;
  if (auth?.token == null) return null;
  return ref.watch(apiClientProvider).credits();
});

final productsProvider = FutureProvider.autoDispose<List<ProductModel>>((ref) async {
  return ref.watch(apiClientProvider).products();
});

final catalogProductsProvider = FutureProvider.autoDispose<List<CatalogProductModel>>((ref) async {
  final q = ref.watch(catalogSearchProvider).trim();
  final major = ref.watch(catalogMajorProvider);
  final mid = ref.watch(catalogMidProvider);
  final category = ref.watch(catalogCategoryProvider);
  final flavor = ref.watch(catalogFlavorFilterProvider);
  final volumeMin = ref.watch(catalogVolumeMinFilterProvider);
  final volumeMax = ref.watch(catalogVolumeMaxFilterProvider);
  return ref.watch(apiClientProvider).catalogProducts(
        q: q.isEmpty ? null : q,
        category: category,
        categoryMajor: major,
        categoryMid: mid,
        flavor: flavor,
        volumeMlMin: volumeMin,
        volumeMlMax: volumeMax,
      );
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

final cartProvider = FutureProvider.autoDispose<CartModel>((ref) async {
  final auth = ref.watch(authStateProvider).valueOrNull;
  if (auth?.token == null) {
    return CartModel(items: const [], totalCredits: 0);
  }
  return ref.watch(apiClientProvider).cart();
});

final ordersProvider = FutureProvider.autoDispose<List<OrderModel>>((ref) async {
  return ref.watch(apiClientProvider).orders();
});

final membershipPlansProvider = FutureProvider.autoDispose<List<MembershipPlanModel>>((ref) async {
  return ref.watch(apiClientProvider).membershipPlans();
});

final myMembershipProvider = FutureProvider.autoDispose<SubscriptionModel?>((ref) async {
  final auth = ref.watch(authStateProvider).valueOrNull;
  if (auth?.token == null) return null;
  return ref.watch(apiClientProvider).myMembership();
});
