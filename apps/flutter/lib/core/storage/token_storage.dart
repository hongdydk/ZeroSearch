import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/login_portal.dart';

class TokenStorage {
  static const _legacyTokenKey = 'accessToken';
  static const _legacyPortalKey = 'loginPortal';

  /// 관리자·판매자 포털을 떠난 뒤에만 적용. 해당 경로에 머무르면 JWT exp만 본다.
  static const awaySessionTtl = Duration(minutes: 5);

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  bool _migrated = false;
  bool _leftAtLoaded = false;
  final Map<LoginPortal, DateTime> leftAtByPortal = {};

  static String tokenKey(LoginPortal portal) => 'token_${portal.name}';

  static String leftAtKey(LoginPortal portal) => 'leftAt_${portal.name}';

  static bool usesAwaySessionTtl(LoginPortal portal) =>
      portal == LoginPortal.admin || portal == LoginPortal.seller;

  static bool isAwayExpired(DateTime? leftAt, DateTime now) {
    if (leftAt == null) return false;
    return now.toUtc().difference(leftAt.toUtc()) > awaySessionTtl;
  }

  LoginPortal activePortal = LoginPortal.buyer;

  Future<String?> readPortalToken(LoginPortal portal) async {
    await _migrateLegacy();
    return storageGet(tokenKey(portal));
  }

  Future<String?> readActiveToken() => readPortalToken(activePortal);

  Future<void> writePortalToken(LoginPortal portal, String token) async {
    await _migrateLegacy();
    await storageSet(tokenKey(portal), token);
    await clearPortalLeft(portal);
  }

  Future<void> clearPortal(LoginPortal portal) async {
    await _migrateLegacy();
    await storageRemove(tokenKey(portal));
    await clearPortalLeft(portal);
  }

  Future<void> loadLeftAts() async {
    if (_leftAtLoaded) return;
    _leftAtLoaded = true;
    await _migrateLegacy();
    for (final portal in LoginPortal.values) {
      if (!usesAwaySessionTtl(portal)) continue;
      if (leftAtByPortal.containsKey(portal)) continue;
      final raw = await storageGet(leftAtKey(portal));
      if (raw == null || raw.isEmpty) continue;
      final ms = int.tryParse(raw);
      if (ms == null) continue;
      leftAtByPortal[portal] =
          DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    }
  }

  Future<void> markPortalLeft(LoginPortal portal, DateTime at) async {
    if (!usesAwaySessionTtl(portal)) return;
    final utc = at.toUtc();
    leftAtByPortal[portal] = utc;
    await storageSet(leftAtKey(portal), '${utc.millisecondsSinceEpoch}');
  }

  Future<void> clearPortalLeft(LoginPortal portal) async {
    leftAtByPortal.remove(portal);
    await storageRemove(leftAtKey(portal));
  }

  bool isPortalAwayExpired(LoginPortal portal, DateTime now) {
    if (!usesAwaySessionTtl(portal)) return false;
    return isAwayExpired(leftAtByPortal[portal], now);
  }

  /// 레거시 단일 키 — 구매자 슬롯과 같다. 테스트 페이크가 오버라이드한다.
  Future<String?> read() => readPortalToken(LoginPortal.buyer);

  Future<void> write(String token) =>
      writePortalToken(LoginPortal.buyer, token);

  Future<String?> readPortal() async => null;

  Future<void> writePortal(String value) async {}

  Future<void> clear() async {
    for (final portal in LoginPortal.values) {
      await clearPortal(portal);
    }
  }

  Future<void> _migrateLegacy() async {
    if (_migrated) return;
    _migrated = true;
    final legacy = await storageGet(_legacyTokenKey);
    if (legacy == null || legacy.isEmpty) return;
    final portal = LoginPortal.parse(await storageGet(_legacyPortalKey));
    final existing = await storageGet(tokenKey(portal));
    if (existing == null || existing.isEmpty) {
      await storageSet(tokenKey(portal), legacy);
    }
    await storageRemove(_legacyTokenKey);
    await storageRemove(_legacyPortalKey);
  }

  Future<String?> storageGet(String key) => _get(key);

  Future<void> storageSet(String key, String value) => _set(key, value);

  Future<void> storageRemove(String key) => _remove(key);

  Future<String?> _get(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }
    return _secure.read(key: key);
  }

  Future<void> _set(String key, String value) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
      return;
    }
    await _secure.write(key: key, value: value);
  }

  Future<void> _remove(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      return;
    }
    await _secure.delete(key: key);
  }
}
