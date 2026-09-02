import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TokenStorage {
  static const _key = 'accessToken';
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<String?> read() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key);
    }
    return _secure.read(key: _key);
  }

  Future<void> write(String token) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, token);
      return;
    }
    await _secure.write(key: _key, value: token);
  }

  Future<void> clear() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
      return;
    }
    await _secure.delete(key: _key);
  }
}
