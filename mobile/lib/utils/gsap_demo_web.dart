import 'dart:html' as html;

/// The GSAP demo page is available on the web build.
bool get gsapDemoSupported => true;

/// Hand the itinerary to the GSAP demo page (same origin) via localStorage,
/// then open it. The Flutter app is at `<base>/app/`; the demo page sits one
/// level up at `<base>/demo.html`.
void openGsapDemo(String jsonData) {
  try {
    html.window.localStorage['voyplan_demo'] = jsonData;
  } catch (_) {}
  final base = Uri.base;
  final segs = base.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.isNotEmpty && segs.last == 'app') segs.removeLast();
  final path = segs.isEmpty ? '/' : '/${segs.join('/')}/';
  final target = '${base.origin}${path}demo.html';
  html.window.open(target, '_blank');
}
