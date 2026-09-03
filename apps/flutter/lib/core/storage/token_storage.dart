import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TokenStorage {
  static const _key = 'accessToken';
  static const _portalKey = 'loginPortal';
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<String?> read() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key);
    }
    return _secure.read(key: _key);
  }

  Future<String?> readPortal() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_portalKey);
    }
    return _secure.read(key: _portalKey);
  }

  Future<void> write(String token) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, token);
      return;
    }
    await _secure.write(key: _key, value: token);
  }

  Future<void> writePortal(String portal) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_portalKey, portal);
      return;
    }
    await _secure.write(key: _portalKey, value: portal);
  }

  Future<void> clear() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
      await prefs.remove(_portalKey);
      return;
    }
    await _secure.delete(key: _key);
    await _secure.delete(key: _portalKey);
  }
}
