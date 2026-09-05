import 'dart:convert';
import 'dart:math' as math;
import 'dart:math' show cos, sin, asin, sqrt;
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode, debugPrint;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import '../models/trip_models.dart';
import '../models/vehicles_data.dart';
import '../config/app_config.dart';
import '../data/temple_database.dart';
import '../data/venue_database.dart';
import '../data/attraction_database.dart';
import 'toll_calculation_service.dart';
import 'fuel_price_service.dart';
import '../utils/trip_date_time.dart';

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

  // Hosted backend, environment-driven (BACKEND_URL define; defaults to prod).
  static const String _prodBackend = AppConfig.backendUrl;

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

  Future<GeoPoint> geocode(String address, {GeoPoint? near}) async {
    // Prefer client-side Mapbox geocoding: the app's Mapbox token is typically
    // URL-restricted to this web origin, so it works from the browser but is
    // Forbidden (403) from the backend — and the backend's Nominatim fallback
    // gets rate-limited (429) on shared cloud IPs. Going direct avoids both.
    // `near` biases ambiguous names toward the trip's area so short itinerary
    // lines ("Lunch in Springfield") don't resolve on another continent.
    if (AppConfig.hasMapboxToken) {
      final gp = await _geocodeWithMapbox(address, near: near);
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
  Future<GeoPoint?> _geocodeWithMapbox(String address, {GeoPoint? near}) async {
    try {
      final uri = Uri.parse(
              'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(address)}.json')
          .replace(queryParameters: {
        'access_token': AppConfig.mapboxToken,
        'limit': '1',
        'language': 'en',
        // Soft ranking bias only (never excludes strong matches elsewhere):
        // the trip's area when known, else India — same as the backend.
        'proximity': near != null ? '${near.lng},${near.lat}' : '78.9629,20.5937',
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
        'start': {'lat': start.lat, 'lng': start.lng, 'name': start.name},
        'end': {'lat': end.lat, 'lng': end.lng, 'name': end.name},
        'waypoints': waypoints.map((w) => {'lat': w.lat, 'lng': w.lng, 'name': w.name}).toList(),
        'vehicle': {
          'type': vehicle.type,
          'efficiencyKmPerLiter': vehicle.efficiencyKmPerLiter,
          'tankCapacityLiters': vehicle.tankCapacityLiters,
          'currentFuelLiters': vehicle.currentFuelLiters,
          'fuelType': vehicle.fuelType,
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

    var plan = TripPlan.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    
    final fuelStops = plan.fuel.refuelStops;
    if (fuelStops.isNotEmpty) {
      debugPrint('[FUEL] Stop received: ${fuelStops.length} stop(s)');
      for (final s in fuelStops) {
        debugPrint('[FUEL] Stop added to itinerary: ${s.name} at (${s.lat}, ${s.lng}), ${s.distanceFromStartKm} km');
      }
    }

    // Ensure tolls are calculated accurately from the actual route polyline and vehicle type
    if (plan.toll == null || plan.toll!.tolls.isEmpty || plan.toll!.isEstimated) {
      final calculatedToll = TollCalculationService.instance.calculateTolls(
        start: start,
        end: end,
        vehicleType: vehicle.type,
        routeCoordinates: plan.coordinates,
      );
      plan = plan.copyWith(toll: calculatedToll);
    }

    // Ensure fuel estimate is calculated accurately from the actual route distance, efficiency, current fuel & fuel type
    if (plan.fuelEstimate == null) {
      final fuelEst = FuelPriceService.instance.calculateRouteFuel(
        distanceKm: plan.distanceKm,
        mileage: vehicle.efficiencyKmPerLiter > 0 ? vehicle.efficiencyKmPerLiter : 15.0,
        fuelType: vehicle.fuelType,
        currentFuelLiters: vehicle.currentFuelLiters,
        tankCapacityLiters: vehicle.tankCapacityLiters,
        originLocation: start.name,
        destLocation: end.name,
      );
      plan = plan.copyWith(fuelEstimate: fuelEst);
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
    // 1. Direct Supabase Insert (zero backend cold-start latency, guaranteed persistence)
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final enrichedEnd = {
          'lat': end.lat,
          'lng': end.lng,
          if (end.name != null) 'name': end.name,
          if (tripStart != null) 'tripStart': tripStart.toIso8601String(),
          if (itinerary != null && itinerary.isNotEmpty) 'itinerary': itinerary,
          if (vehicle != null) 'vehicle': vehicle.toJson(),
        };
        final inserted = await Supabase.instance.client.from('trips').insert({
          'user_id': user.id,
          // Stamp the account email so this trip is visible from the user's
          // other sign-in identities (Google / email / phone). The DB also has
          // a trigger that fills this in, so older app builds stay covered.
          if (user.email != null) 'owner_email': user.email!.toLowerCase(),
          'name': name,
          'start_point': {'lat': start.lat, 'lng': start.lng, if (start.name != null) 'name': start.name},
          'end_point': enrichedEnd,
          'vehicle_type': vehicleType,
        }).select().single();

        if (waypoints.isNotEmpty && inserted['id'] != null) {
          final stops = waypoints.asMap().entries.map((e) => {
            'trip_id': inserted['id'],
            'type': 'waypoint',
            'lat': e.value.lat,
            'lng': e.value.lng,
            'name': e.value.name,
            'order_index': e.key,
          }).toList();
          await Supabase.instance.client.from('trip_stops').insert(stops);
        }
        return;
      }
    } catch (e) {
      debugPrint('Direct Supabase saveTrip note: $e');
    }

    // 2. Backend /api/trip/save fallback
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
            'startPoint': {'lat': start.lat, 'lng': start.lng, if (start.name != null) 'name': start.name},
            'endPoint': {'lat': end.lat, 'lng': end.lng, if (end.name != null) 'name': end.name},
            'waypoints': waypoints.map((w) => {'lat': w.lat, 'lng': w.lng, 'name': w.name}).toList(),
            'vehicleType': vehicleType,
            if (vehicle != null) 'vehicle': vehicle.toJson(),
            if (tripStart != null) 'tripStart': tripStart.toIso8601String(),
            if (itinerary != null && itinerary.isNotEmpty) 'itinerary': itinerary,
          }),
        )
        .timeout(const Duration(seconds: 45), onTimeout: () {
      throw ApiException('Saving is taking too long. Please try again.');
    });

    if (response.statusCode != 200) {
      throw ApiException('Saving trip failed (${response.statusCode}): ${response.body}');
    }
  }

  Future<List<dynamic>> getSavedTrips(String token) async {
    // 1. Direct Supabase Query (instant cross-device sync)
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        // Do NOT filter by user_id here. A user can sign in with different
        // methods (Google / email / phone) on different devices, each a
        // separate auth.users row. RLS now returns every trip owned by this
        // account — matched by user_id OR the account's verified email — so
        // trips saved from another device/identity sync in. Filtering by
        // user_id would re-hide exactly those cross-device trips.
        final data = await Supabase.instance.client
            .from('trips')
            .select('*, trip_stops(*)')
            .order('created_at', ascending: false);
        if (data is List && data.isNotEmpty) {
          final active = data.where((r) {
            final m = (r as Map).cast<String, dynamic>();
            return m['status'] != 'DELETED' && m['deleted_at'] == null;
          }).toList();
          return active;
        }
      }
    } catch (e) {
      debugPrint('Direct Supabase getSavedTrips note: $e');
    }

    // 2. Backend /api/trip/saved fallback
    final uri = Uri.parse('$baseUrl/api/trip/saved');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
      },
    ).timeout(const Duration(seconds: 20), onTimeout: () {
      throw ApiException('Loading your trips is taking too long. Please try again.');
    });

    if (response.statusCode != 200) {
      throw ApiException('Fetching trips failed (${response.statusCode}): ${response.body}');
    }

    final list = jsonDecode(response.body) as List<dynamic>;
    return list.where((r) {
      if (r is Map) {
        return r['status'] != 'DELETED' && r['deleted_at'] == null;
      }
      return true;
    }).toList();
  }

  Future<void> deleteTrip(String id, String token) async {
    final uri = Uri.parse('$baseUrl/api/trip/$id');
    try {
      final response = await http.delete(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 && response.statusCode != 204) {
        debugPrint('Backend deleteTrip note: (${response.statusCode}) ${response.body}');
      }
    } catch (e) {
      debugPrint('Backend deleteTrip exception: $e');
    }
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

    // Tier 1: Instant Local Curated Knowledge Match (prefix or exact primary name only)
    int curatedCount = 0;
    for (final p in _curatedPlaces) {
      final name = p['name'] as String;
      final lowerName = name.toLowerCase();
      final primaryName = lowerName.split(',').first.trim();
      if (lowerName.startsWith(q) || primaryName == q) {
        addResult(name, (p['lat'] as num).toDouble(), (p['lng'] as num).toDouble());
        curatedCount++;
        if (curatedCount >= 2) break; // Allow room for Photon / Mapbox suggestions
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

    // 1. Instant local database check (curated attractions, activities, temples, venues)
    final localMatches = AttractionDatabase.search(query, cityFilter: near);
    if (localMatches.isNotEmpty && qClean.length >= 2) {
      return localMatches.take(15).toList();
    }

    // 2. Try backend AI search
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/ai/search'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'query': query, if (near != null) 'near': near}),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final places = _parseAiPlaces(response);
        if (places.isNotEmpty) return places;
      }
    } catch (_) {
      // Fallback gracefully on timeout or 502
    }

    if (localMatches.isNotEmpty) return localMatches.take(15).toList();

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
    String? startDateTime,
    String? timezone,
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
              if (startTime != null) 'startTime': TripDateTime.to24Hour(startTime),
              if (startDateTime != null)
                'startDateTime': startDateTime
              else if (startDate != null && startTime != null)
                'startDateTime': '$startDate ${TripDateTime.to24Hour(startTime)}',
              'timezone': timezone ?? DateTime.now().timeZoneName,
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
      startTime: startTime ?? '08:00',
      travellers: travellers,
    );
  }

  /// Smart, time-blocked AI itinerary with automatic breaks + per-block reasons,
  /// plus a full trip budget (fuel + tolls + food + stay).
  Future<({
    List<SmartDay> days,
    TripBudget? budget,
    RouteInfo? route,
    NavigationRoute? navigationRoute,
    TripPlan? tripPlan,
    int routeVersion,
    double? totalDistanceKm,
    int? totalDurationMin,
    String? tripType,
    int? searchRadiusKm,
    int? placesFoundCount,
    bool? canExpandSearch,
    int? nextSearchRadiusKm,
  })> aiSmartItinerary({
    required dynamic destination,
    dynamic startLocation = '',
    String tripType = 'around',
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
    String vehicleType = 'car',
    double? fuelEfficiency,
    double? currentFuel,
    double? tankCapacity,
    List<String> selectedCategories = const [],
    Map<String, String> categoryPriorities = const {},
    String customPreferences = '',
    int searchRadiusKm = 25,
  }) async {
    final normStartTime = TripDateTime.to24Hour(startTime);
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/ai/smart-itinerary'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'destination': destination,
              'startLocation': startLocation,
              'tripType': tripType,
              'places': places,
              'startDate': startDate,
              'startTime': normStartTime,
              if (startDate.isNotEmpty)
                'startDateTime': '$startDate $normStartTime',
              'timezone': DateTime.now().timeZoneName,
              'endDate': endDate,
              'endTime': endTime,
              'durationDays': durationDays,
              'mode': mode,
              'preferences': preferences,
              'travellers': travellers,
              'vehicleType': vehicleType,
              if (fuelEfficiency != null) 'fuelEfficiency': fuelEfficiency,
              if (currentFuel != null) 'currentFuel': currentFuel,
              if (tankCapacity != null) 'tankCapacity': tankCapacity,
              if (directive.isNotEmpty) 'directive': directive,
              if (selectedCategories.isNotEmpty) 'selectedCategories': selectedCategories,
              if (categoryPriorities.isNotEmpty) 'categoryPriorities': categoryPriorities,
              if (customPreferences.isNotEmpty) 'customPreferences': customPreferences,
              'searchRadiusKm': searchRadiusKm,
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
        final route = body['route'] != null
            ? RouteInfo.fromJson((body['route'] as Map).cast<String, dynamic>())
            : null;
        final navRoute = body['navigationRoute'] != null
            ? NavigationRoute.fromJson((body['navigationRoute'] as Map).cast<String, dynamic>())
            : null;
        final tripPlan = body['tripPlan'] != null
            ? TripPlan.fromJson((body['tripPlan'] as Map).cast<String, dynamic>())
            : null;
        final routeVersion = (body['routeVersion'] as num?)?.toInt() ?? 1;
        final totalDist = route?.distanceKm ?? (body['totalDistanceKm'] as num?)?.toDouble();
        final totalDur = route?.durationMin ?? (body['totalDurationMin'] as num?)?.toInt();
        final resTripType = body['tripType']?.toString() ?? 'around';
        final resSearchRadius = (body['searchRadiusKm'] as num?)?.toInt();
        final resPlacesCount = (body['placesFoundCount'] as num?)?.toInt();
        final resCanExpand = body['canExpandSearch'] as bool?;
        final resNextRadius = (body['nextSearchRadiusKm'] as num?)?.toInt();

        if (days.isNotEmpty) {
          return (
            days: days,
            budget: budget,
            route: route,
            navigationRoute: navRoute,
            tripPlan: tripPlan,
            routeVersion: routeVersion,
            totalDistanceKm: totalDist,
            totalDurationMin: totalDur,
            tripType: resTripType,
            searchRadiusKm: resSearchRadius,
            placesFoundCount: resPlacesCount,
            canExpandSearch: resCanExpand,
            nextSearchRadiusKm: resNextRadius,
          );
        }
      }
    } catch (_) {}

    // Fallback: Built-in Smart Itinerary & Budget Generator
    final fb = _generateFallbackSmartItinerary(
      destination: destination,
      startLocation: startLocation,
      places: places,
      preferences: preferences,
      durationDays: durationDays,
      startTime: normStartTime,
      travellers: travellers,
      fuelEfficiency: fuelEfficiency,
      selectedCategories: selectedCategories,
      categoryPriorities: categoryPriorities,
      customPreferences: customPreferences,
    );
    return (
      days: fb.days,
      budget: fb.budget,
      route: null,
      navigationRoute: null,
      tripPlan: null,
      routeVersion: 1,
      totalDistanceKm: null,
      totalDurationMin: null,
      tripType: 'around',
      searchRadiusKm: searchRadiusKm,
      placesFoundCount: fb.days.fold(0, (sum, d) => sum + d.blocks.where((b) => b.type == 'activity').length),
      canExpandSearch: false,
      nextSearchRadiusKm: null,
    );
  }

  /// Recalculate itinerary on edits (stop removal, reordering, duration adjustment, start time shift).
  Future<({
    List<SmartDay> days,
    TripBudget? budget,
    RouteInfo? route,
    NavigationRoute? navigationRoute,
    TripPlan? tripPlan,
    double totalDistanceKm,
    int totalDurationMin,
    int routeVersion,
  })?> recalculateSmartItinerary({
    required List<SmartDay> days,
    String? startTime,
    String? tripType,
    dynamic origin,
    dynamic destination,
    double? currentFuel,
    double? tankCapacity,
    double? fuelEfficiency,
    int travellers = 1,
    int routeVersion = 1,
    bool isConfirmed = false,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/ai/recalculate-itinerary'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'days': days.map((d) => d.toJson()).toList(),
              if (startTime != null) 'startTime': startTime,
              if (tripType != null) 'tripType': tripType,
              if (origin != null) 'origin': origin,
              if (destination != null) 'destination': destination,
              if (currentFuel != null) 'currentFuel': currentFuel,
              if (tankCapacity != null) 'tankCapacity': tankCapacity,
              if (fuelEfficiency != null) 'fuelEfficiency': fuelEfficiency,
              'travellers': travellers,
              'routeVersion': routeVersion,
              'isConfirmed': isConfirmed,
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final newDays = (body['days'] as List? ?? [])
            .map((e) => SmartDay.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        final budget = body['budget'] != null
            ? TripBudget.fromJson((body['budget'] as Map).cast<String, dynamic>())
            : null;
        final route = body['route'] != null
            ? RouteInfo.fromJson((body['route'] as Map).cast<String, dynamic>())
            : null;
        final navRoute = body['navigationRoute'] != null
            ? NavigationRoute.fromJson((body['navigationRoute'] as Map).cast<String, dynamic>())
            : null;
        final tripPlan = body['tripPlan'] != null
            ? TripPlan.fromJson((body['tripPlan'] as Map).cast<String, dynamic>())
            : null;
        final totalDist = route?.distanceKm ?? ((body['totalDistanceKm'] as num?)?.toDouble() ?? 0.0);
        final totalDur = route?.durationMin ?? ((body['totalDurationMin'] as num?)?.toInt() ?? 0);
        final rVer = (body['routeVersion'] as num?)?.toInt() ?? (routeVersion + 1);

        return (
          days: newDays,
          budget: budget,
          route: route,
          navigationRoute: navRoute,
          tripPlan: tripPlan,
          totalDistanceKm: totalDist,
          totalDurationMin: totalDur,
          routeVersion: rVer,
        );
      }
    } catch (_) {}
    return null;
  }

  /// Authoritative single source of truth for trip route calculation.
  Future<({
    RouteInfo route,
    NavigationRoute navigationRoute,
    TripBudget? budget,
    int routeVersion,
  })> calculateTripRoute({
    required GeoPoint origin,
    required GeoPoint destination,
    List<TimelineBlock> stops = const [],
    Vehicle? vehicle,
    String tripType = 'around',
    int durationDays = 1,
    int travellers = 1,
    int routeVersion = 1,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/trip/calculate-route'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'origin': origin.toJson(),
            'destination': destination.toJson(),
            'stops': stops.map((s) => s.toJson()).toList(),
            'vehicle': vehicle != null
                ? {
                    'type': vehicle.type,
                    'efficiencyKmPerLiter': vehicle.efficiencyKmPerLiter,
                    'tankCapacityLiters': vehicle.tankCapacityLiters,
                    'currentFuelLiters': vehicle.currentFuelLiters,
                    'fuelType': vehicle.fuelType,
                  }
                : {},
            'tripType': tripType,
            'durationDays': durationDays,
            'travellers': travellers,
            'routeVersion': routeVersion,
          }),
        )
        .timeout(const Duration(seconds: 25));

    if (response.statusCode != 200) {
      throw ApiException('Route calculation failed (${response.statusCode}): ${response.body}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final route = RouteInfo.fromJson((body['route'] as Map).cast<String, dynamic>());
    final navRoute = NavigationRoute.fromJson((body['navigationRoute'] as Map).cast<String, dynamic>());
    final budget = body['budget'] != null ? TripBudget.fromJson((body['budget'] as Map).cast<String, dynamic>()) : null;
    final rVersion = (body['routeVersion'] as num?)?.toInt() ?? (routeVersion + 1);

    return (
      route: route,
      navigationRoute: navRoute,
      budget: budget,
      routeVersion: rVersion,
    );
  }


  List<Map<String, dynamic>> _generateFallbackBuildItinerary({
    required String start,
    required String end,
    int days = 1,
    String startTime = '08:00',
    int travellers = 1,
  }) {
    final res = <Map<String, dynamic>>[];
    final total = math.max(1, days);
    final startMin = TripDateTime.parseMinutes(startTime);
    final canonicalStart24 = TripDateTime.to24Hour(startTime);
    final h24 = (startMin ~/ 60) % 24;
    final startPart = h24 < 12 ? 'Morning' : (h24 < 17 ? 'Afternoon' : (h24 < 21 ? 'Evening' : 'Night'));

    for (int d = 1; d <= total; d++) {
      final isFirst = d == 1;
      final isLast = d == total;
      res.add({
        'day': d,
        'title': isFirst ? 'Journey to $end & Exploration' : (isLast ? 'Farewell $end & Return' : '$end Highlights & Culture'),
        'activities': [
          {
            'part': isFirst ? startPart : 'Morning',
            'time': isFirst ? canonicalStart24 : '08:00',
            'title': isFirst ? 'Drive from $start to $end' : 'Breakfast & Morning Sights in $end',
            'note': isFirst ? 'Scenic drive along the highway' : 'Fresh regional breakfast and sightseeing visit',
          },
          {
            'part': 'Afternoon',
            'time': '13:00',
            'title': 'Heritage Exploration & Lunch',
            'note': 'Authentic meal and iconic landmark/heritage visit',
          },
          {
            'part': 'Evening',
            'time': '17:30',
            'title': isLast ? 'Sunset Return Drive to $start' : 'Sunset Viewpoint & Local Bazaar',
            'note': isLast ? 'Comfortable highway return journey' : 'Tea, photography and local shopping',
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
    List<String> selectedCategories = const [],
    Map<String, String> categoryPriorities = const {},
    String customPreferences = '',
  }) {
    final total = math.max(1, math.min(durationDays, 14));
    final destName = destination.isNotEmpty ? destination : 'Destination';
    final startName = startLocation.isNotEmpty ? startLocation : 'Home';
    final daysList = <SmartDay>[];

    String cleanCityName(String str) {
      if (str.isEmpty) return 'Destination';
      final raw = str.split(',').first.trim();
      final noParen = raw.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
      return noParen.isNotEmpty ? noParen : raw;
    }

    final cleanCity = cleanCityName(destName);
    final text = '$destination $preferences $customPreferences ${places.join(" ")}'.toLowerCase();

    // Extract search terms including aliases in parentheses e.g. "Mangaluru (Mangalore)" -> ["mangaluru", "mangalore"]
    final parenMatch = RegExp(r'\(([^)]+)\)').firstMatch(destName);
    final parenAlias = parenMatch != null ? parenMatch.group(1)!.toLowerCase().trim() : '';
    final searchTerms = [cleanCity.toLowerCase(), parenAlias].where((s) => s.length >= 3).toList();

    // 1. Comprehensive attraction database across 16 categories
    final allAttractions = <_FallbackAttraction>[
      // --- Mangaluru & Udupi Coastal Circuit ---
      const _FallbackAttraction(name: 'Kudroli Gokarnanatheshwara Temple', city: 'Mangaluru (Mangalore)', rating: '4.8', durationMin: 75, highlight: 'Illuminated marble corridors, golden gopuram & sacred Pushkarini', categories: ['Temples & Religious Places', 'Cultural Places', 'Historical & Heritage Places']),
      const _FallbackAttraction(name: 'Panambur Beach & Water Sports', city: 'Mangaluru (Mangalore)', rating: '4.7', durationMin: 90, highlight: 'Jet skiing, boat rides, camel rides & sunset photography along Arabian Sea', categories: ['Beaches', 'Famous City Attractions', 'Instagrammable / Photography Spots']),
      const _FallbackAttraction(name: 'Tannirbhavi Beach & Tree Park', city: 'Mangaluru (Mangalore)', rating: '4.7', durationMin: 90, highlight: 'Tranquil beach with dense pine canopy, ferry crossing & walking trails', categories: ['Beaches', 'Nature & Forests', 'Viewpoints & Scenic Places']),
      const _FallbackAttraction(name: 'Kadri Manjunath Temple & Ancient Caves', city: 'Mangaluru (Mangalore)', rating: '4.8', durationMin: 75, highlight: 'Historic hill shrine with natural mountain springs & Pandava caves', categories: ['Temples & Religious Places', 'Historical & Heritage Places', 'Hills & Mountains']),
      const _FallbackAttraction(name: 'St. Aloysius Chapel & Heritage Art Gallery', city: 'Mangaluru (Mangalore)', rating: '4.8', durationMin: 60, highlight: 'Magnificent Sistine Chapel-style ceiling frescoes by Italian Jesuit Bro. Moscheni', categories: ['Historical & Heritage Places', 'Cultural Places', 'Monuments & Landmarks']),
      const _FallbackAttraction(name: 'Pilikula Nisargadhama Biological Park', city: 'Mangaluru (Mangalore)', rating: '4.7', durationMin: 150, highlight: 'Safari zoo, heritage artisanal village, lake boating & 3D planetarium', categories: ['Wildlife & National Parks', 'Nature & Forests', 'Rivers, Lakes & Waterfalls']),
      const _FallbackAttraction(name: 'Sultan Battery & Gurupura Riverfront', city: 'Mangaluru (Mangalore)', rating: '4.6', durationMin: 60, highlight: 'Tipu Sultan 1784 naval watchtower overlooking river mouth & boat jetty', categories: ['Forts & Palaces', 'Historical & Heritage Places', 'Rivers, Lakes & Waterfalls']),
      const _FallbackAttraction(name: 'Someshwara Beach & Rudra Shile Rocks', city: 'Ullal, Mangaluru', rating: '4.7', durationMin: 75, highlight: 'Dramatic large monolithic sea boulders & panoramic sunset viewpoint', categories: ['Beaches', 'Viewpoints & Scenic Places', 'Instagrammable / Photography Spots']),
      const _FallbackAttraction(name: 'Surathkal Lighthouse & Beach Lookout', city: 'Surathkal, Mangaluru', rating: '4.7', durationMin: 60, highlight: 'Panoramic 360-degree ocean lookout atop rocky coastal lighthouse hill', categories: ['Viewpoints & Scenic Places', 'Beaches', 'Monuments & Landmarks']),
      const _FallbackAttraction(name: 'Kateel Sri Durgaparameshwari Temple', city: 'Kateel, Mangaluru', rating: '4.8', durationMin: 90, highlight: 'Sacred river island sanctum surrounded by rushing streams of Nandini river', categories: ['Temples & Religious Places', 'Rivers, Lakes & Waterfalls']),
      const _FallbackAttraction(name: 'Udupi Sri Krishna Matha & Temple Square', city: 'Udupi', rating: '4.9', durationMin: 90, highlight: 'Historic 13th-century Madhvacharya matha, golden ratha & holy pond', categories: ['Temples & Religious Places', 'Cultural Places', 'Famous / Must-Visit Places']),
      const _FallbackAttraction(name: 'Malpe Beach & St. Mary\'s Island', city: 'Malpe, Udupi', rating: '4.8', durationMin: 180, highlight: 'Scenic ferry ride to million-year-old columnar basalt rock formations', categories: ['Beaches', 'Nature & Forests', 'Instagrammable / Photography Spots', 'Famous / Must-Visit Places']),

      // --- Chikmagalur & Western Ghats ---
      const _FallbackAttraction(name: 'Mullayanagiri Peak & Trekking Ridge', city: 'Chikmagalur', rating: '4.8', durationMin: 150, highlight: 'Sweeping Western Ghats mountain vistas, cool mist and hilltop temple', categories: ['Hills & Mountains', 'Viewpoints & Scenic Places', 'Instagrammable / Photography Spots']),
      const _FallbackAttraction(name: 'Baba Budangiri & Datta Peeta', city: 'Chikmagalur', rating: '4.7', durationMin: 120, highlight: 'Dramatic mountain pass, historic caves and origin of Indian coffee', categories: ['Hills & Mountains', 'Cultural Places', 'Historical & Heritage Places']),
      const _FallbackAttraction(name: 'Hebbe Falls & Mountain Stream Trek', city: 'Near Chikmagalur', rating: '4.8', durationMin: 180, highlight: 'Exciting 4x4 jungle ride & trek through coffee plantations to roaring falls', categories: ['Rivers, Lakes & Waterfalls', 'Nature & Forests', 'Hills & Mountains']),
      const _FallbackAttraction(name: 'Z Point Sunset Lookout', city: 'Kemmanagundi, Chikmagalur', rating: '4.7', durationMin: 90, highlight: 'Thrilling cliffside walking trail with 360-degree green valley views', categories: ['Viewpoints & Scenic Places', 'Hills & Mountains', 'Instagrammable / Photography Spots']),

      // --- Wayanad ---
      const _FallbackAttraction(name: 'Banasura Sagar Dam & Speed Boating', city: 'Wayanad', rating: '4.7', durationMin: 120, highlight: 'Speed boating in emerald reservoir surrounded by misty Banasura hills', categories: ['Famous Bridges / Dams', 'Rivers, Lakes & Waterfalls', 'Viewpoints & Scenic Places']),
      const _FallbackAttraction(name: 'Edakkal Caves & Ancient Stone Age Carvings', city: 'Wayanad', rating: '4.7', durationMin: 120, highlight: 'Scenic uphill mountain trek to prehistoric rock engravings & valley view', categories: ['Historical & Heritage Places', 'Hills & Mountains', 'Cultural Places']),
      const _FallbackAttraction(name: 'Soochipara Waterfalls (Sentinel Rock)', city: 'Meppadi, Wayanad', rating: '4.7', durationMin: 120, highlight: 'Walk through tea plantations and lush evergreen forest to natural pool', categories: ['Rivers, Lakes & Waterfalls', 'Nature & Forests', 'Instagrammable / Photography Spots']),
      const _FallbackAttraction(name: 'Lakkidi View Point & Ghat Road Vista', city: 'Lakkidi, Wayanad', rating: '4.6', durationMin: 60, highlight: 'Dramatic 700m high cliff edge looking over winding Thamarassery Churam', categories: ['Viewpoints & Scenic Places', 'Hills & Mountains']),

      // --- Mumbai ---
      const _FallbackAttraction(name: 'Gateway of India & Apollo Bunder', city: 'Mumbai', rating: '4.8', durationMin: 90, highlight: 'Iconic 1924 basalt arch monument overlooking Mumbai harbour', categories: ['Historical & Heritage Places', 'Monuments & Landmarks', 'Famous / Must-Visit Places']),
      const _FallbackAttraction(name: 'Bandra-Worli Sea Link & Sea View Promenade', city: 'Mumbai', rating: '4.8', durationMin: 60, highlight: 'Spectacular 8-lane cable-stayed bridge spanning the Arabian Sea', categories: ['Famous Bridges / Dams', 'Viewpoints & Scenic Places', 'Instagrammable / Photography Spots']),
      const _FallbackAttraction(name: 'Marine Drive & Queen\'s Necklace Viewpoint', city: 'Mumbai', rating: '4.8', durationMin: 90, highlight: 'Curved 3.6 km coastal promenade with sweeping sunset Arabian sea views', categories: ['Viewpoints & Scenic Places', 'Famous City Attractions', 'Instagrammable / Photography Spots']),
      const _FallbackAttraction(name: 'Chhatrapati Shivaji Maharaj Terminus (CSMT)', city: 'Mumbai', rating: '4.8', durationMin: 60, highlight: 'UNESCO World Heritage Victorian Gothic architecture & illuminated facade', categories: ['Historical & Heritage Places', 'Monuments & Landmarks', 'Famous / Must-Visit Places']),
      const _FallbackAttraction(name: 'Elephanta Caves & Island Ferry', city: 'Mumbai', rating: '4.7', durationMin: 180, highlight: 'Rock-cut 5th-century cave temples of Lord Shiva reached by scenic boat ride', categories: ['Historical & Heritage Places', 'Cultural Places', 'Rivers, Lakes & Waterfalls']),
      const _FallbackAttraction(name: 'Sanjay Gandhi National Park & Kanheri Caves', city: 'Mumbai', rating: '4.7', durationMin: 180, highlight: 'Protected green forest reserve with ancient Buddhist caves and tiger safari', categories: ['Wildlife & National Parks', 'Nature & Forests', 'Hills & Mountains']),
      const _FallbackAttraction(name: 'Juhu Beach & Street Food Boulevard', city: 'Mumbai', rating: '4.6', durationMin: 90, highlight: 'Sunset beach with famous Pav Bhaji, Bhel Puri and Arabian Sea breezes', categories: ['Beaches', 'Famous Markets & Local Places', 'Famous City Attractions']),
      const _FallbackAttraction(name: 'Colaba Causeway & Heritage Art District', city: 'Mumbai', rating: '4.7', durationMin: 90, highlight: 'Bustling artisanal shopping bazaar, vintage cafes and art galleries', categories: ['Famous Markets & Local Places', 'Cultural Places']),
      const _FallbackAttraction(name: 'Malabar Hill & Hanging Gardens', city: 'Mumbai', rating: '4.6', durationMin: 60, highlight: 'Terraced hilltop gardens with panoramic views of the city skyline', categories: ['Hills & Mountains', 'Viewpoints & Scenic Places', 'Nature & Forests']),
      const _FallbackAttraction(name: 'Shree Siddhivinayak Temple', city: 'Mumbai', rating: '4.8', durationMin: 75, highlight: 'Historic 1801 gold-plated sanctum dedicated to Lord Ganesha', categories: ['Temples & Religious Places']),

      // --- Mysuru ---
      const _FallbackAttraction(name: 'Mysore Palace (Amba Vilas)', city: 'Mysuru', rating: '4.8', durationMin: 150, highlight: 'Golden Throne, stained glass Kalyana Mantapa & illuminated royal durbar', categories: ['Forts & Palaces', 'Historical & Heritage Places', 'Famous / Must-Visit Places']),
      const _FallbackAttraction(name: 'Brindavan Gardens & Musical Dancing Fountain', city: 'Mysuru', rating: '4.7', durationMin: 120, highlight: 'Terraced botanical gardens and synchronized musical dancing fountains', categories: ['Nature & Forests', 'Rivers, Lakes & Waterfalls', 'Famous City Attractions']),
      const _FallbackAttraction(name: 'Sri Chamarajendra Zoological Gardens (Mysore Zoo)', city: 'Mysuru', rating: '4.8', durationMin: 150, highlight: 'Historic 1892 sanctuary with giraffes, big cats & exotic birds', categories: ['Wildlife & National Parks', 'Nature & Forests', 'Famous / Must-Visit Places']),
      const _FallbackAttraction(name: 'KRS Dam (Krishna Raja Sagara Dam)', city: 'Mysuru', rating: '4.7', durationMin: 90, highlight: 'Majestic Kaveri river reservoir dam gates & illuminated walkways', categories: ['Famous Bridges / Dams', 'Rivers, Lakes & Waterfalls', 'Viewpoints & Scenic Places']),
      const _FallbackAttraction(name: 'Karanji Lake & Walk-Through Aviary', city: 'Mysuru', rating: '4.6', durationMin: 75, highlight: 'Scenic lake boating, butterfly park & India\'s largest walk-through aviary', categories: ['Rivers, Lakes & Waterfalls', 'Nature & Forests', 'Viewpoints & Scenic Places']),
      const _FallbackAttraction(name: 'Devaraja Heritage Spice & Silk Market', city: 'Mysuru', rating: '4.7', durationMin: 75, highlight: 'Vibrant 100-year-old market with pure sandalwood, silk & Mysore Pak', categories: ['Famous Markets & Local Places', 'Cultural Places', 'Famous City Attractions']),
      const _FallbackAttraction(name: 'St. Philomena\'s Neo-Gothic Cathedral', city: 'Mysuru', rating: '4.7', durationMin: 45, highlight: 'Twin 175ft spires, stained glass French windows & subterranean crypts', categories: ['Monuments & Landmarks', 'Historical & Heritage Places', 'Cultural Places']),
      const _FallbackAttraction(name: 'Jaganmohan Palace & Royal Art Gallery', city: 'Mysuru', rating: '4.7', durationMin: 90, highlight: 'Historic royal gallery housing original Raja Ravi Varma oil masterpieces', categories: ['Cultural Places', 'Forts & Palaces', 'Historical & Heritage Places']),
      const _FallbackAttraction(name: 'Sri Chamundeshwari Temple & Monolithic Nandi', city: 'Chamundi Hills, Mysuru', rating: '4.8', durationMin: 90, highlight: 'Hilltop Shakti Peetha & 16ft monolithic Nandi statue', categories: ['Temples & Religious Places', 'Viewpoints & Scenic Places', 'Hills & Mountains']),
      const _FallbackAttraction(name: 'Ranganathittu Bird Sanctuary', city: 'Srirangapatna', rating: '4.8', durationMin: 90, highlight: 'Kaveri river boat safari viewing migratory storks, pelicans & crocodiles', categories: ['Wildlife & National Parks', 'Rivers, Lakes & Waterfalls', 'Nature & Forests']),

      // --- Coorg ---
      const _FallbackAttraction(name: 'Abbey Falls & Hanging Bridge', city: 'Madikeri, Coorg', rating: '4.7', durationMin: 75, highlight: '70ft roaring waterfall surrounded by private coffee and spice estates', categories: ['Rivers, Lakes & Waterfalls', 'Nature & Forests', 'Instagrammable / Photography Spots']),
      const _FallbackAttraction(name: 'Raja\'s Seat Sunset Viewpoint', city: 'Madikeri, Coorg', rating: '4.7', durationMin: 60, highlight: 'Panoramic sunset view over Western Ghats mist-covered valleys', categories: ['Viewpoints & Scenic Places', 'Hills & Mountains', 'Instagrammable / Photography Spots']),
      const _FallbackAttraction(name: 'Dubare Elephant Camp & River Crossing', city: 'Kushalnagar, Coorg', rating: '4.7', durationMin: 120, highlight: 'Interactive elephant care, river boating & white water rafting', categories: ['Wildlife & National Parks', 'Rivers, Lakes & Waterfalls', 'Nature & Forests']),
      const _FallbackAttraction(name: 'Namdroling Monastery (Golden Temple)', city: 'Bylakuppe, Coorg', rating: '4.8', durationMin: 90, highlight: '40ft gold-plated Buddha statues, ornate Tibetan murals & peace bell', categories: ['Cultural Places', 'Temples & Religious Places', 'Famous / Must-Visit Places']),
      const _FallbackAttraction(name: 'Mandalpatti Peak 4x4 Jeep Safari', city: 'Madikeri, Coorg', rating: '4.8', durationMin: 150, highlight: 'Off-road 4x4 adventure through clouds to 4000ft high mountain ridge', categories: ['Hills & Mountains', 'Viewpoints & Scenic Places', 'Instagrammable / Photography Spots']),
      const _FallbackAttraction(name: 'Nagarhole National Park (Kabini Safari)', city: 'Coorg / Kabini', rating: '4.8', durationMin: 180, highlight: 'Forest jeep safari spotting wild Asian elephants, leopards & tigers', categories: ['Wildlife & National Parks', 'Nature & Forests']),

      // --- Ooty ---
      const _FallbackAttraction(name: 'Ooty Botanical Gardens & Victorian Glass House', city: 'Ooty', rating: '4.7', durationMin: 90, highlight: 'Historic 55-acre garden with 20-million-year-old fossilized tree', categories: ['Nature & Forests', 'Famous City Attractions']),
      const _FallbackAttraction(name: 'Doddabetta Peak & Telescope Observatory', city: 'Ooty', rating: '4.7', durationMin: 75, highlight: 'Highest peak in Nilgiris (8650ft) with 360-degree telescope observatory', categories: ['Hills & Mountains', 'Viewpoints & Scenic Places', 'Instagrammable / Photography Spots']),
      const _FallbackAttraction(name: 'Ooty Lake & Boating Promenade', city: 'Ooty', rating: '4.6', durationMin: 75, highlight: 'Picturesque mountain lake surrounded by towering eucalyptus groves', categories: ['Rivers, Lakes & Waterfalls', 'Famous City Attractions']),
      const _FallbackAttraction(name: 'Pykara Waterfalls & Lake Speed Boating', city: 'Near Ooty', rating: '4.7', durationMin: 90, highlight: 'Pristine tiered waterfalls and tranquil speed boat lake cruises', categories: ['Rivers, Lakes & Waterfalls', 'Nature & Forests', 'Instagrammable / Photography Spots']),
      const _FallbackAttraction(name: 'Nilgiri Mountain Railway Toy Train', city: 'Ooty / Coonoor', rating: '4.8', durationMin: 120, highlight: 'UNESCO Heritage vintage steam train winding through mist and tunnels', categories: ['Historical & Heritage Places', 'Famous / Must-Visit Places', 'Cultural Places']),

      // --- Bengaluru ---
      const _FallbackAttraction(name: 'Bangalore Palace & Royal Grounds', city: 'Bengaluru', rating: '4.7', durationMin: 120, highlight: 'Wodeyar Tudor-style fortified turrets, royal ballrooms & manicured lawns', categories: ['Forts & Palaces', 'Historical & Heritage Places', 'Famous / Must-Visit Places']),
      const _FallbackAttraction(name: 'Lalbagh Botanical Garden & Glass House', city: 'Bengaluru', rating: '4.8', durationMin: 120, highlight: 'Victorian Glass House, lotus lake and 3000-million-year peninsular rock', categories: ['Nature & Forests', 'Famous City Attractions', 'Instagrammable / Photography Spots']),
      const _FallbackAttraction(name: 'Bannerghatta National Park & Safari', city: 'Bengaluru', rating: '4.7', durationMin: 180, highlight: 'Grand wildlife reserve, bus safari and butterfly conservatory', categories: ['Wildlife & National Parks', 'Nature & Forests']),
      const _FallbackAttraction(name: 'Cubbon Park & Vidhana Soudha Architecture', city: 'Bengaluru', rating: '4.7', durationMin: 75, highlight: 'Neo-Dravidian architecture and shaded colonial park promenades', categories: ['Monuments & Landmarks', 'Nature & Forests', 'Famous City Attractions']),
      const _FallbackAttraction(name: 'Nandi Hills & Sunrise Cloud-Sea Vista', city: 'Near Bengaluru', rating: '4.8', durationMin: 150, highlight: '4851ft mountain fortress with sea of clouds sunrise view', categories: ['Hills & Mountains', 'Viewpoints & Scenic Places', 'Instagrammable / Photography Spots']),
      const _FallbackAttraction(name: 'Commercial Street & Brigade Road Bazaar', city: 'Bengaluru', rating: '4.6', durationMin: 90, highlight: 'Bustling shopping lanes with artisanal silk, crafts and cafes', categories: ['Famous Markets & Local Places', 'Famous City Attractions']),
    ];

    // Filter candidate places for the destination using search terms
    var cityCandidates = allAttractions.where((a) =>
      searchTerms.any((st) => a.city.toLowerCase().contains(st) || text.contains(st))
    ).toList();

    // Strict Category Filtering
    final hasCategoryFilter = selectedCategories.isNotEmpty;
    final templesAllowed = !hasCategoryFilter || selectedCategories.contains('Temples & Religious Places');

    var pool = <_FallbackAttraction>[];

    if (hasCategoryFilter) {
      pool = cityCandidates.where((a) =>
        a.categories.any((c) => selectedCategories.contains(c))
      ).toList();

      if (!templesAllowed) {
        pool = pool.where((a) => !a.categories.contains('Temples & Religious Places')).toList();
      }

      // Prioritize Must Visit
      pool.sort((a, b) {
        final aMust = a.categories.any((c) => categoryPriorities[c] == 'must_visit');
        final bMust = b.categories.any((c) => categoryPriorities[c] == 'must_visit');
        if (aMust && !bMust) return -1;
        if (!aMust && bMust) return 1;
        return 0;
      });
    } else {
      pool = cityCandidates.isNotEmpty ? cityCandidates : [];
    }

    _FallbackAttraction synthesizeAttraction(String city, String cat, int count) {
      final c = count > 0 ? count : 1;
      if (cat == 'Temples & Religious Places') {
        final names = ['$city Sacred Heritage Shrine', '$city Hilltop Spiritual Sanctum', '$city Ancient Cultural Temple'];
        return _FallbackAttraction(name: names[(c - 1) % names.length], city: city, rating: '4.8', durationMin: 75, highlight: 'Historic sanctum, spiritual heritage and traditional stone architecture', categories: const ['Temples & Religious Places', 'Historical & Heritage Places']);
      }
      if (cat == 'Beaches') {
        final names = ['$city Sunset Beach & Coastal Walkway', '$city Golden Sands Promenade', '$city Coastal Bay & Water Sports Beach'];
        return _FallbackAttraction(name: names[(c - 1) % names.length], city: city, rating: '4.8', durationMin: 90, highlight: 'Golden sand coastline, sea breeze and evening coastal sunset', categories: const ['Beaches', 'Viewpoints & Scenic Places', 'Instagrammable / Photography Spots']);
      }
      if (cat == 'Hills & Mountains') {
        final names = ['$city Misty Mountain Peak & Ridge Lookout', '$city Valley Viewpoint & Mountain Trail', '$city Cloud-Capped Hilltop Ridge'];
        return _FallbackAttraction(name: names[(c - 1) % names.length], city: city, rating: '4.8', durationMin: 120, highlight: 'High altitude clouds, mountain breeze and valley vistas', categories: const ['Hills & Mountains', 'Viewpoints & Scenic Places']);
      }
      if (cat == 'Rivers, Lakes & Waterfalls') {
        final names = ['$city Scenic Waterfalls & Cascades', '$city Lakefront Promenade & Boating', '$city Natural River Gorge & Falls'];
        return _FallbackAttraction(name: names[(c - 1) % names.length], city: city, rating: '4.8', durationMin: 90, highlight: 'Cascading natural waterfalls and serene water promenade', categories: const ['Rivers, Lakes & Waterfalls', 'Nature & Forests']);
      }
      if (cat == 'Viewpoints & Scenic Places') {
        final names = ['$city Panoramic Sunset Valley Viewpoint', '$city Skyline Lookout & Promenade', '$city Scenic Landscape Vista'];
        return _FallbackAttraction(name: names[(c - 1) % names.length], city: city, rating: '4.8', durationMin: 60, highlight: 'Breathtaking 360-degree landscape and golden hour sunset vista', categories: const ['Viewpoints & Scenic Places', 'Instagrammable / Photography Spots']);
      }
      if (cat == 'Forts & Palaces') {
        final names = ['$city Historic Royal Fort & Bastion', '$city Heritage Palace & Royal Grounds', '$city Ancient Citadel & Courtyard'];
        return _FallbackAttraction(name: names[(c - 1) % names.length], city: city, rating: '4.8', durationMin: 120, highlight: 'Grand royal architecture and fortified courtyard grounds', categories: const ['Forts & Palaces', 'Historical & Heritage Places']);
      }
      if (cat == 'Wildlife & National Parks') {
        final names = ['$city Wildlife Sanctuary & Safari', '$city Nature Reserve & Fauna Park', '$city Botanical Bird Sanctuary'];
        return _FallbackAttraction(name: names[(c - 1) % names.length], city: city, rating: '4.8', durationMin: 150, highlight: 'Protected natural fauna habitat and guided flora safari', categories: const ['Wildlife & National Parks', 'Nature & Forests']);
      }
      if (cat == 'Nature & Forests') {
        final names = ['$city Lush Botanical Gardens & Tree Park', '$city Forest Reserve & Canopy Trail', '$city Green Valley Eco Park'];
        return _FallbackAttraction(name: names[(c - 1) % names.length], city: city, rating: '4.7', durationMin: 90, highlight: 'Scenic canopy walkways, rare flora and peaceful nature trails', categories: const ['Nature & Forests', 'Rivers, Lakes & Waterfalls']);
      }
      if (cat == 'Famous Markets & Local Places') {
        final names = ['$city Traditional Artisan Bazaar', '$city Heritage Spice & Craft Market', '$city Local Food & Souvenir Street'];
        return _FallbackAttraction(name: names[(c - 1) % names.length], city: city, rating: '4.7', durationMin: 75, highlight: 'Vibrant local market with regional delicacies, handicrafts and spices', categories: const ['Famous Markets & Local Places', 'Cultural Places']);
      }
      return _FallbackAttraction(name: '$city Iconic Heritage Landmark $c', city: city, rating: '4.8', durationMin: 90, highlight: 'Regional landmark, photography spot and cultural heritage', categories: [cat.isNotEmpty ? cat : 'Famous / Must-Visit Places']);
    }

    // Time-of-Day Intelligent Category Selector (Never repeats any place across days)
    final usedAttractionNames = <String>{};
    int slotCounter = 0;

    _FallbackAttraction getNextAttraction([String timeSlot = 'any']) {
      final preferred = <String>[];
      if (timeSlot == 'morning') {
        preferred.addAll(['Temples & Religious Places', 'Hills & Mountains', 'Wildlife & National Parks', 'Rivers, Lakes & Waterfalls', 'Nature & Forests']);
      } else if (timeSlot == 'sunset' || timeSlot == 'evening') {
        preferred.addAll(['Beaches', 'Viewpoints & Scenic Places', 'Famous Bridges / Dams', 'Instagrammable / Photography Spots', 'Famous City Attractions', 'Famous Markets & Local Places']);
      } else if (timeSlot == 'afternoon') {
        preferred.addAll(['Historical & Heritage Places', 'Forts & Palaces', 'Cultural Places', 'Monuments & Landmarks', 'Famous City Attractions']);
      }

      String? targetCategory;
      if (hasCategoryFilter && selectedCategories.isNotEmpty) {
        final aligned = selectedCategories.where((c) => preferred.contains(c)).toList();
        if (aligned.isNotEmpty) {
          targetCategory = aligned[slotCounter % aligned.length];
        } else {
          targetCategory = selectedCategories[slotCounter % selectedCategories.length];
        }
      }
      slotCounter++;

      _FallbackAttraction? chosen;
      if (targetCategory != null) {
        for (final t in pool) {
          if (!usedAttractionNames.contains(t.name) && t.categories.contains(targetCategory)) {
            chosen = t;
            break;
          }
        }
      }
      if (chosen == null && preferred.isNotEmpty) {
        for (final t in pool) {
          if (!usedAttractionNames.contains(t.name) && t.categories.any((c) => preferred.contains(c))) {
            chosen = t;
            break;
          }
        }
      }
      if (chosen == null) {
        for (final t in pool) {
          if (!usedAttractionNames.contains(t.name)) {
            chosen = t;
            break;
          }
        }
      }

      if (chosen == null) {
        final cat = targetCategory ?? (preferred.isNotEmpty ? preferred.first : (selectedCategories.isNotEmpty ? selectedCategories.first : 'Famous / Must-Visit Places'));
        final synthCount = usedAttractionNames.length + 1;
        chosen = synthesizeAttraction(cleanCity, cat, synthCount);
      }

      usedAttractionNames.add(chosen.name);
      return chosen;
    }

    // Realistic highway distance estimation
    double estimatedKm = 145.0;
    final pair = '$startName $destName'.toLowerCase();
    if (pair.contains('bengaluru') || pair.contains('bangalore')) {
      if (pair.contains('mumbai')) {
        estimatedKm = 985.0;
      } else if (pair.contains('delhi')) {
        estimatedKm = 2150.0;
      } else if (pair.contains('hyderabad')) {
        estimatedKm = 570.0;
      } else if (pair.contains('mangaluru') || pair.contains('mangalore')) {
        estimatedKm = 350.0;
      } else if (pair.contains('tirupati') || pair.contains('tirumala')) {
        estimatedKm = 250.0;
      } else if (pair.contains('mysore') || pair.contains('mysuru')) {
        estimatedKm = 145.0;
      } else if (pair.contains('coorg') || pair.contains('madikeri')) {
        estimatedKm = 265.0;
      } else if (pair.contains('ooty')) {
        estimatedKm = 280.0;
      } else if (pair.contains('chennai')) {
        estimatedKm = 350.0;
      } else if (pair.contains('goa')) {
        estimatedKm = 560.0;
      } else if (pair.contains('hampi')) {
        estimatedKm = 340.0;
      }
    } else if (pair.contains('mysore') || pair.contains('mysuru')) {
      if (pair.contains('mangaluru') || pair.contains('mangalore')) {
        estimatedKm = 255.0;
      } else if (pair.contains('tirupati') || pair.contains('tirumala')) {
        estimatedKm = 385.0;
      } else if (pair.contains('coorg') || pair.contains('madikeri')) {
        estimatedKm = 120.0;
      } else if (pair.contains('ooty')) {
        estimatedKm = 125.0;
      } else if (pair.contains('wayanad')) {
        estimatedKm = 140.0;
      }
    } else if (pair.contains('mumbai')) {
      if (pair.contains('pune')) estimatedKm = 150.0;
      else if (pair.contains('goa')) estimatedKm = 585.0;
      else if (pair.contains('lonavala')) estimatedKm = 85.0;
      else if (pair.contains('shirdi')) estimatedKm = 240.0;
      else if (pair.contains('mahabaleshwar')) estimatedKm = 260.0;
    }

    final totalDriveMin = (estimatedKm / 60.0 * 60).round();

    int parseMinutes(String t) => TripDateTime.parseMinutes(t);
    String formatMin(int totalMin) => TripDateTime.formatMinutes(totalMin);

    String getEmoji(String cat) {
      if (cat.contains('Temple') || cat.contains('Religious')) return '🛕';
      if (cat.contains('Waterfall') || cat.contains('River') || cat.contains('Lake')) return '🌊';
      if (cat.contains('Viewpoint') || cat.contains('Scenic')) return '🌄';
      if (cat.contains('Hill') || cat.contains('Mountain')) return '⛰️';
      if (cat.contains('Fort') || cat.contains('Palace')) return '🏰';
      if (cat.contains('Forest') || cat.contains('Nature')) return '🌳';
      if (cat.contains('Beach')) return '🏖️';
      if (cat.contains('Wildlife') || cat.contains('National Park')) return '🐘';
      if (cat.contains('Monument') || cat.contains('Landmark')) return '🗿';
      if (cat.contains('Market')) return '🛍️';
      if (cat.contains('Cultural')) return '🎨';
      if (cat.contains('Bridge') || cat.contains('Dam')) return '🌉';
      if (cat.contains('Instagrammable') || cat.contains('Photo')) return '📸';
      if (cat.contains('City')) return '🏙️';
      if (cat.contains('Historical') || cat.contains('Heritage')) return '🏛️';
      return '⭐';
    }

    ({List<String> categories, String match}) resolveCats(_FallbackAttraction t) {
      if (selectedCategories.isEmpty) {
        return (categories: t.categories, match: t.categories.isNotEmpty ? t.categories.first : 'Famous Places');
      }
      final matches = t.categories.where((c) => selectedCategories.contains(c)).toList();
      if (matches.isNotEmpty) {
        return (categories: matches, match: matches.first);
      }
      return (categories: t.categories, match: t.categories.isNotEmpty ? t.categories.first : selectedCategories.first);
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
        // --- DAY 1: OUTWARD TRAVEL & FIRST SIGHTSEEING ---
        final startMin = parseMinutes(startTime);
        int cur = startMin;

        final driveMin = totalDriveMin > 360 ? 300 : totalDriveMin;
        blocks.add(TimelineBlock(
          start: formatMin(cur),
          end: formatMin(cur + driveMin),
          type: 'travel',
          title: 'Drive from $startName to $destName',
          place: destName,
          durationMin: driveMin,
          travelMin: driveMin,
          distanceKm: estimatedKm,
          travelMode: 'drive',
          reason: 'Highway journey with optimal route pacing',
        ));
        cur += driveMin;

        // Arrival Lunch
        blocks.add(TimelineBlock(
          start: formatMin(cur),
          end: formatMin(cur + 60),
          type: 'meal',
          title: 'Arrival Lunch at ${lunchVenue.name}',
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

        // Afternoon Sightseeing 1
        final t1 = getNextAttraction('afternoon');
        final t1Dur = t1.durationMin > 90 ? 75 : (t1.durationMin > 0 ? t1.durationMin : 75);
        final res1 = resolveCats(t1);
        final emoji1 = getEmoji(res1.match);
        blocks.add(TimelineBlock(
          start: formatMin(cur),
          end: formatMin(cur + t1Dur),
          type: 'activity',
          title: 'Visit ${t1.name}',
          place: '${t1.name}, ${t1.city}',
          durationMin: t1Dur,
          reason: '$emoji1 ⭐ ${t1.rating} · ${t1.highlight}',
          categories: res1.categories,
          whyIncluded: 'Matches your selected ${res1.match} preference along the route.',
        ));
        cur += t1Dur + 15; // 15 min buffer to reach sunset spot

        // Evening Sunset Sightseeing 2
        final t2 = getNextAttraction('sunset');
        final t2Dur = t2.durationMin > 90 ? 75 : (t2.durationMin > 0 ? t2.durationMin : 75);
        final res2 = resolveCats(t2);
        final emoji2 = getEmoji(res2.match);
        blocks.add(TimelineBlock(
          start: formatMin(cur),
          end: formatMin(cur + t2Dur),
          type: 'activity',
          title: 'Explore ${t2.name}',
          place: '${t2.name}, ${t2.city}',
          durationMin: t2Dur,
          reason: '$emoji2 ⭐ ${t2.rating} · ${t2.highlight}',
          categories: res2.categories,
          whyIncluded: 'Matches your selected ${res2.match} preference along the route.',
        ));
        cur += t2Dur;

        // Dinner
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
          reason: 'Peaceful rest after sightseeing and travel',
        ));
      } else if (!isLast) {
        // --- MIDDLE DAY ---
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

        final t1 = getNextAttraction('morning');
        final t1Duration = t1.durationMin > 150 ? 120 : (t1.durationMin > 0 ? t1.durationMin : 90);
        final res1 = resolveCats(t1);
        final emoji1 = getEmoji(res1.match);
        blocks.add(TimelineBlock(
          start: '09:15 AM',
          end: formatMin(555 + t1Duration),
          type: 'activity',
          title: 'Visit ${t1.name}',
          place: '${t1.name}, ${t1.city}',
          durationMin: t1Duration,
          reason: '$emoji1 ⭐ ${t1.rating} · ${t1.highlight}',
          categories: res1.categories,
          whyIncluded: 'Matches your selected ${res1.match} preference along the route.',
        ));

        // Lunch at 12:45 PM
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

        final t2 = getNextAttraction('afternoon');
        final t2Duration = t2.durationMin > 120 ? 105 : (t2.durationMin > 0 ? t2.durationMin : 90);
        final res2 = resolveCats(t2);
        final emoji2 = getEmoji(res2.match);
        blocks.add(TimelineBlock(
          start: '02:00 PM',
          end: formatMin(840 + t2Duration),
          type: 'activity',
          title: 'Explore ${t2.name}',
          place: '${t2.name}, ${t2.city}',
          durationMin: t2Duration,
          reason: '$emoji2 ⭐ ${t2.rating} · ${t2.highlight}',
          categories: res2.categories,
          whyIncluded: 'Matches your selected ${res2.match} preference along the route.',
        ));

        // Sunset Spot
        final t3 = getNextAttraction('sunset');
        final res3 = resolveCats(t3);
        final emoji3 = getEmoji(res3.match);
        blocks.add(TimelineBlock(
          start: '04:30 PM',
          end: '06:00 PM',
          type: 'activity',
          title: 'Sunset at ${t3.name}',
          place: '${t3.name}, ${t3.city}',
          durationMin: 90,
          reason: '$emoji3 ⭐ ${t3.rating} · ${t3.highlight}',
          categories: res3.categories,
          whyIncluded: 'Matches your selected ${res3.match} preference along the route.',
        ));

        // Evening Tea
        blocks.add(TimelineBlock(
          start: '06:15 PM',
          end: '07:00 PM',
          type: 'coffee',
          title: 'Evening Sunset & Refreshment Break',
          place: 'Scenic Viewpoint / Promenade',
          durationMin: 45,
          breakType: 'coffee',
          reason: 'Golden hour vistas, scenic photography & tea',
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
        // --- FINAL DAY ---
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

        final t1 = getNextAttraction('morning');
        final t1Duration = t1.durationMin > 90 ? 75 : (t1.durationMin > 0 ? t1.durationMin : 75);
        final res1 = resolveCats(t1);
        final emoji1 = getEmoji(res1.match);
        blocks.add(TimelineBlock(
          start: '09:15 AM',
          end: '10:30 AM',
          type: 'activity',
          title: 'Explore ${t1.name}',
          place: '${t1.name}, ${t1.city}',
          durationMin: t1Duration,
          reason: '$emoji1 ⭐ ${t1.rating} · ${t1.highlight}',
          categories: res1.categories,
          whyIncluded: 'Matches your selected ${res1.match} preference along the route.',
        ));

        final t2 = getNextAttraction('afternoon');
        final t2Duration = t2.durationMin > 90 ? 75 : (t2.durationMin > 0 ? t2.durationMin : 75);
        final res2 = resolveCats(t2);
        final emoji2 = getEmoji(res2.match);
        blocks.add(TimelineBlock(
          start: '10:45 AM',
          end: '12:00 PM',
          type: 'activity',
          title: 'Visit ${t2.name}',
          place: '${t2.name}, ${t2.city}',
          durationMin: t2Duration,
          reason: '$emoji2 ⭐ ${t2.rating} · ${t2.highlight}',
          categories: res2.categories,
          whyIncluded: 'Matches your selected ${res2.match} preference along the route.',
        ));

        // Lunch
        blocks.add(TimelineBlock(
          start: '12:30 PM',
          end: '01:30 PM',
          type: 'meal',
          title: 'Departure Lunch at ${lunchVenue.name}',
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
          reason: 'Settle bills and prepare for return journey',
        ));

        // Return Drive
        final retDriveMin = totalDriveMin > 360 ? 300 : totalDriveMin;
        blocks.add(TimelineBlock(
          start: '02:00 PM',
          end: formatMin(840 + retDriveMin),
          type: 'return',
          title: 'Return Drive back to $startName',
          place: startName,
          durationMin: retDriveMin,
          travelMin: retDriveMin,
          distanceKm: estimatedKm,
          travelMode: 'drive',
          reason: 'Safe return journey completing the round trip circuit',
        ));
      }

      daysList.add(SmartDay(
        day: d,
        date: 'Day $d',
        title: isFirst ? 'Arrival & Highlights of $destName' : (isLast ? 'Farewell $destName & Return' : 'Full Exploration of $destName'),
        blocks: blocks,
      ));
    }

    final eff = (fuelEfficiency != null && fuelEfficiency > 0) ? fuelEfficiency : 15.0;
    final totalKm = (estimatedKm * 2) * (total > 1 ? 1.2 : 1.0);
    final fuelEst = FuelPriceService.instance.calculateRouteFuel(
      distanceKm: totalKm,
      mileage: eff,
      fuelType: 'petrol',
      originLocation: startName,
      destLocation: destName,
    );
    final fuelCost = fuelEst.totalFuelCost.round();
    
    // Realistic highway toll estimation based on actual corridor distance & expressway routes
    int tollCost = 0;
    if (estimatedKm > 50.0) {
      // Highway trip: estimate realistic toll based on corridor
      final pair = '$startName $destName'.toLowerCase();
      if ((pair.contains('bengaluru') || pair.contains('bangalore')) && (pair.contains('mysore') || pair.contains('mysuru'))) {
        tollCost = 320 * 2; // Bengaluru-Mysuru Expressway round-trip (Kaniminike + Gananguru)
      } else if ((pair.contains('bengaluru') || pair.contains('bangalore')) && pair.contains('chennai')) {
        tollCost = 490 * 2; // Bengaluru-Chennai NH-48 round-trip
      } else if (pair.contains('mumbai') && pair.contains('pune')) {
        tollCost = 320 * 2; // Mumbai-Pune Expressway round-trip
      } else if (pair.contains('delhi') && (pair.contains('agra') || pair.contains('lucknow'))) {
        tollCost = pair.contains('lucknow') ? (530 + 655) * 2 : 530 * 2;
      } else {
        // Average NHAI 4-lane toll rate per km: ~₹1.10/km for cars on tollable highway sections
        tollCost = ((estimatedKm * 2) * 1.10).round();
      }
    }
    final foodCost = total * 750 * travellers;
    final stayCost = (total > 1 ? (total - 1) : 0) * 2200 * ((travellers / 2).ceil());
    const int bufferCost = 1000;
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

class _FallbackAttraction {
  final String name;
  final String city;
  final String rating;
  final int durationMin;
  final String highlight;
  final List<String> categories;

  const _FallbackAttraction({
    required this.name,
    required this.city,
    this.rating = '4.8',
    this.durationMin = 90,
    required this.highlight,
    required this.categories,
  });
}
