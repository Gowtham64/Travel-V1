import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/trip_models.dart';
import '../models/car_mode_models.dart';
// Web speech synthesis support conditionally
import 'dart:html' as html if (dart.library.io) 'car_guidance_speech_stub.dart';

class CarGuidanceService {
  final Distance _distance = const Distance();
  String? _lastAnnouncedInstruction;
  DateTime? _lastSpeechTime;
  bool speechMuted = false;

  /// Computes the current maneuver instruction for the vehicle position along the route.
  ManeuverInstruction calculateManeuver({
    required LatLng currentPos,
    required List<GeoPoint> routePoints,
    required GeoPoint end,
    List<GeoPoint> waypoints = const [],
  }) {
    if (routePoints.isEmpty) {
      return const ManeuverInstruction(
        type: ManeuverType.destination,
        instruction: 'Arriving at destination',
        distanceMeters: 0,
      );
    }

    // Find current progress index along routePoints
    int closestIdx = 0;
    double minDist = double.infinity;
    for (int i = 0; i < routePoints.length; i++) {
      final d = _distance.as(LengthUnit.Meter, currentPos, routePoints[i].toLatLng());
      if (d < minDist) {
        minDist = d;
        closestIdx = i;
      }
    }

    // Check distance to final destination
    final distToEnd = _distance.as(LengthUnit.Meter, currentPos, end.toLatLng());
    if (distToEnd < 200 || closestIdx >= routePoints.length - 2) {
      return ManeuverInstruction(
        type: ManeuverType.destination,
        instruction: 'Arriving at ${end.name ?? "destination"}',
        distanceMeters: distToEnd,
      );
    }

    // Look ahead to find significant bearing changes (turns)
    int lookAheadEnd = min(closestIdx + 15, routePoints.length - 1);
    for (int i = closestIdx; i < lookAheadEnd - 1; i++) {
      final p1 = routePoints[i].toLatLng();
      final p2 = routePoints[i + 1].toLatLng();
      final p3 = (i + 2 < routePoints.length) ? routePoints[i + 2].toLatLng() : p2;

      final b1 = _distance.bearing(p1, p2);
      final b2 = _distance.bearing(p2, p3);
      double angleDiff = (b2 - b1 + 360) % 360;
      if (angleDiff > 180) angleDiff -= 360;

      final distToTurn = _distance.as(LengthUnit.Meter, currentPos, p2);

      if (angleDiff.abs() > 25) {
        ManeuverType type;
        String action;
        if (angleDiff > 60) {
          type = ManeuverType.turnRight;
          action = 'Turn right';
        } else if (angleDiff > 25) {
          type = ManeuverType.slightRight;
          action = 'Slight right';
        } else if (angleDiff < -60) {
          type = ManeuverType.turnLeft;
          action = 'Turn left';
        } else {
          type = ManeuverType.slightLeft;
          action = 'Slight left';
        }

        return ManeuverInstruction(
          type: type,
          instruction: '$action ahead',
          distanceMeters: distToTurn,
        );
      }
    }

    // Default: Continue straight
    final nextSegmentDist = (closestIdx + 1 < routePoints.length)
        ? _distance.as(LengthUnit.Meter, currentPos, routePoints[closestIdx + 1].toLatLng())
        : 1000.0;

    return ManeuverInstruction(
      type: ManeuverType.straight,
      instruction: 'Continue straight',
      distanceMeters: max(50.0, nextSegmentDist),
    );
  }

  /// Trigger voice announcement for maneuver
  void announceManeuver(ManeuverInstruction maneuver) {
    if (speechMuted) return;

    final text = '${maneuver.instruction} in ${maneuver.formattedDistance}';
    final now = DateTime.now();

    // Prevent spamming the exact same audio instruction too frequently
    if (_lastAnnouncedInstruction == text &&
        _lastSpeechTime != null &&
        now.difference(_lastSpeechTime!).inSeconds < 10) {
      return;
    }

    _lastAnnouncedInstruction = text;
    _lastSpeechTime = now;

    _speak(text);
  }

  void _speak(String text) {
    try {
      if (kIsWeb) {
        final synth = html.window.speechSynthesis;
        if (synth != null) {
          final utterance = html.SpeechSynthesisUtterance(text);
          utterance.lang = 'en-US';
          utterance.rate = 1.0;
          synth.speak(utterance);
        }
      }
    } catch (_) {
      // Speech synthesis fallback/catch
    }
  }

  void speakCustom(String text) {
    if (speechMuted) return;
    _speak(text);
  }
}
