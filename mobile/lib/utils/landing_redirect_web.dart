import 'dart:convert';
import 'dart:html' as html;

/// Clears cached browser session data from localStorage and sessionStorage
/// so the static landing page does not automatically resume the old session.
void clearWebSessionData() {
  try {
    final storage = html.window.localStorage;
    final keysToRemove = <String>[];
    for (final key in storage.keys) {
      if (key.startsWith('sb-') ||
          key.contains('supabase') ||
          key.contains('auth-token') ||
          key.contains('guest') ||
          key.contains('voyplan')) {
        keysToRemove.add(key);
      }
    }
    for (final key in keysToRemove) {
      storage.remove(key);
    }
  } catch (_) {}

  try {
    final session = html.window.sessionStorage;
    final keysToRemove = <String>[];
    for (final key in session.keys) {
      if (key.startsWith('sb-') ||
          key.contains('supabase') ||
          key.contains('auth-token') ||
          key.contains('guest') ||
          key.contains('voyplan')) {
        keysToRemove.add(key);
      }
    }
    for (final key in keysToRemove) {
      session.remove(key);
    }
  } catch (_) {}

  try {
    html.window.history.replaceState(null, '', '/app/');
  } catch (_) {}
}

/// Sends the browser to the static landing page that hosts login. The Flutter
/// app lives at `<base>/app/`; the landing page is one level up at `<base>/`.
/// If [forLogout] is true, appends `?logout=true` so the landing page purges its JS client session.
void redirectToLanding({bool forLogout = false}) {
  final base = Uri.base;
  final segs = base.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.isNotEmpty && segs.last == 'app') segs.removeLast();
  final path = segs.isEmpty ? '/' : '/${segs.join('/')}/';
  final query = forLogout ? '?logout=true' : '';
  final target = '${base.origin}$path$query';
  html.window.location.href = target;
}

/// Cleanses sensitive session tokens (#sb_refresh=...) and guest bypass flags from the browser address bar
/// immediately after session extraction to prevent history leakage.
void sanitizeBrowserUrl() {
  try {
    final loc = html.window.location;
    final path = loc.pathname ?? '/app/';
    final search = loc.search ?? '';
    var cleanSearch = search
        .replaceAll(RegExp(r'[?&]sb_refresh=[^&]+'), '')
        .replaceAll(RegExp(r'[?&]guest=[^&]+'), '');
    if (cleanSearch == '?' || cleanSearch == '&') cleanSearch = '';
    final cleanUrl = '$path$cleanSearch';
    html.window.history.replaceState(null, '', cleanUrl);
  } catch (_) {}
}

/// Retrieves stored Supabase session refresh token from browser localStorage
/// to seamlessly hydrate auth state without requiring URL query fragments.
String? getStoredWebSessionRefreshToken() {
  try {
    final storage = html.window.localStorage;
    // 1. Direct key saved by landing page
    final direct = storage['sb_refresh_token'];
    if (direct != null && direct.isNotEmpty) return direct;

    // 2. Search for standard Supabase token keys
    for (final entry in storage.entries) {
      if ((entry.key.startsWith('sb-') || entry.key.contains('supabase')) &&
          (entry.key.endsWith('-auth-token') || entry.key.contains('token'))) {
        try {
          final data = jsonDecode(entry.value);
          if (data is Map) {
            final refresh = data['refresh_token'] ??
                (data['currentSession'] is Map
                    ? data['currentSession']['refresh_token']
                    : null);
            if (refresh is String && refresh.isNotEmpty) {
              return refresh;
            }
          }
        } catch (_) {}
      }
    }
  } catch (_) {}
  return null;
}
