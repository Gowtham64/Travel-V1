import 'dart:html' as html;

/// Sends the browser to the static landing page that hosts login. The Flutter
/// app lives at `<base>/app/`; the landing page is one level up at `<base>/`.
/// Derived from the current URL so it works on GitHub Pages and localhost.
void redirectToLanding() {
  final base = Uri.base;
  final segs = base.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.isNotEmpty && segs.last == 'app') segs.removeLast();
  final path = segs.isEmpty ? '/' : '/${segs.join('/')}/';
  final target = '${base.origin}$path';
  // Avoid a redirect loop if we're somehow already there.
  if (html.window.location.href != target) {
    html.window.location.replace(target);
  }
}

/// Cleanses sensitive session tokens (#sb_refresh=...) from the browser address bar
/// immediately after session extraction to prevent history leakage.
void sanitizeBrowserUrl() {
  try {
    final loc = html.window.location;
    final path = loc.pathname ?? '/app/';
    // Preserve normal query parameters if any (except sensitive token keys)
    final search = loc.search ?? '';
    final cleanSearch = search.replaceAll(RegExp(r'[?&]sb_refresh=[^&]+'), '');
    final cleanUrl = '$path$cleanSearch';
    html.window.history.replaceState(null, '', cleanUrl);
  } catch (_) {}
}
