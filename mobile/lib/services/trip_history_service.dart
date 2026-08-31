import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    required this.waypoints,
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
      id: json['id'] as String? ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      title: json['title'] as String? ??
          '${json['startAddress']} → ${json['endAddress']}',
      startAddress: json['startAddress'] as String? ?? 'Origin',
      endAddress: json['endAddress'] as String? ?? 'Destination',
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
      completedAt:
          DateTime.tryParse(json['completedAt'] as String? ?? '') ?? DateTime.now(),
      isRoundTrip: json['isRoundTrip'] as bool? ?? false,
      routeCoordinates: (json['routeCoordinates'] as List<dynamic>?)
              ?.map((e) => {
                    'lat': (e['lat'] as num).toDouble(),
                    'lng': (e['lng'] as num).toDouble(),
                  })
              .toList() ??
          [],
      totalStopsCount: (json['totalStopsCount'] as num?)?.toInt() ?? 0,
      tollPlazas: (json['tollPlazas'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          [],
      places:
          (json['places'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [],
      avgSpeedKmh: (json['avgSpeedKmh'] as num?)?.toDouble() ?? 60.0,
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
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) {
        historyNotifier.value = [];
        return [];
      }
      final list = jsonDecode(raw) as List;
      final items = list
          .map((e) =>
              TripHistoryItem.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      items.sort((a, b) => b.completedAt.compareTo(a.completedAt));
      historyNotifier.value = items;
      return items;
    } catch (e) {
      debugPrint('Error loading trip history: $e');
      return [];
    }
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
    } catch (e) {
      debugPrint('Error saving trip history: $e');
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
