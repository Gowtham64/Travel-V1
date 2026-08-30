import 'dart:io' show Platform;
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

  bool get _isIOS => !kIsWeb && Platform.isIOS;

  Future<void> start({required String destination}) async {
    if (!_isIOS) return;
    try {
      await _channel.invokeMethod('start', {'destination': destination});
    } catch (_) {/* not available: Android, iOS < 16.1, or extension absent */}
  }

  Future<void> update({
    required String etaText,
    required double distanceLeftKm,
    required double progressPercent, // 0..1
    bool arriving = false,
  }) async {
    if (!_isIOS) return;
    try {
      await _channel.invokeMethod('update', {
        'eta': etaText,
        'distanceLeftKm': distanceLeftKm,
        'progress': progressPercent,
        'arriving': arriving,
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
