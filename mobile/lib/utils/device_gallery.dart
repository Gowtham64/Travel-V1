// Device photo-gallery access, isolated behind a conditional import so the
// native-only `photo_manager` plugin is never compiled into the web build.
//
// Web  -> device_gallery_stub.dart  (unsupported; pick-from-gallery only)
// Native (Android/iOS) -> device_gallery_io.dart (real gallery via photo_manager)
export 'device_gallery_stub.dart' if (dart.library.io) 'device_gallery_io.dart';
