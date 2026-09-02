import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../network/api_client.dart';
import '../storage/token_storage.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

/// 홈 카탈로그 검색어 — 웹 헤더·카탈로그 화면 공유.
final catalogSearchProvider = StateProvider<String>((ref) => '');

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
  const AuthState({this.user, this.token});

  final UserModel? user;
  final String? token;

  bool get isLoggedIn => token != null && token!.isNotEmpty;
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
      final user = await _api.me();
      state = AsyncValue.data(AuthState(user: user, token: token));
    } catch (e) {
      await _tokens.clear();
      state = const AsyncValue.data(AuthState());
    }
  }

  Future<void> login(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final token = await _api.login(email, password);
      await _tokens.write(token);
      final user = await _api.me();
      state = AsyncValue.data(AuthState(user: user, token: token));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> register(String email, String password, {String? displayName}) async {
    state = const AsyncValue.loading();
    try {
      final token = await _api.register(email, password, displayName: displayName);
      await _tokens.write(token);
      final user = await _api.me();
      state = AsyncValue.data(AuthState(user: user, token: token));
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
    state = AsyncValue.data(AuthState(user: user, token: current!.token));
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
  final flavor = ref.watch(catalogFlavorFilterProvider);
  final volumeMin = ref.watch(catalogVolumeMinFilterProvider);
  final volumeMax = ref.watch(catalogVolumeMaxFilterProvider);
  return ref.watch(apiClientProvider).catalogProducts(
        q: q.isEmpty ? null : q,
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
