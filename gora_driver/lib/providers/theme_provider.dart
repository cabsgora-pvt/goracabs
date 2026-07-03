import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_colors.dart';

class ThemeProvider extends ChangeNotifier {
  bool _dark = false;
  bool get isDark => _dark;
  ThemeMode get mode => _dark ? ThemeMode.dark : ThemeMode.light;

  ThemeProvider() { _load(); }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _dark = p.getBool('driver_dark') ?? false;
      AppColors.dark = _dark;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> toggle(bool v) async {
    _dark = v;
    AppColors.dark = v; // flip all surface/text colors app-wide
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('driver_dark', v);
    } catch (_) {}
  }
}
