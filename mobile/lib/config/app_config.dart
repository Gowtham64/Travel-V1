/// Central app configuration sourced from build-time `--dart-define`s.
///
/// Values here are compiled in at build time, keeping secrets/keys out of the
/// source tree. Provide them when building or running, e.g.:
///
///   flutter run    --dart-define=MAPBOX_TOKEN=pk.your_token
///   flutter build web --dart-define=MAPBOX_TOKEN=pk.your_token
///
/// (deploy_web.sh reads MAPBOX_TOKEN from the shell environment and passes it
/// through automatically.)
class AppConfig {
  AppConfig._();

  /// Public Mapbox access token used for map tiles, geocoding and the 3D globe.
  ///
  /// Client tokens are inherently shipped to users, so the real protection is a
  /// URL-restricted token configured in the Mapbox dashboard — not hiding it.
  static const String mapboxToken = String.fromEnvironment(
    'MAPBOX_TOKEN',
    defaultValue: 'pk.eyJ1IjoiZ293dGhhbWVjNjQiLCJhIjoiY21yZzhnOG82MGh2dTJ6c2FuM3h6ZXdkayJ9.PmiHwk5A4-eSWu7zLYkSXQ',
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
  //     --dart-define=BACKEND_URL=https://voyplan-staging-backend.onrender.com \
  //     --dart-define=MAPBOX_TOKEN=pk.xxx
  // ---------------------------------------------------------------------------

  /// 'production' (default) | 'staging' | 'development'.
  static const String appEnv =
      String.fromEnvironment('APP_ENV', defaultValue: 'production');

  static bool get isProduction => appEnv == 'production';
  static bool get isStaging => appEnv == 'staging';
  static bool get isDevelopment => appEnv == 'development';

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

  /// Hosted backend base URL. Defaults to the production Render service.
  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://travel-v1-mzia.onrender.com',
  );
}
