import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/landing_screen.dart';
import 'utils/landing_redirect.dart';
import 'theme/app_theme.dart';
import 'config/app_config.dart';

import 'services/auth_session.dart';
import 'services/theme_controller.dart';

import 'services/trip_reminder_service.dart';
import 'widgets/trip_start_dialog.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

// Environment-driven (see AppConfig). Defaults are the production project, so a
// plain build is unchanged; staging/dev override via --dart-define.
const supabaseUrl = AppConfig.supabaseUrl;
const supabaseAnonKey = AppConfig.supabaseAnonKey;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    syncWebAuthTokens();
    syncWebTheme();
  }

  if (supabaseUrl != 'YOUR_SUPABASE_URL' &&
      supabaseAnonKey != 'YOUR_SUPABASE_ANON_KEY') {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      );
    } catch (e) {
      debugPrint('Supabase initialization warning: $e');
    }
  }

  // Complete session hydration before any page can decide whether the user is
  // signed in. This is intentionally separate from feature-level checks: the
  // whole app consumes AuthSession as its single authentication source.
  await AuthSession.instance.initialize();
  await ThemeController.instance.initialize();

  // Initialize pre-trip departure reminder listener
  try {
    await TripReminderService.instance.initialize();
  } catch (e) {
    debugPrint('TripReminderService init warning: $e');
  }

  runApp(const TravelApp());
}

class TravelApp extends StatelessWidget {
  const TravelApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Fallback fonts so Indic-script text (e.g. Kannada/Hindi/Tamil POI
    // addresses) renders instead of tofu boxes, silencing the "missing Noto
    // fonts" warning. Loaded via google_fonts, chained after Poppins.
    final indicFallback = <String>[
      GoogleFonts.notoSansKannada().fontFamily!,
      GoogleFonts.notoSansDevanagari().fontFamily!,
      GoogleFonts.notoSansTamil().fontFamily!,
      GoogleFonts.notoSansTelugu().fontFamily!,
    ];
    final baseTextTheme =
        GoogleFonts.poppinsTextTheme(Theme.of(context).textTheme);
    final textTheme = _withFontFallback(baseTextTheme, indicFallback);

    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) => MaterialApp(
        navigatorKey: appNavigatorKey,
        title: 'VoyPlan',
        debugShowCheckedModeBanner: false,
        theme: Voy.light(textTheme),
        darkTheme: Voy.dark(textTheme),
        themeMode: ThemeController.instance.mode,
        home: const AuthStateWrapper(),
        // A prominent, unmissable STAGING banner — shown ONLY on staging
        // builds (APP_ENV=staging) so it cannot be mistaken for production.
        builder: (context, child) {
          final content = child ?? const SizedBox.shrink();
          final wrapped = GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              final currentFocus = FocusManager.instance.primaryFocus;
              if (currentFocus != null && currentFocus.hasFocus) {
                currentFocus.unfocus();
              }
            },
            child: content,
          );
          if (!AppConfig.isStaging) return wrapped;
          return Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(
              children: [
                wrapped,
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: IgnorePointer(
                      child: Container(
                        color: const Color(0xF2C62828),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        alignment: Alignment.center,
                        child: const Text(
                          '⚠ STAGING — NOT PRODUCTION',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Applies [fallback] font families to every style in [t] so glyphs missing
  /// from the primary font fall through to the Noto Indic fonts.
  TextTheme _withFontFallback(TextTheme t, List<String> fallback) {
    TextStyle? f(TextStyle? s) => s?.copyWith(fontFamilyFallback: fallback);
    return TextTheme(
      displayLarge: f(t.displayLarge),
      displayMedium: f(t.displayMedium),
      displaySmall: f(t.displaySmall),
      headlineLarge: f(t.headlineLarge),
      headlineMedium: f(t.headlineMedium),
      headlineSmall: f(t.headlineSmall),
      titleLarge: f(t.titleLarge),
      titleMedium: f(t.titleMedium),
      titleSmall: f(t.titleSmall),
      bodyLarge: f(t.bodyLarge),
      bodyMedium: f(t.bodyMedium),
      bodySmall: f(t.bodySmall),
      labelLarge: f(t.labelLarge),
      labelMedium: f(t.labelMedium),
      labelSmall: f(t.labelSmall),
    );
  }
}

class AuthStateWrapper extends StatefulWidget {
  const AuthStateWrapper({super.key});

  @override
  State<AuthStateWrapper> createState() => _AuthStateWrapperState();
}

class _AuthStateWrapperState extends State<AuthStateWrapper> {
  StreamSubscription<TripDepartureReminder>? _tripReadySub;
  bool _isTripStartDialogOpen = false;
  bool _redirectingToLanding = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // Older landing builds included a refresh token in the URL. Supabase now
      // restores only its canonical browser storage, so remove any lingering
      // legacy hand-off value before it can leak through history or referrers.
      final uri = Uri.base;
      if (uri.queryParameters.containsKey('sb_refresh') ||
          uri.fragment.contains('sb_refresh=')) {
        sanitizeBrowserUrl();
      }
    }
    _setupTripReadyListener();
  }

  void _setupTripReadyListener() {
    _tripReadySub =
        TripReminderService.instance.onTripReadyToStart.listen((reminder) {
      _showTripStartDialogIfNeeded(reminder);
    });
  }

  void _showTripStartDialogIfNeeded(TripDepartureReminder reminder) {
    if (_isTripStartDialogOpen) return;
    final navContext = appNavigatorKey.currentContext;
    if (navContext == null) return;

    _isTripStartDialogOpen = true;
    TripStartDialog.show(
      navContext,
      reminder,
      onStartNavigation: () {
        _isTripStartDialogOpen = false;
      },
      onPostponed: (_) {
        _isTripStartDialogOpen = false;
      },
    ).then((_) {
      _isTripStartDialogOpen = false;
    });
  }

  @override
  void dispose() {
    _tripReadySub?.cancel();
    super.dispose();
  }

  void _redirectToLanding() {
    if (_redirectingToLanding) return;
    _redirectingToLanding = true;
    // The landing page owns sign-in for the web build. Preserve the exact app
    // destination (including planner query data) so successful login resumes
    // the action the visitor originally selected.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) redirectToLanding(returnTo: Uri.base.toString());
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthSession.instance,
      builder: (context, _) {
        if (AuthSession.instance.isLoading) {
          return const Scaffold(
            backgroundColor: Color(0xFF070D18),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
            ),
          );
        }
        if (AuthSession.instance.isAuthenticated) return const HomeScreen();

        if (kIsWeb) {
          _redirectToLanding();
          return const Scaffold(
            backgroundColor: Color(0xFF070D18),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
            ),
          );
        }

        // Native clients retain their in-app public landing screen.
        return LandingScreen(
          onLogin: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
          },
          onPlanTrip: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
          },
        );
      },
    );
  }
}
