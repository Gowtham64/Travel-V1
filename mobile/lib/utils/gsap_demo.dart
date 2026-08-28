// Opens the GSAP-powered trip demo page (web only). On native this is a no-op
// and callers fall back to the in-app Flutter demo. Conditional import keeps
// dart:html out of the native build.
export 'gsap_demo_stub.dart' if (dart.library.html) 'gsap_demo_web.dart';
