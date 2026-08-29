import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import '../models/trip_models.dart';
import '../models/vehicles_data.dart';
import '../config/app_config.dart';

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

  /// The signed-in user's saved vehicles, mapped to VehicleModel for the
  /// planners' vehicle pickers. Returns [] for guests or on any error.
  Future<List<VehicleModel>> savedVehicles() async {
    try {
      final rows = await accountList('vehicles');
      return rows.map((r) {
        final t = (r['type'] ?? 'car').toString().toLowerCase();
        return VehicleModel(
          id: 'saved_${r['id']}',
          name: (r['name'] ?? 'My vehicle').toString(),
          type: t.contains('bike') || t.contains('motor') ? 'motorcycle' : 'car',
          mileage: double.tryParse('${r['mileage_kmpl'] ?? ''}') ?? 15,
          tankCapacity: double.tryParse('${r['tank_liters'] ?? ''}') ?? 40,
        );
      }).toList();
    } catch (_) {
      return [];
    }
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
    // Prefer client-side Mapbox geocoding: the app's Mapbox token is typically
    // URL-restricted to this web origin, so it works from the browser but is
    // Forbidden (403) from the backend — and the backend's Nominatim fallback
    // gets rate-limited (429) on shared cloud IPs. Going direct avoids both.
    if (AppConfig.hasMapboxToken) {
      final gp = await _geocodeWithMapbox(address);
      if (gp != null) return gp;
    }

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

  /// AllTrails-style discovery: hiking/trekking trails near a point, nearest first.
  Future<List<Trek>> searchTreks({
    required double lat,
    required double lng,
    double radiusMeters = 20000,
    int limit = 20,
  }) async {
    final uri = Uri.parse('$baseUrl/api/treks').replace(queryParameters: {
      'lat': lat.toString(),
      'lng': lng.toString(),
      'radius': radiusMeters.round().toString(),
      'limit': limit.toString(),
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 60), onTimeout: () {
      throw ApiException('Server is waking up (can take up to 60s). Please try again in a moment!');
    });
    if (response.statusCode != 200) {
      throw ApiException('Trek search failed (${response.statusCode})');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['treks'] as List? ?? [])
        .map((e) => Trek.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Geocode directly against Mapbox from the client. Returns null on any error
  /// or no match so the caller can fall back to the backend geocoder.
  Future<GeoPoint?> _geocodeWithMapbox(String address) async {
    try {
      final uri = Uri.parse(
              'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(address)}.json')
          .replace(queryParameters: {
        'access_token': AppConfig.mapboxToken,
        'limit': '1',
        'language': 'en',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final features = body['features'] as List? ?? [];
      if (features.isEmpty) return null;
      final f = features.first as Map<String, dynamic>;
      final center = f['center'] as List; // [lng, lat]
      return GeoPoint(
        lat: (center[1] as num).toDouble(),
        lng: (center[0] as num).toDouble(),
        name: (f['place_name'] as String?) ?? address,
      );
    } catch (_) {
      return null;
    }
  }

  /// Lazily fetch one trail's line geometry (kept out of the discovery list so
  /// that stays fast). Returns the ordered points and measured length in km.
  Future<({List<LatLng> path, double? lengthKm})> fetchTrekGeometry(String id) async {
    final uri = Uri.parse('$baseUrl/api/treks/geometry').replace(queryParameters: {'id': id});
    final response = await http.get(uri).timeout(const Duration(seconds: 60), onTimeout: () {
      throw ApiException('Trail is taking too long to load. Try again in a moment.');
    });
    if (response.statusCode != 200) {
      throw ApiException('Trail geometry failed (${response.statusCode})');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final path = (body['path'] as List? ?? [])
        .map((e) => LatLng(((e as Map)['lat'] as num).toDouble(), (e['lng'] as num).toDouble()))
        .toList();
    return (path: path, lengthKm: (body['lengthKm'] as num?)?.toDouble());
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
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'coordinates': sampledCoords.map((c) => {'lat': c.lat, 'lng': c.lng}).toList(),
            'categories': categories,
          }),
        )
        .timeout(const Duration(seconds: 60), onTimeout: () {
      throw ApiException('Finding places is taking too long. Please try again.');
    });

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
    Vehicle? vehicle,
  }) async {
    final uri = Uri.parse('$baseUrl/api/trip/save');
    final response = await http
        .post(
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
            // Persist the full vehicle spec so reloaded trips recompute fuel and
            // budget with the exact numbers the user planned with, instead of a
            // type-based guess.
            if (vehicle != null) 'vehicle': vehicle.toJson(),
            if (tripStart != null) 'tripStart': tripStart.toIso8601String(),
            if (itinerary != null && itinerary.isNotEmpty) 'itinerary': itinerary,
          }),
        )
        .timeout(const Duration(seconds: 45), onTimeout: () {
      throw ApiException('Saving is taking too long (server may be waking up). Please try again.');
    });

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
    ).timeout(const Duration(seconds: 45), onTimeout: () {
      throw ApiException('Loading your trips is taking too long (server may be waking up). Please try again.');
    });

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

  /// Smart, time-blocked AI itinerary with automatic breaks + per-block reasons,
  /// plus a full trip budget (fuel + tolls + food + stay).
  Future<({List<SmartDay> days, TripBudget? budget})> aiSmartItinerary({
    required String destination,
    String startLocation = '',
    List<String> places = const [],
    String startDate = '',
    String startTime = '08:00',
    String endDate = '',
    String endTime = '',
    int durationDays = 1,
    String mode = 'balanced',
    String preferences = '',
    String directive = '',
    int travellers = 1,
    double? fuelEfficiency,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/ai/smart-itinerary'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'destination': destination,
            'startLocation': startLocation,
            'places': places,
            'startDate': startDate,
            'startTime': startTime,
            'endDate': endDate,
            'endTime': endTime,
            'durationDays': durationDays,
            'mode': mode,
            'preferences': preferences,
            'travellers': travellers,
            if (fuelEfficiency != null) 'fuelEfficiency': fuelEfficiency,
            if (directive.isNotEmpty) 'directive': directive,
          }),
        )
        .timeout(const Duration(seconds: 90));
    if (response.statusCode == 503) {
      throw ApiException("AI isn't enabled yet. Ask the server admin to configure an AI key.");
    }
    if (response.statusCode != 200) {
      // Prefer the server's human-readable message (e.g. a rate-limit notice)
      // over a bare status code.
      String msg = 'AI request failed (${response.statusCode})';
      try {
        final err = (jsonDecode(response.body) as Map)['error'];
        if (err is String && err.trim().isNotEmpty) msg = err;
      } catch (_) {/* keep the default */}
      throw ApiException(msg);
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final days = (body['days'] as List? ?? [])
        .map((e) => SmartDay.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    final budget = body['budget'] != null
        ? TripBudget.fromJson((body['budget'] as Map).cast<String, dynamic>())
        : null;
    return (days: days, budget: budget);
  }

  /// AI-suggested flight / train / hotel options for a journey (typical options,
  /// not live quotes). Returns three lists of string-keyed maps.
  Future<({List<Map<String, String>> flights, List<Map<String, String>> trains, List<Map<String, String>> hotels})>
      aiTravelOptions({
    required String to,
    String from = '',
    String startDate = '',
    int travellers = 1,
    int nights = 0,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/ai/travel-options'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'to': to,
            'from': from,
            'startDate': startDate,
            'travellers': travellers,
            'nights': nights,
          }),
        )
        .timeout(const Duration(seconds: 90));
    if (response.statusCode == 503) {
      throw ApiException("AI isn't enabled yet. Ask the server admin to configure an AI key.");
    }
    if (response.statusCode != 200) {
      String msg = 'AI request failed (${response.statusCode})';
      try {
        final err = (jsonDecode(response.body) as Map)['error'];
        if (err is String && err.trim().isNotEmpty) msg = err;
      } catch (_) {/* keep default */}
      throw ApiException(msg);
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    List<Map<String, String>> pick(String key) => (body[key] as List? ?? [])
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), (v ?? '').toString())))
        .toList();
    return (flights: pick('flights'), trains: pick('trains'), hotels: pick('hotels'));
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
