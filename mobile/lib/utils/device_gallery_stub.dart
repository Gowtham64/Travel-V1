import 'dart:typed_data';

/// Web stub: the browser cannot enumerate the device photo gallery, so device
/// sync is unsupported. The app falls back to pick-from-gallery there.
class DeviceGallery {
  static bool get supported => false;
  static Future<bool> ensurePermission() async => false;
  static Future<List<DevicePhoto>> recent({int limit = 200}) async => const [];
}

class DevicePhoto {
  final String id;
  const DevicePhoto(this.id);
  Future<Uint8List?> thumb() async => null;
  Future<Uint8List?> origin() async => null;
}
