import 'dart:convert';
import 'dart:html' as html;

/// Clears cached browser session data from localStorage and sessionStorage
/// so the static landing page does not automatically resume the old session.
void clearWebSessionData() {
  try {
    final storage = html.window.localStorage;
    storage.remove('sb-dtemayjpttktntooxraa-auth-token');
    storage.remove('flutter.sb-dtemayjpttktntooxraa-auth-token');
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
///
/// [returnTo] is kept only when it points back into this site's `/app/` area.
/// It lets the landing page resume a protected deep link after sign-in without
/// becoming an open redirect.
void redirectToLanding({bool forLogout = false, String? returnTo}) {
  final base = Uri.base;
  final segs = base.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.isNotEmpty && segs.last == 'app') segs.removeLast();
  final path = segs.isEmpty ? '/' : '/${segs.join('/')}/';
  final params = <String, String>{if (forLogout) 'logout': 'true'};
  if (returnTo != null && returnTo.isNotEmpty) {
    final candidate = Uri.tryParse(returnTo);
    if (candidate != null &&
        candidate.origin == base.origin &&
        candidate.path.startsWith('/app/')) {
      params['returnTo'] =
          candidate.path + (candidate.hasQuery ? '?${candidate.query}' : '');
    }
  }
  final query = params.isEmpty ? '' : '?${Uri(queryParameters: params).query}';
  final target = '${base.origin}$path$query';
  html.window.location.href = target;
}

/// Removes retired hand-off data and guest bypass flags from the browser URL.
/// The active Supabase session stays in its canonical same-origin storage key.
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

/// Returns any valid stored session JSON string found in browser localStorage.
String? getStoredWebSessionJson() {
  try {
    final storage = html.window.localStorage;
    const kBase = 'sb-dtemayjpttktntooxraa-auth-token';
    const kFlutter = 'flutter.$kBase';

    final candidateKeys = <String>[kBase, kFlutter];
    for (final key in storage.keys) {
      if ((key.startsWith('sb-') && key.endsWith('-auth-token')) ||
          (key.startsWith('flutter.sb-') && key.endsWith('-auth-token'))) {
        if (!candidateKeys.contains(key)) {
          candidateKeys.add(key);
        }
      }
    }

    for (final key in candidateKeys) {
      final raw = storage[key];
      if (raw != null && raw.isNotEmpty && raw != 'null' && raw != 'undefined') {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map &&
              decoded['access_token'] != null &&
              decoded['user'] != null) {
            return raw;
          }
        } catch (_) {}
      }
    }
  } catch (_) {}
  return null;
}

/// Symmetrically bridges session between the landing page's @supabase/supabase-js
/// storage key ('sb-dtemayjpttktntooxraa-auth-token') and Flutter Web SharedPreferences
/// key ('flutter.sb-dtemayjpttktntooxraa-auth-token').
void syncWebAuthTokens() {
  try {
    const kBase = 'sb-dtemayjpttktntooxraa-auth-token';
    const kFlutter = 'flutter.$kBase';
    final storage = html.window.localStorage;
    final sBase = storage[kBase];
    final sFlutter = storage[kFlutter];

    if ((sBase == null || sBase == 'null' || sBase.isEmpty) &&
        (sFlutter == null || sFlutter == 'null' || sFlutter.isEmpty)) {
      return;
    }

    if (sBase != null && sBase.isNotEmpty && sBase != 'null' &&
        (sFlutter == null || sFlutter.isEmpty || sFlutter == 'null')) {
      storage[kFlutter] = sBase;
      return;
    }
    if (sFlutter != null && sFlutter.isNotEmpty && sFlutter != 'null' &&
        (sBase == null || sBase.isEmpty || sBase == 'null')) {
      storage[kBase] = sFlutter;
      return;
    }

    if (sBase != null && sFlutter != null && sBase != sFlutter) {
      int expBase = 0;
      int expFlutter = 0;
      try {
        final bObj = jsonDecode(sBase);
        if (bObj is Map) expBase = (bObj['expires_at'] as num?)?.toInt() ?? 0;
      } catch (_) {}
      try {
        final fObj = jsonDecode(sFlutter);
        if (fObj is Map) expFlutter = (fObj['expires_at'] as num?)?.toInt() ?? 0;
      } catch (_) {}

      if (expBase >= expFlutter && expBase > 0) {
        storage[kFlutter] = sBase;
      } else if (expFlutter > expBase) {
        storage[kBase] = sFlutter;
      }
    }
  } catch (_) {}
}


