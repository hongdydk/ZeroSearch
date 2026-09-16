import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/login_portal.dart';

class TokenStorage {
  static const _legacyTokenKey = 'accessToken';
  static const _legacyPortalKey = 'loginPortal';
  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  bool _migrated = false;

  static String tokenKey(LoginPortal portal) => 'token_${portal.name}';

  LoginPortal activePortal = LoginPortal.buyer;

  Future<String?> readPortalToken(LoginPortal portal) async {
    await _migrateLegacy();
    return _get(tokenKey(portal));
  }

  Future<String?> readActiveToken() => readPortalToken(activePortal);

  Future<void> writePortalToken(LoginPortal portal, String token) async {
    await _migrateLegacy();
    await _set(tokenKey(portal), token);
  }

  Future<void> clearPortal(LoginPortal portal) async {
    await _migrateLegacy();
    await _remove(tokenKey(portal));
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
    final legacy = await _get(_legacyTokenKey);
    if (legacy == null || legacy.isEmpty) return;
    final portal = LoginPortal.parse(await _get(_legacyPortalKey));
    final existing = await _get(tokenKey(portal));
    if (existing == null || existing.isEmpty) {
      await _set(tokenKey(portal), legacy);
    }
    await _remove(_legacyTokenKey);
    await _remove(_legacyPortalKey);
  }

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
