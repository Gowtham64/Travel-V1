import 'package:flutter/services.dart';
import '../models/trip_models.dart';
import '../models/car_mode_models.dart';

/// Platform channel interface bridge for sending trip & maneuver updates
/// to native iOS CarPlay (CPMapTemplate) and Android Auto (androidx.car.app).
class CarPlatformChannel {
  static const MethodChannel _channel = MethodChannel('com.travelapp.car');

  static VoidCallback? onCarStopNavigation;
  static bool _handlerInstalled = false;

  /// Initialize bidirectional listeners from car head unit
  static void initialize() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'stopNavigationFromCar') {
        onCarStopNavigation?.call();
      }
    });
  }

  /// Send active route setup to native car module
  static Future<void> setRoute({
    required GeoPoint start,
    required GeoPoint end,
    required List<GeoPoint> waypoints,
    required List<GeoPoint> routeCoordinates,
    List<RefuelStop>? fuelStops,
    String? destinationName,
  }) async {
    initialize();
    try {
      await _channel.invokeMethod('setRoute', {
        'start': {'lat': start.lat, 'lng': start.lng, 'name': start.name ?? 'Start'},
        'end': {'lat': end.lat, 'lng': end.lng, 'name': destinationName ?? end.name ?? 'Destination'},
        'waypoints': waypoints.map((w) => {
          'lat': w.lat,
          'lng': w.lng,
          'name': w.name ?? '',
          'isFuelStop': w.isFuelStop,
        }).toList(),
        'coordinates': routeCoordinates.map((c) => {'lat': c.lat, 'lng': c.lng}).toList(),
        if (fuelStops != null)
          'fuelStops': fuelStops.map((f) => {
            'name': f.name,
            'lat': f.lat,
            'lng': f.lng,
            'fuelType': f.fuelType,
            'refillLiters': f.refillLiters,
            'estimatedCost': f.estimatedCost,
            'distanceFromStartKm': f.distanceFromStartKm,
          }).toList(),
      });
    } catch (_) {
      // Channel fallback when running on web or non-car head unit environments
    }
  }

  /// Send telemetry and maneuver guidance updates to car screen
  static Future<void> updateNavigation({
    required ManeuverInstruction maneuver,
    required CarTelemetry telemetry,
    double? currentLat,
    double? currentLng,
    double? bearingDeg,
    String? roadName,
    RefuelStop? nextFuelStop,
  }) async {
    initialize();
    try {
      await _channel.invokeMethod('updateNavigation', {
        'instruction': maneuver.instruction,
        'maneuverType': maneuver.type.name,
        'distanceMeters': maneuver.distanceMeters,
        'formattedDistance': maneuver.formattedDistance,
        'speedKmh': telemetry.speedKmh,
        'remainingDistanceKm': telemetry.remainingDistanceKm,
        'remainingDurationMin': telemetry.remainingDurationMin,
        'formattedEta': telemetry.formattedEta,
        if (roadName != null) 'roadName': roadName,
        // Live position + heading so the car map can follow the vehicle in real time.
        if (currentLat != null) 'currentLat': currentLat,
        if (currentLng != null) 'currentLng': currentLng,
        if (bearingDeg != null) 'bearingDeg': bearingDeg,
        if (nextFuelStop != null)
          'nextFuelStop': {
            'name': nextFuelStop.name,
            'lat': nextFuelStop.lat,
            'lng': nextFuelStop.lng,
            'fuelType': nextFuelStop.fuelType,
            'refillLiters': nextFuelStop.refillLiters,
            'estimatedCost': nextFuelStop.estimatedCost,
            'distanceFromStartKm': nextFuelStop.distanceFromStartKm,
          },
      });
    } catch (_) {
      // Channel fallback
    }
  }

  /// Trigger navigation audio voice guidance on Android Auto / native audio focus
  static Future<void> speakNavigation(String text) async {
    initialize();
    try {
      await _channel.invokeMethod('speakNavigation', {'text': text});
    } catch (_) {
      // Channel fallback
    }
  }

  /// Notify car module when navigation stops/resumes
  static Future<void> setNavigationState({required bool isNavigating}) async {
    initialize();
    try {
      await _channel.invokeMethod('setNavigationState', {'isNavigating': isNavigating});
    } catch (_) {
      // Channel fallback
    }
  }
}
