import 'dart:html' as html;

/// Returns to the static landing page after the Flutter app has completed the
/// SDK-owned sign-out. No auth storage is read, copied or cleared here.
void redirectToLanding({bool forLogout = false, String? returnTo}) {
  final base = Uri.base;
  final segments =
      base.pathSegments.where((segment) => segment.isNotEmpty).toList();
  if (segments.isNotEmpty && segments.last == 'app') {
    segments.removeLast();
  }
  final path = segments.isEmpty ? '/' : '/${segments.join('/')}/';
  html.window.location.assign('${base.origin}$path');
}

/// Symmetrically bridges the visual theme between the static landing page and
/// Flutter's SharedPreferences key. Authentication never uses this bridge.
void syncWebTheme() {
  try {
    final storage = html.window.localStorage;
    final landingTheme = storage['voyplan_theme'];
    final flutterTheme = storage['flutter.voyplan.theme_mode'];

    if ((landingTheme == null || landingTheme.isEmpty) &&
        (flutterTheme == null || flutterTheme.isEmpty)) {
      return;
    }

    if (landingTheme != null &&
        landingTheme.isNotEmpty &&
        (flutterTheme == null || flutterTheme.isEmpty)) {
      storage['flutter.voyplan.theme_mode'] = landingTheme;
      return;
    }

    if (flutterTheme != null &&
        flutterTheme.isNotEmpty &&
        (landingTheme == null || landingTheme.isEmpty)) {
      storage['voyplan_theme'] = flutterTheme;
    }
  } catch (_) {}
}
