import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  const LocalStorageService();

  Future<String?> readString(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<void> writeString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }
}
