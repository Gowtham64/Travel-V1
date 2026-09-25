import 'auth_session.dart';

/// The only application-level decision point between the authentication state
/// and the root screen. Keeping this policy free of widget navigation makes
/// startup, OAuth callbacks, refreshes and manual sign-in deterministic.
enum AuthDestination { loading, login, dashboard }

class AuthRoute {
  AuthRoute._();

  static AuthDestination resolve(AuthStatus status) => switch (status) {
        AuthStatus.loading => AuthDestination.loading,
        AuthStatus.unauthenticated => AuthDestination.login,
        AuthStatus.authenticated => AuthDestination.dashboard,
      };

  /// OAuth must always return to a registered Flutter application URL.
  ///
  /// [canonicalAppUrl] is used for a production web build so Supabase never
  /// falls back to a stale Site URL when an OAuth flow starts from a preview or
  /// alias. Query parameters from the browser preserve a valid deep-link intent
  /// (for example a trip planner URL) after Google returns.
  static Uri oauthCallbackUri(
    Uri currentAppUri, {
    String? canonicalAppUrl,
  }) {
    final configured = canonicalAppUrl == null || canonicalAppUrl.isEmpty
        ? null
        : Uri.tryParse(canonicalAppUrl);
    final callbackBase =
        configured != null && configured.hasScheme && configured.host.isNotEmpty
            ? configured
            : currentAppUri;

    return callbackBase.replace(
      queryParameters: {
        ...callbackBase.queryParameters,
        ...currentAppUri.queryParameters,
      },
    ).removeFragment();
  }
}
