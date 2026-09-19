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

import 'services/trip_reminder_service.dart';
import 'widgets/trip_start_dialog.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

// Environment-driven (see AppConfig). Defaults are the production project, so a
// plain build is unchanged; staging/dev override via --dart-define.
const supabaseUrl = AppConfig.supabaseUrl;
const supabaseAnonKey = AppConfig.supabaseAnonKey;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (supabaseUrl != 'YOUR_SUPABASE_URL' &&
      supabaseAnonKey != 'YOUR_SUPABASE_ANON_KEY') {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Supabase initialization warning: $e');
    }
  }

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

    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'VoyPlan',
      debugShowCheckedModeBanner: false,
      theme: Voy.dark(textTheme),
      darkTheme: Voy.dark(textTheme),
      themeMode: ThemeMode.dark,
      home: const AuthStateWrapper(),
      // A prominent, unmissable STAGING banner — shown ONLY on staging builds
      // (APP_ENV=staging) so staging can never be confused with production.
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
  bool _isLoading = true;
  bool _isAuthenticated = false;
  StreamSubscription<TripDepartureReminder>? _tripReadySub;
  StreamSubscription<AuthState>? _authSub;
  bool _isTripStartDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
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
    _authSub?.cancel();
    _tripReadySub?.cancel();
    super.dispose();
  }

  Future<void> _checkAuth() async {
    // Check for guest=true query parameter on web to bypass login during automated testing
    if (kIsWeb) {
      final uri = Uri.base;
      // NOTE: do not log the full URL here — it can carry the `sb_refresh`
      // session-handoff token in its query/fragment, which would leak into
      // the browser console/logs.
      if (uri.queryParameters['guest'] == 'true' ||
          uri.toString().contains('guest=true')) {
        sanitizeBrowserUrl();
        setState(() {
          _isAuthenticated = true;
          _isLoading = false;
        });
        return;
      }

      // The landing page and Flutter share Supabase's canonical browser
      // storage key. Do not refresh a copied token here: refresh-token rotation
      // can make that copy stale and leave this screen loading indefinitely.
      // This only removes legacy hand-off fragments emitted by older builds.
      if (uri.queryParameters.containsKey('sb_refresh') ||
          uri.fragment.contains('sb_refresh=')) {
        sanitizeBrowserUrl();
      }
    }

    // If keys aren't set, just bypass auth for local dev
    if (supabaseUrl == 'YOUR_SUPABASE_URL') {
      setState(() {
        _isAuthenticated = true;
        _isLoading = false;
      });
      return;
    }

    try {
      final client = Supabase.instance.client;
      _authSub?.cancel();
      _authSub = client.auth.onAuthStateChange.listen((data) {
        final current = data.session;
        if (mounted) {
          setState(() {
            _isAuthenticated = current != null;
          });
        }
      });

      // Supabase continues any canonical browser-storage recovery in the
      // background. Subscribe before reading the current state so that a late
      // recovery event is never missed, and always release the loading UI.
      final session = client.auth.currentSession;
      if (mounted) {
        setState(() {
          _isAuthenticated = session != null;
          _isLoading = false;
        });
      }
    } on Object catch (e) {
      debugPrint('Auth check error: $e');
      if (mounted) {
        setState(() {
          _isAuthenticated = false;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF070D18),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
        ),
      );
    }
    // Web visitors accessing /app/ are using the application directly
    if (_isAuthenticated || kIsWeb) return const HomeScreen();
    // Serve the public VoyPlan landing page for unauthenticated mobile visitors
    return LandingScreen(
      onLogin: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      },
      onPlanTrip: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      },
    );
  }
}
