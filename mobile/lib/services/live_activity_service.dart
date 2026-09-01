import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart bridge to the native iOS Live Activity (ActivityKit) that renders the
/// trip tracker on the lock screen and in the Dynamic Island, like a
/// food-delivery ETA card.
///
/// The native handler lives in the iOS Runner + a Widget Extension. Until that
/// is present (or on Android / iOS < 16.1), every call safely no-ops — the
/// MethodChannel throws MissingPluginException, which we swallow.
class LiveActivityService {
  LiveActivityService._();
  static final LiveActivityService instance = LiveActivityService._();

  static const MethodChannel _channel = MethodChannel('com.travelapp.liveactivity');

  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> start({
    required String destination,
    String vehicleType = 'car',
    String startPoint = 'Start',
    List<String> stops = const [],
    bool isRoundTrip = false,
  }) async {
    if (!_isIOS) return;
    try {
      await _channel.invokeMethod('start', {
        'destination': destination,
        'vehicleType': vehicleType,
        'startPoint': startPoint,
        'stops': stops,
        'isRoundTrip': isRoundTrip,
      });
    } catch (_) {/* not available: Android, iOS < 16.1, or extension absent */}
  }

  Future<void> update({
    required String etaText,
    required double distanceLeftKm,
    required double progressPercent, // 0..1
    bool arriving = false,
    String? nextStopName,
    double? nextStopDistanceKm,
    int? remainingStopsCount,
    String? currentVehicleType,
    List<String>? activeStops,
  }) async {
    if (!_isIOS) return;
    try {
      await _channel.invokeMethod('update', {
        'eta': etaText,
        'distanceLeftKm': distanceLeftKm,
        'progress': progressPercent,
        'arriving': arriving,
        if (nextStopName != null) 'nextStopName': nextStopName,
        if (nextStopDistanceKm != null) 'nextStopDistanceKm': nextStopDistanceKm,
        if (remainingStopsCount != null) 'remainingStopsCount': remainingStopsCount,
        if (currentVehicleType != null) 'currentVehicleType': currentVehicleType,
        if (activeStops != null) 'activeStops': activeStops,
      });
    } catch (_) {/* no-op */}
  }

  Future<void> end() async {
    if (!_isIOS) return;
    try {
      await _channel.invokeMethod('end');
    } catch (_) {/* no-op */}
  }
}
