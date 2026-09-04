import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/trip_models.dart';
import '../models/car_mode_models.dart';
import 'voice_prefs.dart';
import 'car_guidance_speech_stub.dart'
    if (dart.library.html) 'dart:html' as html;

class RouteProjectionResult {
  final LatLng snappedPoint;
  final int segmentIndex;
  final double distanceFromRouteMeters;
  final double segmentBearing;
  final double progressPercent;
  final double remainingDistanceMeters;

  const RouteProjectionResult({
    required this.snappedPoint,
    required this.segmentIndex,
    required this.distanceFromRouteMeters,
    required this.segmentBearing,
    required this.progressPercent,
    required this.remainingDistanceMeters,
  });
}

class CarGuidanceService {
  final Distance _distance = const Distance();
  String? _lastAnnouncedInstruction;
  DateTime? _lastSpeechTime;
  double? _lastAnnouncedDistance;
  bool speechMuted = false;

  /// Project the vehicle's live GPS position onto the nearest road segment of the active polyline.
  RouteProjectionResult projectOnRoute(LatLng currentPos, List<GeoPoint> routePoints) {
    if (routePoints.isEmpty) {
      return RouteProjectionResult(
        snappedPoint: currentPos,
        segmentIndex: 0,
        distanceFromRouteMeters: 0,
        segmentBearing: 0,
        progressPercent: 0,
        remainingDistanceMeters: 0,
      );
    }

    if (routePoints.length == 1) {
      final single = routePoints.first.toLatLng();
      final d = _distance.as(LengthUnit.Meter, currentPos, single);
      return RouteProjectionResult(
        snappedPoint: single,
        segmentIndex: 0,
        distanceFromRouteMeters: d,
        segmentBearing: 0,
        progressPercent: 1.0,
        remainingDistanceMeters: 0,
      );
    }

    // Cumulative distances along route
    final cumulativeDistances = <double>[0.0];
    for (int i = 0; i < routePoints.length - 1; i++) {
      cumulativeDistances.add(
        cumulativeDistances[i] +
            _distance.as(LengthUnit.Meter, routePoints[i].toLatLng(), routePoints[i + 1].toLatLng()),
      );
    }
    final totalDistance = cumulativeDistances.last;

    double minDistanceToRoute = double.infinity;
    LatLng bestSnapped = currentPos;
    int bestSegmentIdx = 0;
    double bestSegT = 0.0;
    double bestBearing = 0.0;

    for (int i = 0; i < routePoints.length - 1; i++) {
      final a = routePoints[i].toLatLng();
      final b = routePoints[i + 1].toLatLng();

      final segBearing = _distance.bearing(a, b);

      // Vector from a to b in local Cartesian projection (equirectangular approximation)
      final cosLat = cos((a.latitude + b.latitude) * pi / 360.0);
      final dx = (b.longitude - a.longitude) * cosLat;
      final dy = b.latitude - a.latitude;
      final segLenSq = dx * dx + dy * dy;

      LatLng snapped;
      double t = 0.0;
      if (segLenSq < 1e-12) {
        snapped = a;
        t = 0.0;
      } else {
        final pX = (currentPos.longitude - a.longitude) * cosLat;
        final pY = currentPos.latitude - a.latitude;
        t = ((pX * dx + pY * dy) / segLenSq).clamp(0.0, 1.0);
        snapped = LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        );
      }

      final dist = _distance.as(LengthUnit.Meter, currentPos, snapped);
      if (dist < minDistanceToRoute) {
        minDistanceToRoute = dist;
        bestSnapped = snapped;
        bestSegmentIdx = i;
        bestSegT = t;
        bestBearing = segBearing;
      }
    }

    final coveredMeters = cumulativeDistances[bestSegmentIdx] +
        ((cumulativeDistances[bestSegmentIdx + 1] - cumulativeDistances[bestSegmentIdx]) * bestSegT);
    final remainingMeters = (totalDistance - coveredMeters).clamp(0.0, totalDistance);
    final progress = totalDistance > 0 ? (coveredMeters / totalDistance).clamp(0.0, 1.0) : 0.0;

    return RouteProjectionResult(
      snappedPoint: bestSnapped,
      segmentIndex: bestSegmentIdx,
      distanceFromRouteMeters: minDistanceToRoute,
      segmentBearing: bestBearing,
      progressPercent: progress,
      remainingDistanceMeters: remainingMeters,
    );
  }

  /// True when the vehicle has strayed further than [thresholdMeters] from the
  /// active route polyline.
  bool isOffRoute(LatLng currentPos, List<GeoPoint> routePoints, {double thresholdMeters = 45.0}) {
    if (routePoints.isEmpty) return false;
    final proj = projectOnRoute(currentPos, routePoints);
    return proj.distanceFromRouteMeters > thresholdMeters;
  }

  /// Computes the active turn maneuver instruction and lane-level guidance.
  ManeuverInstruction calculateManeuver({
    required LatLng currentPos,
    required List<GeoPoint> routePoints,
    required GeoPoint end,
    List<GeoPoint> waypoints = const [],
    int? activeWaypointIndex,
  }) {
    if (routePoints.isEmpty) {
      return const ManeuverInstruction(
        type: ManeuverType.destination,
        instruction: 'Arriving at destination',
        distanceMeters: 0,
      );
    }

    final proj = projectOnRoute(currentPos, routePoints);
    final closestIdx = proj.segmentIndex;

    // 1. Check distance to next intermediate waypoint
    if (waypoints.isNotEmpty && activeWaypointIndex != null && activeWaypointIndex < waypoints.length) {
      final targetWp = waypoints[activeWaypointIndex];
      final distToWp = _distance.as(LengthUnit.Meter, currentPos, targetWp.toLatLng());
      if (distToWp < 50) {
        return ManeuverInstruction(
          type: ManeuverType.waypoint,
          instruction: 'Arrive at stop: ${targetWp.name ?? "Waypoint"}',
          distanceMeters: distToWp,
          roadName: targetWp.name,
        );
      }
    }

    // 2. Check distance to final destination
    final distToEnd = _distance.as(LengthUnit.Meter, currentPos, end.toLatLng());
    if (distToEnd < 60 || closestIdx >= routePoints.length - 2) {
      return ManeuverInstruction(
        type: ManeuverType.destination,
        instruction: 'Arriving at ${end.name ?? "destination"}',
        distanceMeters: distToEnd,
        roadName: end.name,
      );
    }

    // 3. Scan forward up to 35 route points (~1.5 km) to detect next significant turn
    final lookAheadEnd = min(closestIdx + 35, routePoints.length - 1);
    double cumulativeTurnDist = 0.0;
    
    // Distance from vehicle to the end of current segment
    cumulativeTurnDist += _distance.as(
      LengthUnit.Meter,
      currentPos,
      routePoints[closestIdx + 1].toLatLng(),
    );

    for (int i = closestIdx + 1; i < lookAheadEnd; i++) {
      final p1 = routePoints[i - 1].toLatLng();
      final p2 = routePoints[i].toLatLng();
      final p3 = (i + 1 < routePoints.length) ? routePoints[i + 1].toLatLng() : p2;

      final b1 = _distance.bearing(p1, p2);
      final b2 = _distance.bearing(p2, p3);

      double angleDiff = (b2 - b1 + 360) % 360;
      if (angleDiff > 180) angleDiff -= 360;

      if (angleDiff.abs() > 22) {
        ManeuverType type;
        String action;
        LaneGuidance? laneGuidance;

        if (angleDiff > 140 || angleDiff < -140) {
          type = ManeuverType.uTurn;
          action = 'Make a U-turn';
          laneGuidance = const LaneGuidance(
            lanes: [
              LaneInfo(indications: ['u_turn', 'left'], valid: true, active: true, validIndication: 'u_turn'),
              LaneInfo(indications: ['straight'], valid: false),
              LaneInfo(indications: ['straight', 'right'], valid: false),
            ],
            instruction: 'Use left lane for U-turn',
            recommendedIndex: 0,
          );
        } else if (angleDiff > 65) {
          type = ManeuverType.turnRight;
          action = 'Turn right';
          laneGuidance = const LaneGuidance(
            lanes: [
              LaneInfo(indications: ['straight'], valid: false),
              LaneInfo(indications: ['straight', 'right'], valid: true, active: false, validIndication: 'right'),
              LaneInfo(indications: ['right'], valid: true, active: true, validIndication: 'right'),
            ],
            instruction: 'Use right lane to turn right',
            recommendedIndex: 2,
          );
        } else if (angleDiff > 22) {
          type = ManeuverType.slightRight;
          action = 'Keep right';
          laneGuidance = const LaneGuidance(
            lanes: [
              LaneInfo(indications: ['straight'], valid: true),
              LaneInfo(indications: ['slight_right', 'straight'], valid: true, active: true, validIndication: 'slight_right'),
            ],
            instruction: 'Keep right on fork',
            recommendedIndex: 1,
          );
        } else if (angleDiff < -65) {
          type = ManeuverType.turnLeft;
          action = 'Turn left';
          laneGuidance = const LaneGuidance(
            lanes: [
              LaneInfo(indications: ['left'], valid: true, active: true, validIndication: 'left'),
              LaneInfo(indications: ['left', 'straight'], valid: true, active: false, validIndication: 'left'),
              LaneInfo(indications: ['straight', 'right'], valid: false),
            ],
            instruction: 'Use left lane to turn left',
            recommendedIndex: 0,
          );
        } else {
          type = ManeuverType.slightLeft;
          action = 'Keep left';
          laneGuidance = const LaneGuidance(
            lanes: [
              LaneInfo(indications: ['slight_left', 'straight'], valid: true, active: true, validIndication: 'slight_left'),
              LaneInfo(indications: ['straight'], valid: true),
            ],
            instruction: 'Keep left on fork',
            recommendedIndex: 0,
          );
        }

        final rawName = routePoints[i].name;
        String? cleanRoadName;
        if (rawName != null && rawName.trim().isNotEmpty) {
          final trimmed = rawName.trim();
          final isLocationOrCountry = trimmed == 'Waypoint' ||
              trimmed.toLowerCase().contains('india') ||
              trimmed.toLowerCase() == (end.name ?? '').toLowerCase().trim() ||
              waypoints.any((w) => (w.name ?? '').toLowerCase().trim() == trimmed.toLowerCase());
          if (!isLocationOrCountry) {
            cleanRoadName = trimmed;
          }
        }

        final instructionText = (cleanRoadName != null)
            ? '$action onto $cleanRoadName'
            : action;

        return ManeuverInstruction(
          type: type,
          instruction: instructionText,
          distanceMeters: cumulativeTurnDist,
          roadName: cleanRoadName,
          laneGuidance: (cumulativeTurnDist <= 600) ? laneGuidance : null,
          bearing: b2,
        );
      }

      cumulativeTurnDist += _distance.as(LengthUnit.Meter, p2, p3);
    }

    // Default: continue straight
    return ManeuverInstruction(
      type: ManeuverType.straight,
      instruction: 'Continue on current route',
      distanceMeters: max(50.0, proj.remainingDistanceMeters),
      roadName: null,
    );
  }

  /// Builds ordered maneuver steps for whole route.
  List<RouteStep> buildManeuverList(List<GeoPoint> routePoints, {GeoPoint? end}) {
    final steps = <RouteStep>[];
    if (routePoints.length < 2) return steps;

    double cumulative = 0.0;
    for (int i = 0; i < routePoints.length - 1; i++) {
      final p1 = routePoints[i].toLatLng();
      final p2 = routePoints[i + 1].toLatLng();
      cumulative += _distance.as(LengthUnit.Meter, p1, p2);

      if (i + 2 >= routePoints.length) break;
      final p3 = routePoints[i + 2].toLatLng();
      final b1 = _distance.bearing(p1, p2);
      final b2 = _distance.bearing(p2, p3);
      double angleDiff = (b2 - b1 + 360) % 360;
      if (angleDiff > 180) angleDiff -= 360;
      if (angleDiff.abs() <= 22) continue;

      ManeuverType type;
      String action;
      if (angleDiff > 65) {
        type = ManeuverType.turnRight;
        action = 'Turn right';
      } else if (angleDiff > 22) {
        type = ManeuverType.slightRight;
        action = 'Slight right';
      } else if (angleDiff < -65) {
        type = ManeuverType.turnLeft;
        action = 'Turn left';
      } else {
        type = ManeuverType.slightLeft;
        action = 'Slight left';
      }

      final roadName = routePoints[i + 1].name;
      final inst = (roadName != null && roadName.isNotEmpty && roadName != 'Waypoint')
          ? '$action onto $roadName'
          : action;

      steps.add(RouteStep(
        maneuver: ManeuverInstruction(
          type: type,
          instruction: inst,
          distanceMeters: 0,
          roadName: roadName,
          bearing: b2,
        ),
        location: routePoints[i + 1],
        distanceFromStartMeters: cumulative,
      ));
    }

    final dest = end ?? routePoints.last;
    steps.add(RouteStep(
      maneuver: ManeuverInstruction(
        type: ManeuverType.destination,
        instruction: 'Arrive at ${dest.name ?? "destination"}',
        distanceMeters: 0,
        roadName: dest.name,
      ),
      location: dest,
      distanceFromStartMeters: cumulative,
    ));
    return steps;
  }

  /// Trigger voice announcement for maneuver at appropriate distance milestones.
  void announceManeuver(ManeuverInstruction maneuver, {bool force = false}) {
    if (speechMuted && !force) return;

    final dist = maneuver.distanceMeters;
    String phrase;

    if (maneuver.type == ManeuverType.destination) {
      phrase = 'Arriving at ${maneuver.roadName ?? "your destination"}';
    } else if (maneuver.type == ManeuverType.straight) {
      phrase = maneuver.instruction;
    } else if (dist <= 30) {
      phrase = '${maneuver.instruction} now';
    } else if (dist <= 250) {
      phrase = 'In ${(dist / 10).round() * 10} meters, ${maneuver.instruction.toLowerCase()}';
    } else if (dist >= 950 && dist <= 1050) {
      phrase = 'In 1 kilometer, ${maneuver.instruction.toLowerCase()}';
    } else if (dist >= 450 && dist <= 550) {
      phrase = 'In 500 meters, ${maneuver.instruction.toLowerCase()}';
    } else {
      phrase = '${maneuver.instruction} in ${maneuver.formattedDistance}';
    }

    final now = DateTime.now();

    // Prevent repeated speech of identical text within 6 seconds unless distance changed notably
    if (!force &&
        _lastAnnouncedInstruction == phrase &&
        _lastSpeechTime != null &&
        now.difference(_lastSpeechTime!).inSeconds < 6) {
      return;
    }

    _lastAnnouncedInstruction = phrase;
    _lastSpeechTime = now;
    _lastAnnouncedDistance = dist;

    _speak(phrase);
  }

  dynamic _cachedVoice;
  bool _voiceListenerAttached = false;

  void primeVoices() {
    if (!kIsWeb) return;
    try {
      final dynamic synth = html.window.speechSynthesis;
      if (synth == null) return;
      _cachedVoice ??= _pickSoftVoice(synth);
      if (_cachedVoice == null && !_voiceListenerAttached) {
        _voiceListenerAttached = true;
        try {
          synth.addEventListener('voiceschanged', (_) {
            _cachedVoice ??= _pickSoftVoice(synth);
          });
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _speak(String text) {
    try {
      if (kIsWeb) {
        final synth = html.window.speechSynthesis;
        if (synth != null) {
          final utterance = html.SpeechSynthesisUtterance(text);
          utterance.lang = 'en-US';
          utterance.rate = 0.92;
          utterance.pitch = 0.98;
          utterance.volume = 0.95;
          _cachedVoice ??= _pickSoftVoice(synth);
          if (_cachedVoice != null) utterance.voice = _cachedVoice;
          synth.speak(utterance);
        }
      }
    } catch (_) {}
  }

  dynamic _pickSoftVoice(dynamic synth) {
    try {
      final voices = synth.getVoices();
      if (voices is List && voices.isNotEmpty) {
        for (final v in voices) {
          final name = (v.name ?? '').toString().toLowerCase();
          final lang = (v.lang ?? '').toString().toLowerCase();
          if (lang.startsWith('en') &&
              (name.contains('natural') ||
                  name.contains('neural') ||
                  name.contains('samantha') ||
                  name.contains('karen') ||
                  name.contains('google us english') ||
                  name.contains('aria'))) {
            return v;
          }
        }
        for (final v in voices) {
          final lang = (v.lang ?? '').toString().toLowerCase();
          if (lang.startsWith('en')) return v;
        }
      }
    } catch (_) {}
    return null;
  }
}
