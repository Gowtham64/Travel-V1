import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'live_activity_service.dart';

/// Shows a live "trip in progress" notification while driving — an ongoing
/// progress notification on Android (lock screen + shade, like a food-delivery
/// tracker) and a local notification on iOS, driven by a small native handler
/// (MethodChannel `com.travelapp.notification`). On iOS it also drives a native
/// Live Activity (Dynamic Island + lock screen) when available.
///
/// Implemented natively (not via a plugin) so the iOS build stays on Swift
/// Package Manager and needs no CocoaPods.
class TripNotificationService {
  TripNotificationService._();
  static final TripNotificationService instance = TripNotificationService._();

  static const MethodChannel _channel = MethodChannel('com.travelapp.notification');
  bool _active = false;

  /// Begin the trip-progress notification. [destination] names the trip.
  Future<void> start({required String destination}) async {
    if (kIsWeb) return;
    _active = true;
    try {
      await _channel.invokeMethod('start', {'destination': destination});
    } catch (_) {/* channel not wired on this platform */}
    await LiveActivityService.instance.start(destination: destination);
  }

  /// Update the live notification with the latest ETA / distance / progress.
  Future<void> update({
    required String destination,
    required String etaText,
    required double distanceLeftKm,
    required double progressPercent, // 0..1
    required double speedKmh,
    bool arriving = false,
  }) async {
    if (kIsWeb || !_active) return;
    try {
      await _channel.invokeMethod('update', {
        'destination': destination,
        'eta': etaText,
        'distanceLeftKm': distanceLeftKm,
        'progress': progressPercent.clamp(0.0, 1.0),
        'speedKmh': speedKmh,
        'arriving': arriving,
      });
    } catch (_) {/* no-op */}
    await LiveActivityService.instance.update(
      etaText: arriving ? 'Arrived' : etaText,
      distanceLeftKm: distanceLeftKm,
      progressPercent: progressPercent.clamp(0.0, 1.0),
      arriving: arriving,
    );
  }

  /// Clear the notification when navigation ends.
  Future<void> end() async {
    if (kIsWeb) return;
    _active = false;
    try {
      await _channel.invokeMethod('end');
    } catch (_) {/* no-op */}
    await LiveActivityService.instance.end();
  }
}
