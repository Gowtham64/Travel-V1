/// Central app configuration sourced from build-time `--dart-define`s.
///
/// Values here are compiled in at build time, keeping secrets/keys out of the
/// source tree. Provide them when building or running, e.g.:
///
///   flutter run    --dart-define=MAPBOX_TOKEN=pk.your_token
///   flutter build web --dart-define=MAPBOX_TOKEN=pk.your_token
///
/// Local and CI builds can pass this value with `--dart-define`.
class AppConfig {
  AppConfig._();

  /// Canonical application release version across Web, Android, and iOS.
  static const String appVersion = '1.0.0';
  static const int buildNumber = 1;

  /// Public Mapbox access token used for map tiles, geocoding and the 3D globe.
  ///
  /// Client tokens are inherently shipped to users, so the real protection is a
  /// URL-restricted token configured in the Mapbox dashboard — not hiding it.
  static const String mapboxToken = String.fromEnvironment(
    'MAPBOX_TOKEN',
    defaultValue:
        'pk.eyJ1IjoiZ293dGhhbWVjNjQiLCJhIjoiY21yZzhnOG82MGh2dTJ6c2FuM3h6ZXdkayJ9.PmiHwk5A4-eSWu7zLYkSXQ',
  );

  /// Whether a Mapbox token was provided at build time.
  static bool get hasMapboxToken => mapboxToken.isNotEmpty;

  // ---------------------------------------------------------------------------
  // Environment (development / staging / production)
  //
  // The DEFAULTS below are the current PRODUCTION values, so a plain build with
  // no extra defines behaves exactly as production does today — nothing about
  // voyplan.in changes. Staging/dev builds override these via --dart-define, e.g.
  //
  //   flutter build web \
  //     --dart-define=APP_ENV=staging \
  //     --dart-define=SUPABASE_URL=https://<staging-ref>.supabase.co \
  //     --dart-define=SUPABASE_ANON_KEY=<staging anon key> \
  //     --dart-define=BACKEND_URL=https://staging-api.voyplan.in \
  //     --dart-define=MAPBOX_TOKEN=pk.xxx
  // ---------------------------------------------------------------------------

  /// 'production' (default) | 'staging' | 'development'.
  static const String appEnv =
      String.fromEnvironment('APP_ENV', defaultValue: 'production');

  static bool get isProduction => appEnv == 'production';
  static bool get isStaging => appEnv == 'staging';
  static bool get isDevelopment => appEnv == 'development';

  /// The public Flutter Web entry point used for authentication callbacks.
  ///
  /// OAuth providers must return to a URL registered in Supabase. Keeping this
  /// separate from [Uri.base] means a Pages preview, a query-string deep link,
  /// or a custom domain alias cannot accidentally make Supabase fall back to an
  /// obsolete Site URL. Non-production builds keep using the current browser
  /// URL unless this is explicitly overridden.
  static const String webAuthCallbackUrl = String.fromEnvironment(
    'WEB_AUTH_CALLBACK_URL',
    defaultValue: appEnv == 'production' ? 'https://voyplan.in/app/' : '',
  );

  /// Supabase project URL. Defaults to the production project.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://dtemayjpttktntooxraa.supabase.co',
  );

  /// Supabase publishable/anon key. Defaults to the production key.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_sGmsHOvBlUiRKXz0ajEErg_vecwGFnh',
  );

  /// Hosted backend base URL. Configurable by environment (`APP_ENV`) or
  /// overridden via `--dart-define=BACKEND_URL=...`.
  /// Development: http://localhost:3000
  /// Staging:     https://staging-api.voyplan.in
  /// Production:  https://api.voyplan.in
  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: appEnv == 'development'
        ? 'http://localhost:3000'
        : (appEnv == 'staging'
            ? 'https://staging-api.voyplan.in'
            : 'https://api.voyplan.in'),
  );
}
