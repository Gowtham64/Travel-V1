import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/trip_models.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class ApiService {
  /// Point this at your backend. Use 10.0.2.2 instead of localhost when
  /// running on the Android emulator; use your machine's LAN IP for a
  /// physical device.
  final String baseUrl;

  ApiService({this.baseUrl = 'http://localhost:3000'});

  Future<GeoPoint> geocode(String address) async {
    final uri = Uri.parse('$baseUrl/api/geocode').replace(queryParameters: {'q': address});
    final response = await http.get(uri);

    if (response.statusCode == 404) {
      throw ApiException('Could not find a location for "$address"');
    }
    if (response.statusCode != 200) {
      throw ApiException('Geocoding failed (${response.statusCode})');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return GeoPoint(lat: (body['lat'] as num).toDouble(), lng: (body['lng'] as num).toDouble());
  }

  Future<TripPlan> planTrip({
    required GeoPoint start,
    required GeoPoint end,
    List<GeoPoint> waypoints = const [],
    required Vehicle vehicle,
    double dailyDrivingHours = 7,
    List<String> includePlaces = const [],
  }) async {
    final uri = Uri.parse('$baseUrl/api/trip/plan');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'start': {'lat': start.lat, 'lng': start.lng},
        'end': {'lat': end.lat, 'lng': end.lng},
        'waypoints': waypoints.map((w) => {'lat': w.lat, 'lng': w.lng}).toList(),
        'vehicle': vehicle.toJson(),
        'dailyDrivingHours': dailyDrivingHours,
        'includePlaces': includePlaces,
      }),
    );

    if (response.statusCode != 200) {
      throw ApiException('Trip planning failed (${response.statusCode}): ${response.body}');
    }

    return TripPlan.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Map<String, List<PlaceOfInterest>>> fetchPOIs({
    required List<GeoPoint> routeCoordinates,
    required List<String> categories,
  }) async {
    final uri = Uri.parse('$baseUrl/api/trip/pois');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'coordinates': routeCoordinates.map((c) => {'lat': c.lat, 'lng': c.lng}).toList(),
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
        'waypoints': waypoints.map((w) => {'lat': w.lat, 'lng': w.lng}).toList(),
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
}
