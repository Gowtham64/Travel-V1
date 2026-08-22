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
  /// Defaults to empty when not provided at build time (map tiles then fail to
  /// load, which is the intended signal that the token is missing).
  static const String mapboxToken = String.fromEnvironment('MAPBOX_TOKEN');

  /// Whether a Mapbox token was provided at build time.
  static bool get hasMapboxToken => mapboxToken.isNotEmpty;
}
