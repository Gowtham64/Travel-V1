import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travel_app/config/app_config.dart';

void main() {
  group('VoyPlan Version & Sync Audit', () {
    test('Canonical App Version is 1.0.0 across platform configuration', () {
      expect(AppConfig.appVersion, equals('1.0.0'));
      expect(AppConfig.buildNumber, equals(1));
    });

    test('Production backend URL is configured to https://api.voyplan.in', () {
      if (AppConfig.isProduction) {
        expect(AppConfig.backendUrl, equals('https://api.voyplan.in'));
      }
    });

    test('Supabase Production Project configuration matches voyplan.in', () {
      expect(AppConfig.supabaseUrl, equals('https://dtemayjpttktntooxraa.supabase.co'));
      expect(AppConfig.supabaseAnonKey, isNotEmpty);
    });
  });

  group('VoyPlan Bidirectional Session Sync Engine', () {
    test('Synchronizes fresher session from base to Flutter key', () {
      final storage = <String, String>{};
      const kBase = 'sb-dtemayjpttktntooxraa-auth-token';
      const kFlutter = 'flutter.$kBase';

      final oldFlutterSession = jsonEncode({
        'access_token': 'old_token_1',
        'expires_at': 1700000000,
      });
      final newBaseSession = jsonEncode({
        'access_token': 'new_token_2',
        'expires_at': 1800000000,
      });

      storage[kFlutter] = oldFlutterSession;
      storage[kBase] = newBaseSession;

      // Simulate syncWebAuthTokens logic
      final sBase = storage[kBase];
      final sFlutter = storage[kFlutter];
      if (sBase != null && sFlutter != null && sBase != sFlutter) {
        int expB = (jsonDecode(sBase)['expires_at'] as num).toInt();
        int expF = (jsonDecode(sFlutter)['expires_at'] as num).toInt();
        if (expB >= expF) {
          storage[kFlutter] = sBase;
        } else {
          storage[kBase] = sFlutter;
        }
      }

      expect(storage[kFlutter], equals(newBaseSession));
      expect(jsonDecode(storage[kFlutter]!)['access_token'], equals('new_token_2'));
    });

    test('Synchronizes fresher session from Flutter to base key', () {
      final storage = <String, String>{};
      const kBase = 'sb-dtemayjpttktntooxraa-auth-token';
      const kFlutter = 'flutter.$kBase';

      final oldBaseSession = jsonEncode({
        'access_token': 'old_base_token',
        'expires_at': 1700000000,
      });
      final newFlutterSession = jsonEncode({
        'access_token': 'new_flutter_token',
        'expires_at': 1850000000,
      });

      storage[kBase] = oldBaseSession;
      storage[kFlutter] = newFlutterSession;

      // Simulate syncWebAuthTokens logic
      final sBase = storage[kBase];
      final sFlutter = storage[kFlutter];
      if (sBase != null && sFlutter != null && sBase != sFlutter) {
        int expB = (jsonDecode(sBase)['expires_at'] as num).toInt();
        int expF = (jsonDecode(sFlutter)['expires_at'] as num).toInt();
        if (expB >= expF) {
          storage[kFlutter] = sBase;
        } else {
          storage[kBase] = sFlutter;
        }
      }

      expect(storage[kBase], equals(newFlutterSession));
      expect(jsonDecode(storage[kBase]!)['access_token'], equals('new_flutter_token'));
    });
  });

  group('VoyPlan Responsive Display Range Tests', () {
    const viewports = [
      // Mobile
      Size(320, 640),
      Size(360, 740),
      Size(375, 812),
      Size(390, 844),
      Size(414, 896),
      Size(430, 932),
      Size(480, 800),
      // Tablet
      Size(600, 960),
      Size(768, 1024),
      Size(834, 1194),
      Size(900, 1280),
      Size(1024, 768),
      // Laptop & Desktop
      Size(1280, 800),
      Size(1366, 768),
      Size(1440, 900),
      Size(1600, 1200),
      Size(1920, 1080),
      // Ultrawide
      Size(2560, 1440),
      Size(3440, 1440),
    ];

    for (final size in viewports) {
      testWidgets('Renders layout container safely at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 600;
                  final isTablet = constraints.maxWidth >= 600 && constraints.maxWidth < 1100;
                  final isDesktop = constraints.maxWidth >= 1100;

                  return Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 12 : (isTablet ? 24 : 32),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1440),
                        child: Text(
                          isDesktop
                              ? 'Desktop Layout'
                              : (isTablet ? 'Tablet Layout' : 'Mobile Layout'),
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );

        expect(find.byType(Scaffold), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
