import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_mall/core/auth/login_portal.dart';
import 'package:shopping_mall/core/models/models.dart';
import 'package:shopping_mall/core/network/api_client.dart';
import 'package:shopping_mall/core/providers/app_providers.dart';
import 'package:shopping_mall/core/storage/token_storage.dart';

class _MemTokens extends TokenStorage {
  final Map<String, String> kv = {};

  @override
  Future<String?> storageGet(String key) async => kv[key];

  @override
  Future<void> storageSet(String key, String value) async {
    kv[key] = value;
  }

  @override
  Future<void> storageRemove(String key) async {
    kv.remove(key);
  }
}

class _Api extends ApiClient {
  _Api(this.user) : super(tokenReader: () async => null);

  final UserModel user;

  @override
  Future<String> login(
    String email,
    String password, {
    LoginPortal portal = LoginPortal.buyer,
  }) async =>
      'tok';

  @override
  Future<UserModel> me() async => user;
}

Future<AuthState> _ready(AuthNotifier notifier) async {
  for (var i = 0; i < 50; i++) {
    final value = notifier.state;
    final data = value.valueOrNull;
    if (data != null) return data;
    final err = value.error;
    if (err != null) throw err;
    await Future<void>.delayed(Duration.zero);
  }
  fail('auth bootstrap timed out');
}

void main() {
  final admin = UserModel(
    id: 'u1',
    email: 'admin@mall.local',
    isAdmin: true,
  );

  test('away TTL is 5 minutes and ignores null leftAt', () {
    final now = DateTime.utc(2026, 1, 1, 12);
    expect(TokenStorage.isAwayExpired(null, now), isFalse);
    expect(
      TokenStorage.isAwayExpired(now.subtract(const Duration(minutes: 5)), now),
      isFalse,
    );
    expect(
      TokenStorage.isAwayExpired(
        now.subtract(const Duration(minutes: 5, seconds: 1)),
        now,
      ),
      isTrue,
    );
  });

  test('return to /admin within 5 minutes keeps the portal token', () async {
    var now = DateTime.utc(2026, 1, 1, 12);
    final tokens = _MemTokens();
    final notifier = AuthNotifier(_Api(admin), tokens, clock: () => now);
    await _ready(notifier);
    await notifier.login('a@b.c', 'x', portal: LoginPortal.admin);

    notifier.setActive(LoginPortal.buyer);
    now = now.add(const Duration(minutes: 4, seconds: 59));
    notifier.setActive(LoginPortal.admin);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.valueOrNull?.admin?.token, 'tok');
    expect(tokens.kv[TokenStorage.tokenKey(LoginPortal.admin)], 'tok');
  });

  test('return to /admin after 5 minutes clears the portal token', () async {
    var now = DateTime.utc(2026, 1, 1, 12);
    final tokens = _MemTokens();
    final notifier = AuthNotifier(_Api(admin), tokens, clock: () => now);
    await _ready(notifier);
    await notifier.login('a@b.c', 'x', portal: LoginPortal.admin);

    notifier.setActive(LoginPortal.buyer);
    now = now.add(const Duration(minutes: 5, seconds: 1));
    notifier.setActive(LoginPortal.admin);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.valueOrNull?.admin, isNull);
    expect(tokens.kv[TokenStorage.tokenKey(LoginPortal.admin)], isNull);
    expect(notifier.state.valueOrNull?.canAccess(LoginPortal.admin), isFalse);
  });

  test('staying on /admin does not expire at 5 minutes', () async {
    var now = DateTime.utc(2026, 1, 1, 12);
    final tokens = _MemTokens();
    final notifier = AuthNotifier(_Api(admin), tokens, clock: () => now);
    await _ready(notifier);
    await notifier.login('a@b.c', 'x', portal: LoginPortal.admin);

    now = now.add(const Duration(minutes: 30));
    notifier.setActive(LoginPortal.admin);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.valueOrNull?.admin?.token, 'tok');
    expect(tokens.kv[TokenStorage.tokenKey(LoginPortal.admin)], 'tok');
  });

  test('bootstrap drops an away-expired admin slot', () async {
    final left = DateTime.utc(2026, 1, 1, 12);
    final now = left.add(const Duration(minutes: 6));
    final tokens = _MemTokens();
    await tokens.writePortalToken(LoginPortal.admin, 'old');
    await tokens.markPortalLeft(LoginPortal.admin, left);

    final notifier = AuthNotifier(_Api(admin), tokens, clock: () => now);
    final state = await _ready(notifier);

    expect(state.admin, isNull);
    expect(tokens.kv[TokenStorage.tokenKey(LoginPortal.admin)], isNull);
  });
}
