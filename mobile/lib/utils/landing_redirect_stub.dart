/// No-op on non-web platforms (there is no static landing page there).
void redirectToLanding({bool forLogout = false, String? returnTo}) {}

/// No-op on non-web platforms.
void sanitizeBrowserUrl() {}

/// No-op on non-web platforms.
void clearWebSessionData() {}

/// No-op on non-web platforms.
String? getStoredWebSessionJson() => null;

/// No-op on non-web platforms.
void syncWebAuthTokens() {}

/// No-op on non-web platforms.
void syncWebTheme() {}



