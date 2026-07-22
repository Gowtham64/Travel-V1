// Redirects the browser to the static landing page (which hosts login). On
// non-web platforms this is a no-op (see the stub). Uses a conditional import so
// dart:html is only pulled in for the web build.
export 'landing_redirect_stub.dart'
    if (dart.library.html) 'landing_redirect_web.dart';
