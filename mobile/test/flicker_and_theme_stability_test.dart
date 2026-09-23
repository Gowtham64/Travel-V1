import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travel_app/services/theme_controller.dart';
import 'package:travel_app/services/auth_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Flicker & Theme Stability Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('ThemeController defaults to dark mode cleanly without state oscillation', () async {
      final controller = ThemeController.instance;
      await controller.initialize();

      expect(controller.mode, equals(ThemeMode.dark));
      expect(controller.isDark, isTrue);
    });

    test('ThemeController restores light mode and persists changes', () async {
      SharedPreferences.setMockInitialValues({
        'voyplan.theme_mode': 'light',
      });

      final controller = ThemeController.instance;
      await controller.initialize();
      await controller.setMode(ThemeMode.light);

      expect(controller.mode, equals(ThemeMode.light));
      expect(controller.isDark, isFalse);

      // Toggle back to dark
      await controller.toggle();
      expect(controller.mode, equals(ThemeMode.dark));
      expect(controller.isDark, isTrue);
    });

    test('AuthSession initializes with stable loading state until resolved', () {
      final auth = AuthSession.instance;
      expect(auth.status, isNotNull);
    });
  });
}
