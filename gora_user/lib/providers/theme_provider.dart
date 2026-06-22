import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Holds the app's light/dark preference and persists it across launches.
class ThemeProvider extends ChangeNotifier {
  static const _key = 'theme_mode'; // 'light' | 'dark' | 'system'
  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  ThemeProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_key) ?? 'light';
    _mode = v == 'dark' ? ThemeMode.dark : (v == 'system' ? ThemeMode.system : ThemeMode.light);
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    _mode = m;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, m == ThemeMode.dark ? 'dark' : (m == ThemeMode.system ? 'system' : 'light'));
  }

  // Convenience toggle used by the settings switch
  Future<void> toggleDark(bool on) => setMode(on ? ThemeMode.dark : ThemeMode.light);
}
