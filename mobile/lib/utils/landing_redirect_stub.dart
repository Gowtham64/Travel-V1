/// No-op on non-web platforms (there is no static landing page there).
void redirectToLanding({bool forLogout = false}) {}

/// No-op on non-web platforms.
void sanitizeBrowserUrl() {}

/// No-op on non-web platforms.
void clearWebSessionData() {}
