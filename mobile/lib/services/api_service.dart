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
import '../data/venue_database.dart';

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

    final plan = TripPlan.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    
    // If the plan returned straight-line or sparse points (< 25 points for > 3 km),
    // enhance immediately with high-resolution Mapbox or OSRM road geometry!
    if (plan.coordinates.length < 25 && plan.distanceKm > 3.0) {
      final roadCoords = await _fetchRoadCoordinates(start: start, end: end, waypoints: waypoints);
      if (roadCoords.length > 25) {
        return plan.copyWith(coordinates: roadCoords);
      }
    }

    return plan;
  }

  Future<List<GeoPoint>> _fetchRoadCoordinates({
    required GeoPoint start,
    required GeoPoint end,
    List<GeoPoint> waypoints = const [],
  }) async {
    final allPoints = [start, ...waypoints, end];
    
    // 1. Try Mapbox Directions directly with client token
    if (AppConfig.hasMapboxToken) {
      try {
        final coordsStr = allPoints.map((p) => '${p.lng},${p.lat}').join(';');
        final uri = Uri.parse(
          'https://api.mapbox.com/directions/v5/mapbox/driving-traffic/$coordsStr?geometries=geojson&overview=full&access_token=${AppConfig.mapboxToken}',
        );
        final resp = await http.get(uri).timeout(const Duration(seconds: 12));
        if (resp.statusCode == 200) {
          final body = jsonDecode(resp.body) as Map<String, dynamic>;
          final routes = body['routes'] as List? ?? [];
          if (routes.isNotEmpty) {
            final geom = routes[0]['geometry'] as Map<String, dynamic>?;
            final coords = geom?['coordinates'] as List? ?? [];
            if (coords.length > 10) {
              return coords.map((c) => GeoPoint(lat: (c[1] as num).toDouble(), lng: (c[0] as num).toDouble())).toList();
            }
          }
        }
      } catch (_) {}
    }

    // 2. High-speed OSRM road geometry router
    try {
      final coordsStr = allPoints.map((p) => '${p.lng},${p.lat}').join(';');
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$coordsStr?overview=full&geometries=geojson',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final routes = body['routes'] as List? ?? [];
        if (routes.isNotEmpty) {
          final geom = routes[0]['geometry'] as Map<String, dynamic>?;
          final coords = geom?['coordinates'] as List? ?? [];
          if (coords.length > 10) {
            return coords.map((c) => GeoPoint(lat: (c[1] as num).toDouble(), lng: (c[0] as num).toDouble())).toList();
          }
        }
      }
    } catch (_) {}

    return [];
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

  static const List<Map<String, dynamic>> _curatedPlaces = [
    {'name': 'Tirupati, Andhra Pradesh, India', 'lat': 13.6288, 'lng': 79.4192},
    {'name': 'Tirumala, Tirupati, Andhra Pradesh, India', 'lat': 13.6833, 'lng': 79.3500},
    {'name': 'Bengaluru, Karnataka, India', 'lat': 12.9716, 'lng': 77.5946},
    {'name': 'Mandya, Karnataka, India', 'lat': 12.5244, 'lng': 76.8967},
    {'name': 'Mysuru (Mysore), Karnataka, India', 'lat': 12.2958, 'lng': 76.6394},
    {'name': 'Madurai, Tamil Nadu, India', 'lat': 9.9252, 'lng': 78.1198},
    {'name': 'Rameshwaram, Tamil Nadu, India', 'lat': 9.2876, 'lng': 79.3129},
    {'name': 'Srirangapatna, Karnataka, India', 'lat': 12.4237, 'lng': 76.6947},
    {'name': 'Nanjangud, Karnataka, India', 'lat': 12.1195, 'lng': 76.6806},
    {'name': 'Srikalahasti, Andhra Pradesh, India', 'lat': 13.7498, 'lng': 79.6984},
    {'name': 'Kanipakam, Andhra Pradesh, India', 'lat': 13.2798, 'lng': 79.0347},
    {'name': 'Udupi, Karnataka, India', 'lat': 13.3409, 'lng': 74.7421},
    {'name': 'Murudeshwar, Karnataka, India', 'lat': 14.0940, 'lng': 74.4899},
    {'name': 'Gokarna, Karnataka, India', 'lat': 14.5479, 'lng': 74.3188},
    {'name': 'Mangaluru (Mangalore), Karnataka, India', 'lat': 12.9141, 'lng': 74.8560},
    {'name': 'Dharmasthala, Karnataka, India', 'lat': 12.9482, 'lng': 75.3804},
    {'name': 'Kukke Subramanya, Karnataka, India', 'lat': 12.6631, 'lng': 75.6148},
    {'name': 'Varanasi (Kashi), Uttar Pradesh, India', 'lat': 25.3176, 'lng': 82.9739},
    {'name': 'Ayodhya, Uttar Pradesh, India', 'lat': 26.7922, 'lng': 82.1998},
    {'name': 'Haridwar, Uttarakhand, India', 'lat': 29.9457, 'lng': 78.1642},
    {'name': 'Rishikesh, Uttarakhand, India', 'lat': 30.0869, 'lng': 78.2676},
    {'name': 'Puri, Odisha, India', 'lat': 19.8135, 'lng': 85.8312},
    {'name': 'Amritsar, Punjab, India', 'lat': 31.6340, 'lng': 74.8723},
    {'name': 'Chennai, Tamil Nadu, India', 'lat': 13.0827, 'lng': 80.2707},
    {'name': 'Hyderabad, Telangana, India', 'lat': 17.3850, 'lng': 78.4867},
    {'name': 'Mumbai, Maharashtra, India', 'lat': 19.0760, 'lng': 72.8777},
    {'name': 'Delhi / New Delhi, India', 'lat': 28.6139, 'lng': 77.2090},
    {'name': 'Goa, India', 'lat': 15.2993, 'lng': 74.1240},
    {'name': 'Ooty, Tamil Nadu, India', 'lat': 11.4102, 'lng': 76.6950},
    {'name': 'Coorg (Madikeri), Karnataka, India', 'lat': 12.4244, 'lng': 75.7382},
    {'name': 'Munnar, Kerala, India', 'lat': 10.0889, 'lng': 77.0595},
    {'name': 'Kodaikanal, Tamil Nadu, India', 'lat': 10.2381, 'lng': 77.4892},
    {'name': 'Wayanad, Kerala, India', 'lat': 11.6854, 'lng': 76.1320},
    {'name': 'Jaipur, Rajasthan, India', 'lat': 26.9124, 'lng': 75.7873},
    {'name': 'Udaipur, Rajasthan, India', 'lat': 24.5854, 'lng': 73.7125},
    {'name': 'Agra, Uttar Pradesh, India', 'lat': 27.1767, 'lng': 78.0081},
    {'name': 'Pondicherry (Puducherry), India', 'lat': 11.9416, 'lng': 79.8083},
    {'name': 'Kochi (Cochin), Kerala, India', 'lat': 9.9312, 'lng': 76.2673},
    {'name': 'Thiruvananthapuram, Kerala, India', 'lat': 8.5241, 'lng': 76.9366},
    {'name': 'Kanyakumari, Tamil Nadu, India', 'lat': 8.0883, 'lng': 77.5385},
    {'name': 'Thanjavur, Tamil Nadu, India', 'lat': 10.7870, 'lng': 79.1378},
    {'name': 'Kanchipuram, Tamil Nadu, India', 'lat': 12.8342, 'lng': 79.7036},
    {'name': 'Dubai, United Arab Emirates', 'lat': 25.2048, 'lng': 55.2708},
    {'name': 'Singapore', 'lat': 1.3521, 'lng': 103.8198},
    {'name': 'London, United Kingdom', 'lat': 51.5074, 'lng': -0.1278},
    {'name': 'Paris, France', 'lat': 48.8566, 'lng': 2.3522},
    {'name': 'Bangkok, Thailand', 'lat': 13.7563, 'lng': 100.5018},
    {'name': 'Tokyo, Japan', 'lat': 35.6762, 'lng': 139.6503},
    {'name': 'Bali, Indonesia', 'lat': -8.4095, 'lng': 115.1889},
  ];

  /// Destination & stop autocomplete with multi-tier fallback:
  /// 1. Instant local curated knowledge base (<1ms)
  /// 2. Photon OpenStreetMap live typeahead API (global, zero-auth, fast)
  /// 3. Mapbox Places geocoding API
  /// 4. Backend geocode suggest proxy
  /// 5. Nominatim fallback
  Future<List<Map<String, dynamic>>> autocompletePlaces(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];

    final results = <Map<String, dynamic>>[];
    final seenNames = <String>{};

    void addResult(String name, double lat, double lng) {
      final clean = name.trim();
      final key = clean.toLowerCase();
      if (clean.isNotEmpty && !seenNames.contains(key)) {
        seenNames.add(key);
        results.add({'name': clean, 'lat': lat, 'lng': lng});
      }
    }

    // Tier 1: Instant Local Curated Knowledge Match
    for (final p in _curatedPlaces) {
      final name = p['name'] as String;
      if (name.toLowerCase().contains(q)) {
        addResult(name, (p['lat'] as num).toDouble(), (p['lng'] as num).toDouble());
        if (results.length >= 6) return results;
      }
    }

    // Tier 2: Photon (OpenStreetMap Komoot) - Fast global typeahead
    try {
      final photonUri = Uri.parse(
        'https://photon.komoot.io/api/?q=${Uri.encodeComponent(q)}&limit=6&lat=20.5937&lon=78.9629',
      );
      final res = await http.get(photonUri).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final features = (data['features'] as List?) ?? [];
        for (final f in features) {
          final props = f['properties'] as Map<String, dynamic>?;
          final geom = f['geometry'] as Map<String, dynamic>?;
          final coords = (geom?['coordinates'] as List?) ?? [];
          if (props != null && coords.length >= 2) {
            final name = props['name'] ?? '';
            final city = props['city'] ?? props['county'] ?? '';
            final state = props['state'] ?? '';
            final country = props['country'] ?? '';
            final labelParts = [name, city, state, country].where((s) => s.toString().trim().isNotEmpty).toList();
            final fullLabel = labelParts.join(', ');
            final lng = (coords[0] as num).toDouble();
            final lat = (coords[1] as num).toDouble();
            addResult(fullLabel, lat, lng);
            if (results.length >= 6) return results;
          }
        }
      }
    } catch (_) {}

    // Tier 3: Direct Mapbox Places API
    try {
      final mapboxUri = Uri.parse(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(q)}.json?access_token=${AppConfig.mapboxToken}&autocomplete=true&limit=6&language=en&proximity=78.9629,20.5937',
      );
      final res = await http.get(mapboxUri).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final features = (body['features'] as List?) ?? [];
        for (final f in features) {
          final placeName = f['place_name'] as String?;
          final center = (f['center'] as List?) ?? [];
          if (placeName != null && center.length >= 2) {
            final lng = (center[0] as num).toDouble();
            final lat = (center[1] as num).toDouble();
            addResult(placeName, lat, lng);
            if (results.length >= 6) return results;
          }
        }
      }
    } catch (_) {}

    // Tier 4: Backend Suggest Proxy
    try {
      final uri = Uri.parse('$baseUrl/api/geocode/suggest').replace(queryParameters: {'q': q});
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final list = (data['suggestions'] as List?) ?? [];
        for (final e in list) {
          final m = e as Map<String, dynamic>;
          final name = (m['name'] ?? '').toString();
          final lat = (m['lat'] as num?)?.toDouble() ?? 0.0;
          final lng = (m['lng'] as num?)?.toDouble() ?? 0.0;
          addResult(name, lat, lng);
          if (results.length >= 6) return results;
        }
      }
    } catch (_) {}

    // Tier 5: Nominatim Search
    try {
      final osmUri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(q)}&format=json&limit=6',
      );
      final res = await http.get(osmUri, headers: {
        'User-Agent': 'TravelV1/1.0 (https://gowtham64.github.io/Travel-V1/; contact: travel-app)',
      }).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>;
        for (final item in list) {
          final name = item['display_name'] as String?;
          final lat = double.tryParse(item['lat'].toString()) ?? 0.0;
          final lng = double.tryParse(item['lon'].toString()) ?? 0.0;
          if (name != null) addResult(name, lat, lng);
          if (results.length >= 6) return results;
        }
      }
    } catch (_) {}

    return results;
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
    final qClean = query.trim().toLowerCase();

    // 1. Try backend AI search
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/ai/search'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'query': query, if (near != null) 'near': near}),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final places = _parseAiPlaces(response);
        if (places.isNotEmpty) return places;
      }
    } catch (_) {
      // Fallback gracefully on timeout or 502
    }

    // 2. Fallback: Search in TempleDatabase
    final localResults = <Map<String, String>>[];
    for (final t in TempleDatabase.allTemples) {
      final nameMatch = t.canonicalName.toLowerCase().contains(qClean) ||
          t.aliases.any((a) => a.toLowerCase().contains(qClean)) ||
          qClean.contains(t.canonicalName.toLowerCase());
      final deityMatch = t.deity.toLowerCase().contains(qClean);
      final cityMatch = t.city.toLowerCase().contains(qClean);
      if (nameMatch || deityMatch || cityMatch) {
        localResults.add({
          'name': t.canonicalName,
          'area': '${t.city}, ${t.state}',
          'why': '🛕 ${t.deity} · ⭐ ${t.rating} · ${t.highlights}',
        });
      }
    }
    if (localResults.isNotEmpty) return localResults;

    // 3. Fallback: Search in VenueDatabase
    for (final v in VenueDatabase.allVenues) {
      if (v.name.toLowerCase().contains(qClean) || v.city.toLowerCase().contains(qClean) || v.specialty.toLowerCase().contains(qClean)) {
        localResults.add({
          'name': v.name,
          'area': v.city,
          'why': '⭐ ${v.rating} · ${v.specialty}',
        });
      }
    }
    if (localResults.isNotEmpty) return localResults;

    // 4. Fallback: Live Photon / OpenStreetMap Search
    try {
      final places = await autocompletePlaces(query);
      if (places.isNotEmpty) {
        return places.map((p) => {
          'name': p['name'].toString().split(',').first.trim(),
          'area': p['name'].toString(),
          'why': 'Popular destination & attraction',
        }).toList();
      }
    } catch (_) {}

    return [
      {
        'name': query.trim(),
        'area': near ?? 'Local Area',
        'why': 'Custom added place / attraction',
      }
    ];
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

    // Realistic highway distance estimation
    double estimatedKm = 145.0;
    final pair = '$startName $destName'.toLowerCase();
    if (pair.contains('mandya') && (pair.contains('tirupati') || pair.contains('tirumala'))) {
      estimatedKm = 345.0;
    } else if (pair.contains('bengaluru') || pair.contains('bangalore')) {
      if (pair.contains('tirupati') || pair.contains('tirumala')) estimatedKm = 250.0;
      else if (pair.contains('mysore') || pair.contains('mysuru')) estimatedKm = 145.0;
      else if (pair.contains('coorg') || pair.contains('madikeri')) estimatedKm = 265.0;
      else if (pair.contains('ooty')) estimatedKm = 280.0;
      else if (pair.contains('chennai')) estimatedKm = 350.0;
      else if (pair.contains('goa')) estimatedKm = 560.0;
      else if (pair.contains('hampi')) estimatedKm = 340.0;
    } else if (pair.contains('mysore') || pair.contains('mysuru')) {
      if (pair.contains('tirupati') || pair.contains('tirumala')) estimatedKm = 385.0;
      else if (pair.contains('coorg') || pair.contains('madikeri')) estimatedKm = 120.0;
      else if (pair.contains('ooty')) estimatedKm = 125.0;
    } else if (pair.contains('chennai') && (pair.contains('tirupati') || pair.contains('tirumala'))) {
      estimatedKm = 135.0;
    }

    final totalDriveMin = (estimatedKm / 55.0 * 60).round();

    int parseMinutes(String t) {
      final clean = t.trim().toLowerCase();
      if (clean.isEmpty) return 480; // 08:00 AM
      final isPm = clean.contains('pm');
      final isAm = clean.contains('am');
      final numStr = clean.replaceAll(RegExp(r'[^0-9:]'), '');
      final parts = numStr.split(':');
      if (parts.isNotEmpty) {
        int h = int.tryParse(parts[0]) ?? 8;
        int m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
        if (isPm && h < 12) h += 12;
        if (isAm && h == 12) h = 0;
        return h * 60 + m;
      }
      return 480;
    }

    String formatMin(int totalMin) {
      final norm = totalMin % (24 * 60);
      final h24 = norm ~/ 60;
      final m = norm % 60;
      final ampm = h24 >= 12 ? 'PM' : 'AM';
      final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
      return '${h12.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $ampm';
    }

    // Curated Venues for highway, dining, and stay
    final coffeeHighway = VenueDatabase.getBestVenue(destination: destName, type: 'coffee', highwayRoute: '$startName $destName');
    final breakfastVenue = VenueDatabase.getBestVenue(destination: destName, type: 'breakfast');
    final lunchVenue = VenueDatabase.getBestVenue(destination: destName, type: 'lunch');
    final dinnerVenue = VenueDatabase.getBestVenue(destination: destName, type: 'dinner');
    final hotelVenue = VenueDatabase.getBestVenue(destination: destName, type: 'hotel');

    for (int d = 1; d <= total; d++) {
      final isFirst = d == 1;
      final isLast = d == total;
      final blocks = <TimelineBlock>[];

      if (isFirst) {
        // --- DAY 1: OUTWARD TRAVEL & EVENING DARSHAN ---
        final startMin = parseMinutes(startTime);
        int cur = startMin;

        if (totalDriveMin > 180) {
          // Long drive (>3 hours): Split with midway breakfast/coffee
          final leg1 = (totalDriveMin * 0.45).round();
          final leg2 = totalDriveMin - leg1;
          final dist1 = (estimatedKm * 0.45);
          final dist2 = estimatedKm - dist1;

          blocks.add(TimelineBlock(
            start: formatMin(cur),
            end: formatMin(cur + leg1),
            type: 'travel',
            title: 'Drive from $startName (Highway Leg 1)',
            place: 'National Highway',
            durationMin: leg1,
            travelMin: leg1,
            distanceKm: dist1,
            travelMode: 'drive',
            reason: 'Morning highway drive with smooth cruising',
          ));
          cur += leg1;

          blocks.add(TimelineBlock(
            start: formatMin(cur),
            end: formatMin(cur + 45),
            type: 'coffee',
            title: 'Highway Coffee & Breakfast at ${coffeeHighway.name}',
            place: '${coffeeHighway.name}, ${coffeeHighway.city}',
            durationMin: 45,
            breakType: 'breakfast',
            reason: '⭐ ${coffeeHighway.rating} · ${coffeeHighway.specialty}',
          ));
          cur += 45;

          blocks.add(TimelineBlock(
            start: formatMin(cur),
            end: formatMin(cur + leg2),
            type: 'travel',
            title: 'Drive to $destName (Highway Leg 2)',
            place: destName,
            durationMin: leg2,
            travelMin: leg2,
            distanceKm: dist2,
            travelMode: 'drive',
            reason: 'Scenic approach drive arriving in $destName',
          ));
          cur += leg2;
        } else {
          // Short drive (<= 3 hours)
          blocks.add(TimelineBlock(
            start: formatMin(cur),
            end: formatMin(cur + totalDriveMin),
            type: 'travel',
            title: 'Drive from $startName to $destName',
            place: destName,
            durationMin: totalDriveMin,
            travelMin: totalDriveMin,
            distanceKm: estimatedKm,
            travelMode: 'drive',
            reason: 'Smooth morning drive along highway with traffic clearance',
          ));
          cur += totalDriveMin;
        }

        // Arrival Lunch
        blocks.add(TimelineBlock(
          start: formatMin(cur),
          end: formatMin(cur + 60),
          type: 'meal',
          title: 'Traditional Arrival Lunch at ${lunchVenue.name}',
          place: '${lunchVenue.name}, ${lunchVenue.city}',
          durationMin: 60,
          breakType: 'lunch',
          reason: '⭐ ${lunchVenue.rating} · ${lunchVenue.specialty}',
        ));
        cur += 60;

        // Hotel Check-in
        blocks.add(TimelineBlock(
          start: formatMin(cur),
          end: formatMin(cur + 45),
          type: 'checkin',
          title: 'Hotel Check-in at ${hotelVenue.name}',
          place: '${hotelVenue.name}, ${hotelVenue.city}',
          durationMin: 45,
          reason: '⭐ ${hotelVenue.rating} · ${hotelVenue.specialty}',
        ));
        cur += 45;

        // If arrived before 03:00 PM, allow a preliminary shrine visit
        if (cur < 900) {
          final tPrelim = getNextTemple();
          final tPrelimDur = tPrelim.recommendedDarshanMinutes > 90 ? 75 : tPrelim.recommendedDarshanMinutes;
          blocks.add(TimelineBlock(
            start: formatMin(cur),
            end: formatMin(cur + tPrelimDur),
            type: 'activity',
            title: 'Darshan at ${tPrelim.canonicalName}',
            place: '${tPrelim.canonicalName}, ${tPrelim.city}',
            durationMin: tPrelimDur,
            reason: '🛕 Deity: ${tPrelim.deity} · ⭐ ${tPrelim.rating} · ${tPrelim.highlights}',
          ));
          cur += tPrelimDur;
        }

        // Grand Evening Temple / Main Attraction (e.g. Balaji / Main Shrine)
        final tMain = getNextTemple();
        final tDuration = tMain.recommendedDarshanMinutes;
        final tWait = tMain.darshanWaitInfo != null ? ' · ⏳ Darshan Wait: ${tMain.darshanWaitInfo}' : '';
        blocks.add(TimelineBlock(
          start: formatMin(cur),
          end: formatMin(cur + tDuration),
          type: 'activity',
          title: 'Grand Darshan at ${tMain.canonicalName}',
          place: '${tMain.canonicalName}, ${tMain.city}',
          durationMin: tDuration,
          reason: '🛕 Deity: ${tMain.deity} · ⭐ ${tMain.rating}$tWait · ${tMain.highlights}',
        ));
        cur += tDuration;

        // Traditional Dinner (at or after 07:30 PM)
        if (cur < 1170) cur = 1170; // 07:30 PM minimum
        blocks.add(TimelineBlock(
          start: formatMin(cur),
          end: formatMin(cur + 60),
          type: 'meal',
          title: 'Traditional Dinner at ${dinnerVenue.name}',
          place: '${dinnerVenue.name}, ${dinnerVenue.city}',
          durationMin: 60,
          breakType: 'dinner',
          reason: '⭐ ${dinnerVenue.rating} · ${dinnerVenue.specialty}',
        ));
        cur += 60;

        // Night Rest
        blocks.add(TimelineBlock(
          start: formatMin(cur),
          end: '06:30 AM',
          type: 'rest',
          title: 'Night Rest at ${hotelVenue.name}',
          place: '${hotelVenue.name}, ${hotelVenue.city}',
          durationMin: 480,
          reason: 'Peaceful sleep after sacred darshan and travel',
        ));
      } else if (!isLast) {
        // --- MIDDLE DAY: FULL SIGHTSEEING & PILGRIMAGE CIRCUIT ---
        blocks.add(TimelineBlock(
          start: '08:00 AM',
          end: '09:00 AM',
          type: 'meal',
          title: 'Morning Breakfast at ${breakfastVenue.name}',
          place: '${breakfastVenue.name}, ${breakfastVenue.city}',
          durationMin: 60,
          breakType: 'breakfast',
          reason: '⭐ ${breakfastVenue.rating} · ${breakfastVenue.specialty}',
        ));

        final t1 = getNextTemple();
        final t1Duration = t1.recommendedDarshanMinutes > 180 ? 180 : t1.recommendedDarshanMinutes;
        final t1Wait = t1.darshanWaitInfo != null ? ' · ⏳ Darshan Wait: ${t1.darshanWaitInfo}' : '';
        blocks.add(TimelineBlock(
          start: '09:15 AM',
          end: formatMin(555 + t1Duration),
          type: 'activity',
          title: 'Darshan at ${t1.canonicalName}',
          place: '${t1.canonicalName}, ${t1.city}',
          durationMin: t1Duration,
          reason: '🛕 Deity: ${t1.deity} · ⭐ ${t1.rating}$t1Wait · ${t1.highlights}',
        ));

        // Lunch strictly at 12:45 PM
        blocks.add(TimelineBlock(
          start: '12:45 PM',
          end: '01:45 PM',
          type: 'meal',
          title: 'Traditional Lunch at ${lunchVenue.name}',
          place: '${lunchVenue.name}, ${lunchVenue.city}',
          durationMin: 60,
          breakType: 'lunch',
          reason: '⭐ ${lunchVenue.rating} · ${lunchVenue.specialty}',
        ));

        final t2 = getNextTemple();
        final t2Duration = t2.recommendedDarshanMinutes > 150 ? 150 : t2.recommendedDarshanMinutes;
        final t2Wait = t2.darshanWaitInfo != null ? ' · ⏳ Darshan Wait: ${t2.darshanWaitInfo}' : '';
        blocks.add(TimelineBlock(
          start: '02:00 PM',
          end: formatMin(840 + t2Duration),
          type: 'activity',
          title: 'Visit & Darshan at ${t2.canonicalName}',
          place: '${t2.canonicalName}, ${t2.city}',
          durationMin: t2Duration,
          reason: '🛕 Deity: ${t2.deity} · ⭐ ${t2.rating}$t2Wait · ${t2.highlights}',
        ));

        // Evening Sunset & Tea strictly around 05:45 PM
        blocks.add(TimelineBlock(
          start: '05:45 PM',
          end: '06:45 PM',
          type: 'coffee',
          title: 'Evening Sunset & Tea Break',
          place: 'Scenic Viewpoint / Temple Promenade',
          durationMin: 60,
          breakType: 'coffee',
          reason: 'Golden hour views, cool evening breeze & hot tea',
        ));

        blocks.add(TimelineBlock(
          start: '07:30 PM',
          end: '08:30 PM',
          type: 'meal',
          title: 'Traditional Dinner at ${dinnerVenue.name}',
          place: '${dinnerVenue.name}, ${dinnerVenue.city}',
          durationMin: 60,
          breakType: 'dinner',
          reason: '⭐ ${dinnerVenue.rating} · ${dinnerVenue.specialty}',
        ));

        blocks.add(TimelineBlock(
          start: '09:30 PM',
          end: '06:30 AM',
          type: 'rest',
          title: 'Night Rest at ${hotelVenue.name}',
          place: '${hotelVenue.name}, ${hotelVenue.city}',
          durationMin: 480,
          reason: 'Restful sleep preparing for morning visits',
        ));
      } else {
        // --- FINAL DAY: MORNING SHRINES, LUNCH, CHECK-OUT & RETURN DRIVE ---
        blocks.add(TimelineBlock(
          start: '08:00 AM',
          end: '09:00 AM',
          type: 'meal',
          title: 'Morning Breakfast at ${breakfastVenue.name}',
          place: '${breakfastVenue.name}, ${breakfastVenue.city}',
          durationMin: 60,
          breakType: 'breakfast',
          reason: '⭐ ${breakfastVenue.rating} · ${breakfastVenue.specialty}',
        ));

        final t1 = getNextTemple();
        final t1Duration = t1.recommendedDarshanMinutes;
        final t1Wait = t1.darshanWaitInfo != null ? ' · ⏳ Darshan Wait: ${t1.darshanWaitInfo}' : '';
        blocks.add(TimelineBlock(
          start: '09:15 AM',
          end: '10:45 AM',
          type: 'activity',
          title: 'Darshan at ${t1.canonicalName}',
          place: '${t1.canonicalName}, ${t1.city}',
          durationMin: t1Duration > 90 ? 90 : t1Duration,
          reason: '🛕 Deity: ${t1.deity} · ⭐ ${t1.rating}$t1Wait · ${t1.highlights}',
        ));

        final t2 = getNextTemple();
        final t2Duration = t2.recommendedDarshanMinutes;
        final t2Wait = t2.darshanWaitInfo != null ? ' · ⏳ Darshan Wait: ${t2.darshanWaitInfo}' : '';
        blocks.add(TimelineBlock(
          start: '11:00 AM',
          end: '12:30 PM',
          type: 'activity',
          title: 'Visit & Darshan at ${t2.canonicalName}',
          place: '${t2.canonicalName}, ${t2.city}',
          durationMin: t2Duration > 90 ? 90 : t2Duration,
          reason: '🛕 Deity: ${t2.deity} · ⭐ ${t2.rating}$t2Wait · ${t2.highlights}',
        ));

        // Lunch strictly at 12:30 PM
        blocks.add(TimelineBlock(
          start: '12:30 PM',
          end: '01:30 PM',
          type: 'meal',
          title: 'Traditional Farewell Lunch at ${lunchVenue.name}',
          place: '${lunchVenue.name}, ${lunchVenue.city}',
          durationMin: 60,
          breakType: 'lunch',
          reason: '⭐ ${lunchVenue.rating} · ${lunchVenue.specialty}',
        ));

        // Hotel Check-out at 01:30 PM
        blocks.add(TimelineBlock(
          start: '01:30 PM',
          end: '02:00 PM',
          type: 'checkout',
          title: 'Hotel Check-out from ${hotelVenue.name}',
          place: '${hotelVenue.name}, ${hotelVenue.city}',
          durationMin: 30,
          reason: 'Settle bills, load prasadam & luggage into vehicle',
        ));

        // Return Drive
        int cur = 840; // 02:00 PM
        if (totalDriveMin > 180) {
          final ret1 = (totalDriveMin * 0.5).round();
          final ret2 = totalDriveMin - ret1;
          final dist1 = (estimatedKm * 0.5);
          final dist2 = estimatedKm - dist1;

          blocks.add(TimelineBlock(
            start: formatMin(cur),
            end: formatMin(cur + ret1),
            type: 'travel',
            title: 'Return Drive (Highway Leg 1)',
            place: 'National Highway',
            durationMin: ret1,
            travelMin: ret1,
            distanceKm: dist1,
            travelMode: 'drive',
            reason: 'Smooth afternoon highway cruising returning home',
          ));
          cur += ret1;

          blocks.add(TimelineBlock(
            start: formatMin(cur),
            end: formatMin(cur + 45),
            type: 'coffee',
            title: 'Sunset Highway Coffee Break at ${coffeeHighway.name}',
            place: '${coffeeHighway.name}, ${coffeeHighway.city}',
            durationMin: 45,
            breakType: 'coffee',
            reason: '⭐ ${coffeeHighway.rating} · ${coffeeHighway.specialty}',
          ));
          cur += 45;

          blocks.add(TimelineBlock(
            start: formatMin(cur),
            end: formatMin(cur + ret2),
            type: 'return',
            title: 'Return Drive back to $startName',
            place: startName,
            durationMin: ret2,
            travelMin: ret2,
            distanceKm: dist2,
            travelMode: 'drive',
            reason: 'Final evening highway cruise arriving safely back at $startName',
          ));
          cur += ret2;
        } else {
          blocks.add(TimelineBlock(
            start: formatMin(cur),
            end: formatMin(cur + totalDriveMin),
            type: 'return',
            title: 'Return Drive back to $startName',
            place: startName,
            durationMin: totalDriveMin,
            travelMin: totalDriveMin,
            distanceKm: estimatedKm,
            travelMode: 'drive',
            reason: 'Smooth evening highway cruise returning home',
          ));
          cur += totalDriveMin;
        }

        blocks.add(TimelineBlock(
          start: formatMin(cur),
          end: formatMin(cur + 45),
          type: 'meal',
          title: 'Dinner Arrival at $startName',
          place: 'Local Restaurant / Home Diner',
          durationMin: 45,
          breakType: 'dinner',
          reason: 'Relaxing dinner marking the auspicious conclusion of pilgrimage',
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
