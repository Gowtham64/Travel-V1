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
