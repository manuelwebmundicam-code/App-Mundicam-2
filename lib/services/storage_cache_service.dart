// services/storage_cache_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class StorageCacheService {
  static const Duration _ttl = Duration(hours: 2);

  static Future<void> cacheData(String key, dynamic data) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(key, jsonEncode(data));
    prefs.setString('${key}_time', DateTime.now().toIso8601String());
  }

  static Future<dynamic> getCachedData(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString('${key}_time');
    if (timeStr == null) return null;
    if (DateTime.now().difference(DateTime.parse(timeStr)) > _ttl) {
      prefs.remove(key);
      prefs.remove('${key}_time');
      return null;
    }
    final data = prefs.getString(key);
    return data != null ? jsonDecode(data) : null;
  }
}