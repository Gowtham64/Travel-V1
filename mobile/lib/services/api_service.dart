import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:http/http.dart' as http;
import '../models/trip_models.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class ApiService {
  /// Backend endpoint.
  ///
  /// Web builds and release builds always use the hosted backend. Only a
  /// local debug run on the Android emulator falls back to `10.0.2.2:3000`
  /// (use your machine's LAN IP for a physical device). Pass [baseUrl]
  /// explicitly to override for local development.
  final String baseUrl;

  static const String _prodBackend = 'https://travel-v1-mzia.onrender.com';

  ApiService({String? baseUrl})
      : baseUrl = baseUrl ??
            ((kIsWeb || kReleaseMode) ? _prodBackend : 'http://10.0.2.2:3000');

  Future<GeoPoint> geocode(String address) async {
    final uri = Uri.parse('$baseUrl/api/geocode').replace(queryParameters: {'q': address});
    final response = await http.get(uri).timeout(const Duration(seconds: 60), onTimeout: () {
      throw ApiException('Server is waking up (can take up to 60s). Please try again in a moment!');
    });

    if (response.statusCode == 404) {
      throw ApiException('Could not find a location for "$address"');
    }
    if (response.statusCode != 200) {
      throw ApiException('Geocoding failed (${response.statusCode})');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return GeoPoint(
      lat: (body['lat'] as num).toDouble(),
      lng: (body['lng'] as num).toDouble(),
      name: body['displayName'] as String? ?? address,
    );
  }

  Future<TripPlan> planTrip({
    required GeoPoint start,
    required GeoPoint end,
    List<GeoPoint> waypoints = const [],
    required Vehicle vehicle,
    double dailyDrivingHours = 7,
    int travellers = 1,
    List<String> includePlaces = const [],
  }) async {
    final uri = Uri.parse('$baseUrl/api/trip/plan');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'start': {'lat': start.lat, 'lng': start.lng},
        'end': {'lat': end.lat, 'lng': end.lng},
        'waypoints': waypoints.map((w) => {'lat': w.lat, 'lng': w.lng, 'name': w.name}).toList(),
        'vehicle': {
          'type': vehicle.type,
          'efficiencyKmPerLiter': vehicle.efficiencyKmPerLiter,
          'tankCapacityLiters': vehicle.tankCapacityLiters,
          'currentFuelLiters': vehicle.currentFuelLiters,
        },
        'dailyDrivingHours': dailyDrivingHours,
        'travellers': travellers,
        'includePlaces': includePlaces,
      }),
    ).timeout(const Duration(seconds: 90), onTimeout: () {
      throw ApiException('Server is generating your plan (can take up to 90s). Please try again if it fails!');
    });

    if (response.statusCode != 200) {
      throw ApiException('Trip planning failed (${response.statusCode}): ${response.body}');
    }

    return TripPlan.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Map<String, List<PlaceOfInterest>>> fetchPOIs({
    required List<GeoPoint> routeCoordinates,
    required List<String> categories,
  }) async {
    // Downsample coordinates if there are too many to keep payload size small (resolves 413 Payload Too Large)
    List<GeoPoint> sampledCoords = routeCoordinates;
    if (sampledCoords.length > 150) {
      final step = (sampledCoords.length / 150).ceil();
      sampledCoords = [];
      for (int i = 0; i < routeCoordinates.length; i += step) {
        sampledCoords.add(routeCoordinates[i]);
      }
      if (sampledCoords.isEmpty || sampledCoords.last != routeCoordinates.last) {
        sampledCoords.add(routeCoordinates.last);
      }
    }

    final uri = Uri.parse('$baseUrl/api/trip/pois');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'coordinates': sampledCoords.map((c) => {'lat': c.lat, 'lng': c.lng}).toList(),
        'categories': categories,
      }),
    );

    if (response.statusCode != 200) {
      throw ApiException('Fetching POIs failed (${response.statusCode}): ${response.body}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final placesJson = body['places'] as Map<String, dynamic>? ?? {};

    return placesJson.map(
      (key, value) => MapEntry(
        key,
        (value as List).map((e) => PlaceOfInterest.fromJson(e as Map<String, dynamic>)).toList(),
      ),
    );
  }

  Future<void> saveTrip({
    required String name,
    required GeoPoint start,
    required GeoPoint end,
    List<GeoPoint> waypoints = const [],
    required String vehicleType,
    required String token,
  }) async {
    final uri = Uri.parse('$baseUrl/api/trip/save');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'name': name,
        'startPoint': {'lat': start.lat, 'lng': start.lng},
        'endPoint': {'lat': end.lat, 'lng': end.lng},
        'waypoints': waypoints.map((w) => {'lat': w.lat, 'lng': w.lng, 'name': w.name}).toList(),
        'vehicleType': vehicleType,
      }),
    );

    if (response.statusCode != 200) {
      throw ApiException('Saving trip failed (${response.statusCode}): ${response.body}');
    }
  }

  Future<List<dynamic>> getSavedTrips(String token) async {
    final uri = Uri.parse('$baseUrl/api/trip/saved');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      throw ApiException('Fetching trips failed (${response.statusCode}): ${response.body}');
    }

    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<String?> reverseGeocode(double lat, double lng) async {
    final uri = Uri.parse('$baseUrl/api/trip/reverse-geocode?lat=$lat&lng=$lng');
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['address'] as String?;
      }
    } catch (_) {
      // Ignore and fallback to null
    }
    return null;
  }
}
