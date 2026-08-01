import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
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

  // ---------------------------------------------------------------------------
  // Account API (profile-menu features) — all require a logged-in user; RLS on
  // the server scopes every row to that user.
  // ---------------------------------------------------------------------------
  Map<String, String> _authHeaders() {
    final t = Supabase.instance.client.auth.currentSession?.accessToken;
    return {'Content-Type': 'application/json', if (t != null) 'Authorization': 'Bearer $t'};
  }

  String _accountErr(http.Response res) {
    try {
      final b = jsonDecode(res.body);
      if (b is Map && b['error'] != null) {
        final e = b['error'].toString();
        if (e.contains('does not exist') || e.contains('schema cache')) {
          return "This feature isn't set up on the server yet (run profile_schema.sql in Supabase).";
        }
        return e;
      }
    } catch (_) {}
    if (res.statusCode == 401) return 'Please log in to use this.';
    return 'Request failed (${res.statusCode})';
  }

  Future<List<Map<String, dynamic>>> accountList(String path, {String? type, String? tripId}) async {
    final qp = <String, String>{};
    if (type != null) qp['type'] = type;
    if (tripId != null) qp['trip_id'] = tripId;
    final uri = Uri.parse('$baseUrl/api/account/$path').replace(queryParameters: qp.isEmpty ? null : qp);
    final res = await http.get(uri, headers: _authHeaders()).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw ApiException(_accountErr(res));
    return (jsonDecode(res.body) as List).map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  Future<Map<String, dynamic>> accountCreate(String path, Map<String, dynamic> data) async {
    final res = await http
        .post(Uri.parse('$baseUrl/api/account/$path'), headers: _authHeaders(), body: jsonEncode(data))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200 && res.statusCode != 201) throw ApiException(_accountErr(res));
    return (jsonDecode(res.body) as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> accountUpdate(String path, String id, Map<String, dynamic> data) async {
    final res = await http
        .patch(Uri.parse('$baseUrl/api/account/$path/$id'), headers: _authHeaders(), body: jsonEncode(data))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw ApiException(_accountErr(res));
    return (jsonDecode(res.body) as Map).cast<String, dynamic>();
  }

  Future<void> accountDelete(String path, String id) async {
    final res = await http
        .delete(Uri.parse('$baseUrl/api/account/$path/$id'), headers: _authHeaders())
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw ApiException(_accountErr(res));
  }

  Future<Map<String, dynamic>> getProfile() async {
    final res = await http.get(Uri.parse('$baseUrl/api/account/profile'), headers: _authHeaders()).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw ApiException(_accountErr(res));
    return (jsonDecode(res.body) as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> putProfile(Map<String, dynamic> data) async {
    final res = await http
        .put(Uri.parse('$baseUrl/api/account/profile'), headers: _authHeaders(), body: jsonEncode(data))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw ApiException(_accountErr(res));
    return (jsonDecode(res.body) as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> convertCurrency({required String from, required String to, required double amount}) async {
    final uri = Uri.parse('$baseUrl/api/currency/convert')
        .replace(queryParameters: {'from': from, 'to': to, 'amount': '$amount'});
    final res = await http.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw ApiException(_accountErr(res));
    return (jsonDecode(res.body) as Map).cast<String, dynamic>();
  }

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
    DateTime? departAt,
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
        // Local wall-time (no timezone suffix) to match the forecast's local hours.
        if (departAt != null) 'departAt': departAt.toIso8601String(),
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
    DateTime? tripStart,
    List<Map<String, dynamic>>? itinerary,
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
        if (tripStart != null) 'tripStart': tripStart.toIso8601String(),
        if (itinerary != null && itinerary.isNotEmpty) 'itinerary': itinerary,
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

  // ───────────────────────── AI (Google Gemini via backend) ─────────────────

  List<Map<String, String>> _parseAiPlaces(http.Response response) {
    if (response.statusCode == 503) {
      throw ApiException('AI isn\'t enabled yet. Ask the server admin to set GEMINI_API_KEY.');
    }
    if (response.statusCode != 200) {
      throw ApiException('AI request failed (${response.statusCode})');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final list = (body['places'] as List?) ?? [];
    return list
        .map((e) => {
              'name': (e['name'] ?? '').toString(),
              'area': (e['area'] ?? '').toString(),
              'why': (e['why'] ?? '').toString(),
            })
        .where((m) => m['name']!.isNotEmpty)
        .toList();
  }

  /// AI: notable stops along a route (names + reasons; geocode on add).
  Future<List<Map<String, String>>> aiRecommendStops({
    required String start,
    required String end,
    List<String> waypoints = const [],
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/ai/recommend'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'start': start, 'end': end, 'waypoints': waypoints}),
        )
        .timeout(const Duration(seconds: 40));
    return _parseAiPlaces(response);
  }

  /// AI: natural-language place search, optionally anchored near a location.
  Future<List<Map<String, String>>> aiSearchPlaces({
    required String query,
    String? near,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/ai/search'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'query': query, if (near != null) 'near': near}),
        )
        .timeout(const Duration(seconds: 40));
    return _parseAiPlaces(response);
  }

  /// AI: free-form trip assistant / itinerary writer (returns text).
  /// Generates a structured, day-by-day itinerary via the backend AI.
  /// Returns a list of days: {day, title, activities:[{part, time, title, note}]}.
  Future<List<Map<String, dynamic>>> aiBuildItinerary({
    required String start,
    required String end,
    int days = 1,
    List<String> waypoints = const [],
    int travellers = 1,
    String? purpose,
    String? startDate,
    String? startTime,
    String? weather,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/ai/itinerary'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'start': start,
            'end': end,
            'days': days,
            'waypoints': waypoints,
            'travellers': travellers,
            if (purpose != null) 'purpose': purpose,
            if (startDate != null) 'startDate': startDate,
            if (startTime != null) 'startTime': startTime,
            if (weather != null && weather.isNotEmpty) 'weather': weather,
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode == 503) {
      throw ApiException("AI isn't enabled yet. Ask the server admin to configure an AI key.");
    }
    if (response.statusCode != 200) {
      throw ApiException('AI request failed (${response.statusCode})');
    }
    final list = (jsonDecode(response.body) as Map<String, dynamic>)['days'] as List? ?? [];
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  Future<String> aiAsk({
    required String question,
    Map<String, dynamic>? context,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/ai/ask'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'question': question, if (context != null) 'context': context}),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode == 503) {
      throw ApiException('AI isn\'t enabled yet. Ask the server admin to set GEMINI_API_KEY.');
    }
    if (response.statusCode != 200) {
      throw ApiException('AI request failed (${response.statusCode})');
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)['text'] as String? ?? '';
  }
}
