import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'screens/trip_planner_screen.dart';
import 'screens/login_screen.dart';
import 'utils/landing_redirect.dart';
import 'theme/app_theme.dart';

const supabaseUrl = 'https://dtemayjpttktntooxraa.supabase.co';
const supabaseAnonKey = 'sb_publishable_sGmsHOvBlUiRKXz0ajEErg_vecwGFnh';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (supabaseUrl != 'YOUR_SUPABASE_URL' && supabaseAnonKey != 'YOUR_SUPABASE_ANON_KEY') {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
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
    final baseTextTheme = GoogleFonts.poppinsTextTheme(Theme.of(context).textTheme);
    final textTheme = _withFontFallback(baseTextTheme, indicFallback);

    return MaterialApp(
      title: 'Voyplan',
      debugShowCheckedModeBanner: false,
      theme: Voy.dark(textTheme),
      darkTheme: Voy.dark(textTheme),
      themeMode: ThemeMode.dark,
      home: const AuthStateWrapper(),
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

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    // Check for guest=true query parameter on web to bypass login during automated testing
    if (kIsWeb) {
      final uri = Uri.base;
      print("AUTHENTICATION CHECK URL: $uri");
      if (uri.queryParameters['guest'] == 'true' || uri.toString().contains('guest=true')) {
        setState(() {
          _isAuthenticated = true;
          _isLoading = false;
        });
        return;
      }

      // Session hand-off from the static landing-page login card. The landing
      // page signs the user in with supabase-js, then redirects here with the
      // refresh token in the URL fragment (#sb_refresh=...). We restore the
      // session so the user lands straight in the app, already authenticated.
      final refreshToken = _readHandoffRefreshToken(uri);
      if (refreshToken != null && refreshToken.isNotEmpty) {
        try {
          await Supabase.instance.client.auth.setSession(refreshToken);
        } catch (e) {
          print("Session hand-off failed: $e");
        }
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
      final session = Supabase.instance.client.auth.currentSession;
      setState(() {
        _isAuthenticated = session != null;
        _isLoading = false;
      });

      Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        final session = data.session;
        if (mounted) {
          setState(() {
            _isAuthenticated = session != null;
          });
        }
      });
    } catch (_) {
      // Fallback for tests/local development when Supabase is not initialized
      setState(() {
        _isAuthenticated = true;
        _isLoading = false;
      });
    }
  }

  /// Extracts a refresh token passed from the landing-page login, whether it
  /// arrives in the URL fragment (#sb_refresh=...) or the query (?sb_refresh=...).
  String? _readHandoffRefreshToken(Uri uri) {
    final fromQuery = uri.queryParameters['sb_refresh'];
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
    if (uri.fragment.isNotEmpty) {
      try {
        final frag = Uri.splitQueryString(uri.fragment);
        final t = frag['sb_refresh'];
        if (t != null && t.isNotEmpty) return t;
      } catch (_) {}
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_isAuthenticated) return const TripPlannerScreen();
    // Not signed in: on web there is no in-app login screen — send the user to
    // the static landing page (which hosts the login card). Show a spinner while
    // the browser navigates. Native builds fall back to the in-app LoginScreen.
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => redirectToLanding());
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return const LoginScreen();
  }
}
