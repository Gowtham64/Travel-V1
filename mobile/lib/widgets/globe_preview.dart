// Conditional export: real Mapbox globe on web, inert placeholder elsewhere.
export 'globe_preview_stub.dart'
    if (dart.library.html) 'globe_preview_web.dart';
