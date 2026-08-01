import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/trip_models.dart';
import '../models/car_mode_models.dart';
import 'voice_prefs.dart';
// Web speech synthesis support, conditionally. The stub is the default so native
// builds never reference dart:html; only web (dart.library.html) pulls dart:html.
import 'car_guidance_speech_stub.dart'
    if (dart.library.html) 'dart:html' as html;

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

  /// Builds the full ordered list of maneuvers for the whole route, so the car
  /// screen (CarPlay `CPTrip`/`CPRouteChoice`, Android Auto step list) can show
  /// upcoming turns ahead of time rather than only the single next maneuver.
  /// Detects significant bearing changes and records each turn's location and
  /// cumulative distance from the start.
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
      if (angleDiff.abs() <= 25) continue;

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

      steps.add(RouteStep(
        maneuver: ManeuverInstruction(type: type, instruction: action, distanceMeters: 0),
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
      ),
      location: dest,
      distanceFromStartMeters: cumulative,
    ));
    return steps;
  }

  /// True when the vehicle has strayed further than [thresholdMeters] from the
  /// nearest point on the planned route — the signal to request a reroute.
  bool isOffRoute(LatLng currentPos, List<GeoPoint> routePoints,
      {double thresholdMeters = 50}) {
    if (routePoints.isEmpty) return false;
    double minDist = double.infinity;
    for (final p in routePoints) {
      final d = _distance.as(LengthUnit.Meter, currentPos, p.toLatLng());
      if (d < minDist) minDist = d;
    }
    return minDist > thresholdMeters;
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

  // Cached soft voice + one-time listener so we don't re-scan on every prompt
  // and don't get stuck with the robotic default before voices finish loading.
  dynamic _cachedVoice;
  bool _voiceListenerAttached = false;

  /// Warms up the browser's voice list so the *first* spoken prompt already
  /// uses the soft voice. Browsers load voices asynchronously, so we grab them
  /// now and also listen for `voiceschanged` to fill the cache when ready.
  /// Safe to call multiple times; no-op off the web.
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
        } catch (_) {/* older browsers: getVoices will fill in on later calls */}
      }
    } catch (_) {/* speechSynthesis unavailable */}
  }

  void _speak(String text) {
    try {
      if (kIsWeb) {
        final synth = html.window.speechSynthesis;
        if (synth != null) {
          final utterance = html.SpeechSynthesisUtterance(text);
          utterance.lang = 'en-US';
          // Gentle, unhurried delivery: slower than default with a slightly
          // lower pitch and softened volume reads as calm and smooth.
          utterance.rate = 0.9;
          utterance.pitch = 0.95;
          utterance.volume = 0.9;
          _cachedVoice ??= _pickSoftVoice(synth);
          if (_cachedVoice != null) utterance.voice = _cachedVoice;
          synth.speak(utterance);
        }
      }
    } catch (_) {
      // Speech synthesis fallback/catch
    }
  }

  /// Prefer a natural / neural English voice for a smoother, softer sound.
  /// Returns null while the browser is still loading its voice list. Runs only
  /// on web (dynamic JS types).
  dynamic _pickSoftVoice(dynamic synth) {
    try {
      final voices = synth.getVoices();
      if (voices == null) return null;
      final list = [];
      final names = <String>[];
      final langs = <String>[];
      for (final v in voices) {
        list.add(v);
        names.add((v.name as String?) ?? '');
        langs.add((v.lang as String?) ?? '');
      }
      if (list.isEmpty) return null;
      final idx = bestVoiceIndex(names, langs);
      return idx >= 0 ? list[idx] : null;
    } catch (_) {/* voices may not be ready yet */}
    return null;
  }

  void speakCustom(String text) {
    if (speechMuted) return;
    _speak(text);
  }
}
