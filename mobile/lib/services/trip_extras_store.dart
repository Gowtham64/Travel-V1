import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/trip_extras.dart';

/// Persists the trip workspace add-ons (packing / expenses / reservations)
/// locally via shared_preferences, scoped to a per-trip [tripKey]. Local storage
/// keeps the feature working offline and for guests, with no backend schema
/// changes. Each list is stored as a JSON string under a namespaced key.
class TripExtrasStore {
  final String tripKey;
  TripExtrasStore(this.tripKey);

  String get _packingKey => 'trip_$tripKey.packing';
  String get _expensesKey => 'trip_$tripKey.expenses';
  String get _reservationsKey => 'trip_$tripKey.reservations';

  Future<List<T>> _load<T>(String key, T Function(Map<String, dynamic>) fromJson) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list.map((e) => fromJson((e as Map).cast<String, dynamic>())).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(String key, List<Map<String, dynamic>> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(items));
    } catch (_) {
      // best-effort; a failed write just means the change isn't persisted
    }
  }

  Future<List<PackingItem>> loadPacking() => _load(_packingKey, PackingItem.fromJson);
  Future<void> savePacking(List<PackingItem> items) =>
      _save(_packingKey, items.map((e) => e.toJson()).toList());

  Future<List<Expense>> loadExpenses() => _load(_expensesKey, Expense.fromJson);
  Future<void> saveExpenses(List<Expense> items) =>
      _save(_expensesKey, items.map((e) => e.toJson()).toList());

  Future<List<Reservation>> loadReservations() =>
      _load(_reservationsKey, Reservation.fromJson);
  Future<void> saveReservations(List<Reservation> items) =>
      _save(_reservationsKey, items.map((e) => e.toJson()).toList());
}
