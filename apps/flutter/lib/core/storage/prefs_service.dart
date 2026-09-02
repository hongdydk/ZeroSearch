import 'package:shared_preferences/shared_preferences.dart';

class PrefsService {
  static const themeModeKey = 'mall:themeMode';

  Future<String?> themeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(themeModeKey);
  }

  Future<void> setThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(themeModeKey, mode);
  }
}
