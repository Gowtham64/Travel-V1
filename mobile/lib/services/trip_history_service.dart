import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TripHistoryItem {
  final String id;
  final String title;
  final String startAddress;
  final String endAddress;
  final List<String> waypoints;
  final double distanceKm;
  final int durationMinutes;
  final String vehicleType;
  final double fuelCost;
  final double tollCost;
  final double totalCost;
  final DateTime completedAt;
  final bool isRoundTrip;
  final List<Map<String, double>> routeCoordinates;
  final int totalStopsCount;
  final List<Map<String, dynamic>> tollPlazas;
  final List<Map<String, dynamic>> places;
  final double avgSpeedKmh;

  TripHistoryItem({
    required this.id,
    required this.title,
    required this.startAddress,
    required this.endAddress,
    this.waypoints = const [],
    required this.distanceKm,
    required this.durationMinutes,
    required this.vehicleType,
    required this.fuelCost,
    required this.tollCost,
    required this.totalCost,
    required this.completedAt,
    required this.isRoundTrip,
    this.routeCoordinates = const [],
    this.totalStopsCount = 0,
    this.tollPlazas = const [],
    this.places = const [],
    this.avgSpeedKmh = 60.0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'startAddress': startAddress,
        'endAddress': endAddress,
        'waypoints': waypoints,
        'distanceKm': distanceKm,
        'durationMinutes': durationMinutes,
        'vehicleType': vehicleType,
        'fuelCost': fuelCost,
        'tollCost': tollCost,
        'totalCost': totalCost,
        'completedAt': completedAt.toIso8601String(),
        'isRoundTrip': isRoundTrip,
        'routeCoordinates': routeCoordinates,
        'totalStopsCount': totalStopsCount,
        'tollPlazas': tollPlazas,
        'places': places,
        'avgSpeedKmh': avgSpeedKmh,
      };

  factory TripHistoryItem.fromJson(Map<String, dynamic> json) {
    return TripHistoryItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Trip',
      startAddress: json['startAddress'] as String? ?? '',
      endAddress: json['endAddress'] as String? ?? '',
      waypoints: (json['waypoints'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0.0,
      durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
      vehicleType: json['vehicleType'] as String? ?? 'car',
      fuelCost: (json['fuelCost'] as num?)?.toDouble() ?? 0.0,
      tollCost: (json['tollCost'] as num?)?.toDouble() ?? 0.0,
      totalCost: (json['totalCost'] as num?)?.toDouble() ?? 0.0,
      completedAt: DateTime.tryParse(json['completedAt'] as String? ?? '') ??
          DateTime.now(),
      isRoundTrip: json['isRoundTrip'] as bool? ?? false,
      routeCoordinates: (json['routeCoordinates'] as List<dynamic>?)
              ?.map((e) => (e as Map<String, dynamic>)
                  .map((k, v) => MapEntry(k, (v as num).toDouble())))
              .toList() ??
          [],
      totalStopsCount: (json['totalStopsCount'] as num?)?.toInt() ?? 0,
      tollPlazas:
          (json['tollPlazas'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
              [],
      places:
          (json['places'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [],
      avgSpeedKmh: (json['avgSpeedKmh'] as num?)?.toDouble() ?? 60.0,
    );
  }

  factory TripHistoryItem.fromSupabaseTrip(Map<String, dynamic> row) {
    final startPt = (row['start_point'] as Map?) ?? {};
    final endPt = (row['end_point'] as Map?) ?? {};
    final stops = (row['trip_stops'] as List?) ?? [];
    final name = (row['name'] as String?) ?? 'Saved Trip';
    final createdAt = DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now();
    
    final startName = startPt['name']?.toString() ?? name.split(' to ').first.trim();
    final endName = endPt['name']?.toString() ?? (name.contains(' to ') ? name.split(' to ').last.trim() : name);
    final isRound = name.toLowerCase().contains('round') || startName.toLowerCase() == endName.toLowerCase();

    final wpNames = stops.map((s) => (s['name'] ?? 'Waypoint').toString()).toList();

    return TripHistoryItem(
      id: row['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: name,
      startAddress: startName,
      endAddress: endName,
      waypoints: wpNames,
      distanceKm: (endPt['distanceKm'] as num?)?.toDouble() ?? 145.0,
      durationMinutes: (endPt['durationMinutes'] as num?)?.toInt() ?? 150,
      vehicleType: row['vehicle_type']?.toString() ?? 'car',
      fuelCost: (endPt['fuelCost'] as num?)?.toDouble() ?? 0.0,
      tollCost: (endPt['tollCost'] as num?)?.toDouble() ?? 0.0,
      totalCost: (endPt['totalCost'] as num?)?.toDouble() ?? 0.0,
      completedAt: createdAt,
      isRoundTrip: isRound,
      totalStopsCount: stops.length,
    );
  }
}

class TripHistoryService {
  TripHistoryService._();
  static final TripHistoryService instance = TripHistoryService._();

  static const String _storageKey = 'voyplan_trip_history_v1';

  final ValueNotifier<List<TripHistoryItem>> historyNotifier =
      ValueNotifier([]);

  Future<void> init() async {
    await getHistory();
  }

  Future<List<TripHistoryItem>> getHistory() async {
    List<TripHistoryItem> items = [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        items = list
            .map((e) =>
                TripHistoryItem.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      }
    } catch (e) {
      debugPrint('Error loading local trip history: $e');
    }

    // Two-way cloud sync with Supabase: PULL cloud trips AND PUSH local-only
    // trips up, so a trip saved on any device appears on every device.
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final localItems = List<TripHistoryItem>.from(items);

        // PULL: no user_id filter — RLS returns every trip owned by this account
        // (matched by user_id OR the account's verified email), so trips saved
        // from another device/sign-in method (Google / email / phone) sync in.
        final cloudRows = await Supabase.instance.client
            .from('trips')
            .select('*, trip_stops(*)')
            .order('created_at', ascending: false);

        final cloudItems = (cloudRows is List)
            ? cloudRows
                .map((r) => TripHistoryItem.fromSupabaseTrip((r as Map).cast<String, dynamic>()))
                .toList()
            : <TripHistoryItem>[];

        // Normalised trip name, used to detect which local trips are missing
        // from the cloud (cloud rows are keyed by their `name`).
        String nameKey(TripHistoryItem t) =>
            (t.title.isNotEmpty ? t.title : '${t.startAddress} to ${t.endAddress}')
                .trim()
                .toLowerCase();
        final cloudNames = cloudItems.map(nameKey).toSet();

        // PUSH: upload any local-only trip so it propagates to other devices.
        // Previously sync was pull-only, so a trip whose original cloud write
        // silently failed (or was made before sign-in) stayed on one device.
        for (final li in localItems) {
          final key = nameKey(li);
          if (key.isEmpty || key == 'to') continue;
          if (!cloudNames.contains(key)) {
            try {
              await _pushTripToCloud(li, user);
              cloudNames.add(key);
            } catch (e) {
              debugPrint('Trip push-sync note: $e');
            }
          }
        }

        // MERGE cloud items into the display list.
        final seenKeys = <String>{};
        for (final it in items) {
          seenKeys.add('${it.startAddress}__${it.endAddress}__${it.completedAt.day}');
        }
        for (final cit in cloudItems) {
          final key = '${cit.startAddress}__${cit.endAddress}__${cit.completedAt.day}';
          if (!seenKeys.contains(key)) {
            items.add(cit);
            seenKeys.add(key);
          }
        }

        // Persist merged cache locally.
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            _storageKey, jsonEncode(items.map((e) => e.toJson()).toList()));
      }
    } catch (e) {
      debugPrint('Supabase cloud history sync note: $e');
    }

    items.sort((a, b) => b.completedAt.compareTo(a.completedAt));
    historyNotifier.value = items;
    return items;
  }

  Future<void> saveTrip(TripHistoryItem item) async {
    try {
      final current = await getHistory();
      // Remove recent duplicate if saved within last 15s for exact route
      current.removeWhere((existing) =>
          existing.id == item.id ||
          (existing.startAddress == item.startAddress &&
              existing.endAddress == item.endAddress &&
              item.completedAt
                      .difference(existing.completedAt)
                      .inSeconds
                      .abs() <
                  15));
      current.insert(0, item);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _storageKey, jsonEncode(current.map((e) => e.toJson()).toList()));
      historyNotifier.value = List.from(current);

      // Cloud persistence if signed in
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await _pushTripToCloud(item, user);
      }
    } catch (e) {
      debugPrint('Error saving trip history: $e');
    }
  }

  /// Inserts one trip (and its waypoints) into Supabase. Shared by [saveTrip]
  /// and the push-sync in [getHistory]. Stamps owner_email so the trip is
  /// visible from the user's other sign-in identities that share the email.
  Future<void> _pushTripToCloud(TripHistoryItem item, User user) async {
    final startCoord = item.routeCoordinates.isNotEmpty
        ? item.routeCoordinates.first
        : {'lat': 12.9716, 'lng': 77.5946};
    final endCoord = item.routeCoordinates.isNotEmpty
        ? item.routeCoordinates.last
        : {'lat': 13.6288, 'lng': 79.4192};

    final inserted = await Supabase.instance.client.from('trips').insert({
      'user_id': user.id,
      if (user.email != null) 'owner_email': user.email!.toLowerCase(),
      'name': item.title.isNotEmpty
          ? item.title
          : '${item.startAddress} to ${item.endAddress}',
      'start_point': {'lat': startCoord['lat'], 'lng': startCoord['lng'], 'name': item.startAddress},
      'end_point': {
        'lat': endCoord['lat'],
        'lng': endCoord['lng'],
        'name': item.endAddress,
        'distanceKm': item.distanceKm,
        'durationMinutes': item.durationMinutes,
        'fuelCost': item.fuelCost,
        'tollCost': item.tollCost,
        'totalCost': item.totalCost,
        'isRoundTrip': item.isRoundTrip,
      },
      'vehicle_type': item.vehicleType,
    }).select().single();

    if (item.waypoints.isNotEmpty && inserted['id'] != null) {
      final stops = item.waypoints.asMap().entries.map((e) => {
            'trip_id': inserted['id'],
            'type': 'waypoint',
            'lat': 0.0,
            'lng': 0.0,
            'name': e.value,
            'order_index': e.key,
          }).toList();
      await Supabase.instance.client.from('trip_stops').insert(stops);
    }
  }

  Future<void> deleteTrip(String id) async {
    try {
      final current = await getHistory();
      current.removeWhere((e) => e.id == id);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _storageKey, jsonEncode(current.map((e) => e.toJson()).toList()));
      historyNotifier.value = List.from(current);

      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await Supabase.instance.client.from('trips').delete().eq('id', id);
      }
    } catch (e) {
      debugPrint('Error deleting trip: $e');
    }
  }

  Future<void> clearHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
      historyNotifier.value = [];
    } catch (e) {
      debugPrint('Error clearing trip history: $e');
    }
  }
}
