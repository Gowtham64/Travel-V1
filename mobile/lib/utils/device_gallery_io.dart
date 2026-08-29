import 'dart:typed_data';
import 'package:photo_manager/photo_manager.dart';

/// Native (Android/iOS) device gallery access via photo_manager. Lists recent
/// images from the phone's photo library so they can be shown in-app.
class DeviceGallery {
  static bool get supported => true;

  /// Request photo-library permission. Returns true if granted (full or limited).
  static Future<bool> ensurePermission() async {
    final ps = await PhotoManager.requestPermissionExtend();
    return ps.isAuth || ps.hasAccess;
  }

  /// The most recent [limit] images across the device gallery, newest first.
  static Future<List<DevicePhoto>> recent({int limit = 200}) async {
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );
    if (albums.isEmpty) return const [];
    final all = albums.first;
    final count = await all.assetCountAsync;
    if (count == 0) return const [];
    final assets = await all.getAssetListRange(start: 0, end: limit < count ? limit : count);
    return assets.map((a) => DevicePhoto(a.id, a)).toList();
  }
}

class DevicePhoto {
  final String id;
  final AssetEntity asset;
  const DevicePhoto(this.id, this.asset);

  /// A small thumbnail for grid display.
  Future<Uint8List?> thumb() =>
      asset.thumbnailDataWithSize(const ThumbnailSize(320, 320), quality: 80);

  /// Full-resolution bytes (for a full-screen view or saving into the trip).
  Future<Uint8List?> origin() => asset.originBytes;
}
