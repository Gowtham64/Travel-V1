import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owns the application-wide appearance preference.
///
/// Navigation, dashboard screens, dialogs, and all Material components read
/// the same [ThemeMode]. Keeping it here prevents a visual-only header toggle
/// from drifting away from the actual dashboard theme.
class ThemeController extends ChangeNotifier {
  ThemeController._();

  static final ThemeController instance = ThemeController._();
  static const _storageKey = 'voyplan.theme_mode';

  ThemeMode _mode = ThemeMode.dark;
  Future<void>? _initializing;

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    final preferences = await SharedPreferences.getInstance();
    _mode = preferences.getString(_storageKey) == ThemeMode.light.name
        ? ThemeMode.light
        : ThemeMode.dark;
    notifyListeners();
  }

  Future<void> toggle() => setMode(isDark ? ThemeMode.light : ThemeMode.dark);

  Future<void> setMode(ThemeMode next) async {
    if (_mode == next) return;
    _mode = next;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, next.name);
  }
}
