import 'dart:convert';
import 'dart:math' as math;
import 'dart:math' show cos, sin, asin, sqrt;
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import '../models/trip_models.dart';
import '../models/vehicles_data.dart';
import '../config/app_config.dart';
import '../data/temple_database.dart';

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

  String _localStoreKey(String path, {String? type}) => 'voy_account_${path}_${type ?? 'all'}';

  Future<List<Map<String, dynamic>>> _loadLocalItems(String path, {String? type}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_localStoreKey(path, type: type));
      if (raw != null) {
        return (jsonDecode(raw) as List).map((e) => (e as Map).cast<String, dynamic>()).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _saveLocalItems(String path, List<Map<String, dynamic>> items, {String? type}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_localStoreKey(path, type: type), jsonEncode(items));
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> accountList(String path, {String? type, String? tripId}) async {
    try {
      final qp = <String, String>{};
      if (type != null) qp['type'] = type;
      if (tripId != null) qp['trip_id'] = tripId;
      final uri = Uri.parse('$baseUrl/api/account/$path').replace(queryParameters: qp.isEmpty ? null : qp);
      final res = await http.get(uri, headers: _authHeaders()).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final list = (jsonDecode(res.body) as List).map((e) => (e as Map).cast<String, dynamic>()).toList();
        await _saveLocalItems(path, list, type: type);
        return list;
      }
    } catch (_) {}
    // Seamless local offline/guest fallback
    return await _loadLocalItems(path, type: type);
  }

  /// The signed-in user's saved vehicles, mapped to VehicleModel for the
  /// planners' vehicle pickers. Returns [] for guests or on any error.
  Future<List<VehicleModel>> savedVehicles() async {
    try {
      final rows = await accountList('vehicles');
      return rows.map((r) {
        final t = (r['type'] ?? 'car').toString().toLowerCase();
        return VehicleModel(
          id: 'saved_${r['id'] ?? 'v_${r['name'] ?? 'default'}'}',
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
    try {
      final res = await http
          .post(Uri.parse('$baseUrl/api/account/$path'), headers: _authHeaders(), body: jsonEncode(data))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 || res.statusCode == 201) {
        final item = (jsonDecode(res.body) as Map).cast<String, dynamic>();
        final type = data['type']?.toString();
        final local = await _loadLocalItems(path, type: type);
        local.insert(0, item);
        await _saveLocalItems(path, local, type: type);
        return item;
      }
    } catch (_) {}
    // Offline local creation
    final item = Map<String, dynamic>.from(data);
    item['id'] = item['id'] ?? 'loc_${DateTime.now().millisecondsSinceEpoch}';
    item['created_at'] = DateTime.now().toIso8601String();
    final type = data['type']?.toString();
    final local = await _loadLocalItems(path, type: type);
    local.insert(0, item);
    await _saveLocalItems(path, local, type: type);
    return item;
  }

  Future<Map<String, dynamic>> accountUpdate(String path, String id, Map<String, dynamic> data) async {
    try {
      final res = await http
          .patch(Uri.parse('$baseUrl/api/account/$path/$id'), headers: _authHeaders(), body: jsonEncode(data))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final item = (jsonDecode(res.body) as Map).cast<String, dynamic>();
        final type = data['type']?.toString();
        final local = await _loadLocalItems(path, type: type);
        final idx = local.indexWhere((e) => e['id']?.toString() == id);
        if (idx != -1) {
          local[idx].addAll(item);
          await _saveLocalItems(path, local, type: type);
        }
        return item;
      }
    } catch (_) {}
    // Offline local update
    final type = data['type']?.toString();
    final local = await _loadLocalItems(path, type: type);
    final idx = local.indexWhere((e) => e['id']?.toString() == id);
    if (idx != -1) {
      local[idx].addAll(data);
      await _saveLocalItems(path, local, type: type);
      return local[idx];
    }
    return data;
  }

  Future<void> accountDelete(String path, String id) async {
    try {
      await http
          .delete(Uri.parse('$baseUrl/api/account/$path/$id'), headers: _authHeaders())
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
    // Local deletion
    final local = await _loadLocalItems(path);
    local.removeWhere((e) => e['id']?.toString() == id);
    await _saveLocalItems(path, local);
  }

  Future<Map<String, dynamic>> getProfile() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/account/profile'), headers: _authHeaders()).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final profile = (jsonDecode(res.body) as Map).cast<String, dynamic>();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('voy_cached_profile', jsonEncode(profile));
        return profile;
      }
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('voy_cached_profile');
      if (raw != null) return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {}
    return {'language': 'en', 'currency': 'INR', 'theme': 'dark'};
  }

  Future<Map<String, dynamic>> putProfile(Map<String, dynamic> data) async {
    try {
      final res = await http
          .put(Uri.parse('$baseUrl/api/account/profile'), headers: _authHeaders(), body: jsonEncode(data))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final profile = (jsonDecode(res.body) as Map).cast<String, dynamic>();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('voy_cached_profile', jsonEncode(profile));
        return profile;
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('voy_cached_profile', jsonEncode(data));
    return data;
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
    final activeCategories = categories.isEmpty
        ? ['attraction', 'viewpoint', 'restaurant', 'hotel', 'tea', 'fuel']
        : categories;

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

    try {
      final uri = Uri.parse('$baseUrl/api/trip/pois');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'coordinates': sampledCoords.map((c) => {'lat': c.lat, 'lng': c.lng}).toList(),
              'categories': activeCategories,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final placesJson = body['places'] as Map<String, dynamic>? ?? {};
        final res = placesJson.map(
          (key, value) => MapEntry(
            key,
            (value as List).map((e) => PlaceOfInterest.fromJson(e as Map<String, dynamic>)).toList(),
          ),
        );
        if (res.values.any((l) => l.isNotEmpty)) {
          return res;
        }
      }
    } catch (_) {
      // Backend failed or timed out; fall through to direct Mapbox category search
    }

    // High-speed Photon OSM Proximity Search (global, free, zero restriction)
    return await _fetchPOIsWithPhoton(sampledCoords, activeCategories);
  }

  Future<Map<String, List<PlaceOfInterest>>> _fetchPOIsWithPhoton(
    List<GeoPoint> coordinates,
    List<String> categories,
  ) async {
    final Map<String, List<PlaceOfInterest>> result = {};
    for (final cat in categories) {
      result[cat] = [];
    }

    if (coordinates.isEmpty) return result;

    // Sample 6-8 evenly distributed coordinates along the route
    final samplePoints = <GeoPoint>[];
    const numSamples = 7;
    if (coordinates.length <= numSamples) {
      samplePoints.addAll(coordinates);
    } else {
      for (int i = 0; i < numSamples; i++) {
        final idx = ((coordinates.length - 1) * (i / (numSamples - 1))).round();
        samplePoints.add(coordinates[idx]);
      }
    }

    final categoryQueryMap = {
      'temple': ['sri temple', 'swamy temple', 'temple', 'mandir', 'kovil'],
      'fuel': ['petrol pump', 'indian oil', 'bharat petroleum', 'hindustan petroleum', 'shell petrol', 'fuel'],
      'restaurant': ['restaurant', 'veg restaurant', 'dhaba', 'hotel dining', 'bhavan'],
      'dining': ['restaurant', 'veg restaurant', 'dhaba', 'cafe'],
      'hotel': ['resort', 'hotel stay', 'lodge', 'inn'],
      'attraction': ['palace', 'fort', 'waterfall', 'viewpoint', 'sanctuary', 'monument'],
      'viewpoint': ['viewpoint', 'hill viewpoint', 'waterfall'],
      'hills': ['hills', 'peak', 'viewpoint'],
      'lake': ['lake', 'dam', 'reservoir'],
      'river': ['river', 'falls'],
      'charging': ['ev charging', 'tata power ev', 'charging station'],
      'tea': ['tea stall', 'cafe coffee day', 'chai point', 'bakery'],
    };

    double distKm(double lat1, double lon1, double lat2, double lon2) {
      const p = 0.017453292519943295;
      final a = 0.5 - cos((lat2 - lat1) * p) / 2 +
          cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
      return (12742 * asin(sqrt(a))).toDouble();
    }

    final seenKeys = <String>{};

    for (final cat in categories) {
      final terms = categoryQueryMap[cat] ?? [cat];
      for (final pt in samplePoints) {
        for (final term in terms) {
          try {
            final uri = Uri.parse(
              'https://photon.komoot.io/api/?q=${Uri.encodeComponent(term)}&lat=${pt.lat}&lon=${pt.lng}&limit=8',
            );
            final resp = await http.get(uri).timeout(const Duration(seconds: 4));
            if (resp.statusCode == 200) {
              final data = jsonDecode(resp.body) as Map<String, dynamic>;
              final features = data['features'] as List<dynamic>? ?? [];
              for (final f in features) {
                final geom = f['geometry'] as Map<String, dynamic>?;
                final coords = geom?['coordinates'] as List<dynamic>?;
                final props = f['properties'] as Map<String, dynamic>? ?? {};
                var rawName = (props['name'] as String?)?.trim() ?? '';
                
                if (coords != null && coords.length >= 2) {
                  final lng = (coords[0] as num).toDouble();
                  final lat = (coords[1] as num).toDouble();

                  // Calculate minimum distance to the route
                  double minDistanceKm = double.infinity;
                  for (final sp in samplePoints) {
                    final d = distKm(lat, lng, sp.lat, sp.lng);
                    if (d < minDistanceKm) minDistanceKm = d;
                  }

                  // Strictly filter out POIs that are too far from the highway route (> 12 km)
                  if (minDistanceKm > 12.0) continue;

                  final city = props['city'] ?? props['district'] ?? props['county'] ?? props['locality'];
                  final state = props['state'] ?? '';

                  // Clean up name
                  if (rawName.isEmpty || rawName.toLowerCase() == 'temple' || rawName.toLowerCase() == 'place_of_worship') {
                    if (cat == 'temple') {
                      rawName = city != null ? 'Sri Temple ($city)' : 'Sri Temple';
                    } else if (cat == 'fuel') {
                      rawName = city != null ? 'Fuel Station ($city)' : 'Fuel Station';
                    } else {
                      rawName = city != null ? '${term.toUpperCase()} ($city)' : term.toUpperCase();
                    }
                  }

                  // Build complete address
                  final addressParts = <String>[];
                  if (props['street'] != null) addressParts.add(props['street'].toString());
                  if (city != null) addressParts.add(city.toString());
                  if (state.isNotEmpty) addressParts.add(state.toString());
                  final address = addressParts.isNotEmpty ? addressParts.join(', ') : '$rawName, ${city ?? "Route"}';

                  final key = '$rawName-${lat.toStringAsFixed(3)}-${lng.toStringAsFixed(3)}';
                  if (!seenKeys.contains(key)) {
                    seenKeys.add(key);

                    final temple = (cat == 'temple') ? TempleDatabase.findTemple(rawName) : null;
                    final isTemple = cat == 'temple' || temple != null;

                    result[cat]?.add(
                      PlaceOfInterest(
                        id: key.hashCode,
                        name: temple?.canonicalName ?? rawName,
                        lat: lat,
                        lng: lng,
                        address: address,
                        rating: temple?.rating ?? (isTemple ? 4.7 : (cat == 'attraction' ? 4.6 : 4.4)),
                        reviewsCount: temple?.reviewsCount ?? (isTemple ? 15000 : 8500),
                        deity: temple?.deity,
                        timing: temple?.timing ?? (isTemple ? 'Opens 6:00 AM · Closes 8:30 PM' : null),
                        highlights: temple?.highlights,
                        categoryType: isTemple ? '🛕 Hindu temple' : (cat == 'attraction' ? '📍 Landmark / Attraction' : (cat == 'viewpoint' ? '🌄 Scenic Viewpoint' : null)),
                      ),
                    );
                  }
                }
              }
            }
          } catch (_) {}
        }
      }
    }

    return result;
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

  /// Destination autocomplete via the backend (the client's Mapbox token is
  /// URL-restricted to the website, so native apps must proxy through here).
  /// Returns up to 6 suggestions: [{name, lat, lng}].
  Future<List<Map<String, dynamic>>> autocompletePlaces(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];
    final uri = Uri.parse('$baseUrl/api/geocode/suggest')
        .replace(queryParameters: {'q': q});
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (data['suggestions'] as List?) ?? [];
      return list.map((e) {
        final m = e as Map<String, dynamic>;
        return {
          'name': (m['name'] ?? '').toString(),
          'lat': (m['lat'] as num).toDouble(),
          'lng': (m['lng'] as num).toDouble(),
        };
      }).where((m) => (m['name'] as String).isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  Future<String?> reverseGeocode(double lat, double lng) async {
    // 1. Direct Mapbox Reverse Geocoding (fast client-side, zero backend latency)
    try {
      final mapboxUri = Uri.parse(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/$lng,$lat.json?access_token=${AppConfig.mapboxToken}&limit=1&language=en'
      );
      final res = await http.get(mapboxUri).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final features = body['features'] as List? ?? [];
        if (features.isNotEmpty) {
          final placeName = features.first['place_name'] as String?;
          if (placeName != null && placeName.trim().isNotEmpty) {
            return placeName.trim();
          }
        }
      }
    } catch (_) {}

    // 2. Backend reverse-geocoding service
    try {
      final uri = Uri.parse('$baseUrl/api/trip/reverse-geocode?lat=$lat&lng=$lng');
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final addr = data['address'] as String?;
        if (addr != null && addr.trim().isNotEmpty) {
          return addr.trim();
        }
      }
    } catch (_) {}

    // 3. OpenStreetMap Nominatim reverse geocode fallback
    try {
      final osmUri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lng&format=json&zoom=16'
      );
      final res = await http.get(osmUri, headers: {'User-Agent': 'VoyplanTravelApp/1.0'}).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final displayName = data['display_name'] as String?;
        if (displayName != null && displayName.trim().isNotEmpty) {
          return displayName.trim();
        }
      }
    } catch (_) {}

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
    try {
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
          .timeout(const Duration(seconds: 45));
      if (response.statusCode == 200) {
        final list = (jsonDecode(response.body) as Map<String, dynamic>)['days'] as List? ?? [];
        final parsed = list.map((e) => (e as Map).cast<String, dynamic>()).toList();
        if (parsed.isNotEmpty) return parsed;
      }
    } catch (_) {}

    // Fallback: rule-based day-by-day planner
    return _generateFallbackBuildItinerary(
      start: start,
      end: end,
      days: days,
      travellers: travellers,
    );
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
    try {
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
          .timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final days = (body['days'] as List? ?? [])
            .map((e) => SmartDay.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        final budget = body['budget'] != null
            ? TripBudget.fromJson((body['budget'] as Map).cast<String, dynamic>())
            : null;
        if (days.isNotEmpty) {
          return (days: days, budget: budget);
        }
      }
    } catch (_) {}

    // Fallback: Built-in Smart Itinerary & Budget Generator
    return _generateFallbackSmartItinerary(
      destination: destination,
      startLocation: startLocation,
      places: places,
      preferences: preferences,
      durationDays: durationDays,
      startTime: startTime,
      travellers: travellers,
      fuelEfficiency: fuelEfficiency,
    );
  }

  List<Map<String, dynamic>> _generateFallbackBuildItinerary({
    required String start,
    required String end,
    int days = 1,
    int travellers = 1,
  }) {
    final res = <Map<String, dynamic>>[];
    final total = math.max(1, days);
    for (int d = 1; d <= total; d++) {
      final isFirst = d == 1;
      final isLast = d == total;
      res.add({
        'day': d,
        'title': isFirst ? 'Journey to $end & Exploration' : (isLast ? 'Farewell $end & Return' : '$end Highlights & Culture'),
        'activities': [
          {
            'part': 'Morning',
            'time': '08:00',
            'title': isFirst ? 'Drive from $start to $end' : 'Breakfast & Morning Sights in $end',
            'note': isFirst ? 'Scenic morning drive along the highway' : 'Fresh regional breakfast and temple visit',
          },
          {
            'part': 'Afternoon',
            'time': '13:00',
            'title': 'Heritage Exploration & Lunch',
            'note': 'Authentic thali meal and iconic palace/monument visit',
          },
          {
            'part': 'Evening',
            'time': '17:30',
            'title': isLast ? 'Sunset Return Drive to $start' : 'Sunset Viewpoint & Local Bazaar',
            'note': isLast ? 'Comfortable highway return journey' : 'Tea, photography and local handicraft shopping',
          },
          {
            'part': 'Night',
            'time': '20:30',
            'title': isLast ? 'Arrival back at $start' : 'Dinner & Rest in $end',
            'note': isLast ? 'Safe return home' : 'Relaxing dinner and evening city ambiance',
          },
        ],
      });
    }
    return res;
  }

  ({List<SmartDay> days, TripBudget? budget}) _generateFallbackSmartItinerary({
    required String destination,
    required String startLocation,
    required List<String> places,
    String preferences = '',
    required int durationDays,
    required String startTime,
    required int travellers,
    double? fuelEfficiency,
  }) {
    final total = math.max(1, math.min(durationDays, 14));
    final destName = destination.isNotEmpty ? destination : 'Destination';
    final startName = startLocation.isNotEmpty ? startLocation : 'Home';
    final daysList = <SmartDay>[];

    final pool = TempleDatabase.getAttractionPool(
      destination: destination,
      preferences: preferences,
      places: places,
    );

    final List<TempleInfo> templePool = pool.isNotEmpty ? pool : TempleDatabase.allTemples;
    int templeIdx = 0;

    TempleInfo getNextTemple() {
      final t = templePool[templeIdx % templePool.length];
      templeIdx++;
      return t;
    }

    for (int d = 1; d <= total; d++) {
      final isFirst = d == 1;
      final isLast = d == total;
      final blocks = <TimelineBlock>[];

      if (isFirst) {
        blocks.add(TimelineBlock(
          start: startTime.isNotEmpty ? startTime : '08:00',
          end: '10:30',
          type: 'travel',
          title: 'Drive from $startName to $destName',
          place: destName,
          durationMin: 150,
          travelMin: 150,
          distanceKm: 145,
          travelMode: 'drive',
          reason: 'Scenic morning drive along highway with traffic clearance',
        ));
        blocks.add(TimelineBlock(
          start: '10:30',
          end: '11:15',
          type: 'coffee',
          title: 'Highway Coffee & Breakfast Refreshment',
          place: 'Highway Cafe / Diner',
          durationMin: 45,
          breakType: 'breakfast',
          reason: 'Traditional South Indian filter coffee & hot tiffin',
        ));
        blocks.add(TimelineBlock(
          start: '11:45',
          end: '12:30',
          type: 'checkin',
          title: 'Hotel Check-in & Freshen Up in $destName',
          place: '$destName Pilgrimage Stay / Hotel',
          durationMin: 45,
          reason: 'Check in, deposit luggage, and prepare for auspicious darshan',
        ));
      } else {
        blocks.add(TimelineBlock(
          start: '08:00',
          end: '09:00',
          type: 'meal',
          title: 'Morning Breakfast in $destName',
          place: '$destName Tiffin Center',
          durationMin: 60,
          breakType: 'breakfast',
          reason: 'Traditional morning breakfast to energise for the pilgrimage',
        ));
      }

      final t1 = getNextTemple();
      blocks.add(TimelineBlock(
        start: isFirst ? '12:30' : '09:30',
        end: isFirst ? '14:00' : '12:30',
        type: 'activity',
        title: 'Darshan at ${t1.canonicalName}',
        place: '${t1.canonicalName}, ${t1.city}',
        durationMin: isFirst ? 90 : 180,
        reason: '🛕 Deity: ${t1.deity} · ⭐ ${t1.rating} · ${t1.highlights}',
      ));

      blocks.add(TimelineBlock(
        start: isFirst ? '14:00' : '12:45',
        end: isFirst ? '15:00' : '14:00',
        type: 'meal',
        title: 'Traditional Lunch in $destName',
        place: 'Authentic Pure Vegetarian Restaurant',
        durationMin: 60,
        breakType: 'lunch',
        reason: 'Sacred thali meals & prasadam refreshments',
      ));

      final t2 = getNextTemple();
      blocks.add(TimelineBlock(
        start: '15:15',
        end: '17:30',
        type: 'activity',
        title: 'Visit ${t2.canonicalName}',
        place: '${t2.canonicalName}, ${t2.city}',
        durationMin: 135,
        reason: '🛕 Deity: ${t2.deity} · ⭐ ${t2.rating} · ${t2.highlights}',
      ));

      blocks.add(TimelineBlock(
        start: '17:45',
        end: '18:45',
        type: 'coffee',
        title: 'Evening Sunset & Tea Break',
        place: 'Scenic Viewpoint / Temple Promenade',
        durationMin: 60,
        breakType: 'coffee',
        reason: 'Golden hour views and refreshing evening tea',
      ));

      if (isLast) {
        if (total > 1) {
          blocks.add(TimelineBlock(
            start: '18:45',
            end: '19:15',
            type: 'checkout',
            title: 'Hotel Check-out from $destName',
            place: '$destName Hotel',
            durationMin: 30,
            reason: 'Settle bills, load luggage into vehicle',
          ));
        }
        blocks.add(TimelineBlock(
          start: '19:15',
          end: '21:45',
          type: 'return',
          title: 'Return Drive back to $startName',
          place: startName,
          durationMin: 150,
          travelMin: 150,
          distanceKm: 145,
          travelMode: 'drive',
          reason: 'Smooth evening highway cruise returning home',
        ));
        blocks.add(TimelineBlock(
          start: '22:00',
          end: '22:45',
          type: 'meal',
          title: 'Dinner Arrival at $startName',
          place: 'Home / Local Dining',
          durationMin: 45,
          breakType: 'dinner',
          reason: 'Relaxing meal to conclude the road trip',
        ));
      } else {
        blocks.add(TimelineBlock(
          start: '19:30',
          end: '21:00',
          type: 'meal',
          title: 'Dinner & Evening Leisure in $destName',
          place: 'Celebrated Fine Dining / Dhaba',
          durationMin: 90,
          breakType: 'dinner',
          reason: 'Enjoy authentic dinner and evening city ambiance',
        ));
        blocks.add(TimelineBlock(
          start: '21:15',
          end: '22:00',
          type: 'rest',
          title: 'Night Rest & Trip Reflection',
          place: '$destName Hotel / Resort',
          durationMin: 45,
          reason: 'Good night rest for the next day\'s adventures',
        ));
      }

      daysList.add(SmartDay(
        day: d,
        date: 'Day $d',
        title: isFirst ? 'Arrival & Highlights of $destName' : (isLast ? 'Farewell $destName & Return' : 'Deep Dive into $destName Heritage'),
        blocks: blocks,
      ));
    }

    final eff = (fuelEfficiency != null && fuelEfficiency > 0) ? fuelEfficiency : 15.0;
    final totalKm = 320.0 * (total > 1 ? 1.4 : 1.0);
    final fuelCost = ((totalKm / eff) * 102.0).round();
    final tollCost = 360;
    final foodCost = total * 750 * travellers;
    final stayCost = (total > 1 ? (total - 1) : 0) * 2200 * ((travellers / 2).ceil());
    final int bufferCost = 1000;
    final int grandTotal = (fuelCost + tollCost + foodCost + stayCost + bufferCost).toInt();

    final budget = TripBudget(
      currency: 'INR',
      days: total,
      nights: total > 1 ? total - 1 : 0,
      travellers: travellers,
      international: false,
      fuel: fuelCost,
      tolls: tollCost,
      food: foodCost,
      stay: stayCost,
      buffer: bufferCost,
      total: grandTotal,
      perDay: (grandTotal / total).round(),
    );

    return (days: daysList, budget: budget);
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
