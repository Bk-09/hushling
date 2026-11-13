// Saved data. Replaces the ~/.calm_app/*.json files of the Python app with shared_preferences
// (works on Windows, Android, iOS, macOS and the web).
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class Store {
  static SharedPreferences? _p;

  static Future<void> init() async {
    try {
      _p = await SharedPreferences.getInstance();
    } catch (_) {
      _p = null; // never crash the app over a save problem
    }
  }

  static Map<String, dynamic>? getMap(String key) {
    try {
      final s = _p?.getString(key);
      if (s == null) return null;
      final d = jsonDecode(s);
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
    return null;
  }

  static void setMap(String key, Map<String, dynamic> value) {
    try {
      _p?.setString(key, jsonEncode(value));
    } catch (_) {}
  }
}
