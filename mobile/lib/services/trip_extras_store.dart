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
  String get _journalKey => 'trip_$tripKey.journal';
  String get _daysKey => 'trip_$tripKey.days';

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

  Future<List<JournalEntry>> loadJournal() => _load(_journalKey, JournalEntry.fromJson);
  Future<void> saveJournal(List<JournalEntry> items) =>
      _save(_journalKey, items.map((e) => e.toJson()).toList());

  Future<List<PlanDay>> loadDays() => _load(_daysKey, PlanDay.fromJson);

  /// Save the day-by-day plan. When [name] is given and the plan is non-empty,
  /// the plan is also recorded in a global index so it appears in "Saved trips".
  Future<void> saveDays(List<PlanDay> items, {String name = ''}) async {
    await _save(_daysKey, items.map((e) => e.toJson()).toList());
    if (name.isNotEmpty) {
      if (items.isNotEmpty) {
        await _registerInIndex(name: name, days: items.length);
      } else {
        await removeFromIndex(tripKey);
      }
    }
  }

  // ── Global index of saved day-plans (so they can be listed) ────────────────
  static const String _indexKey = 'voy_plan_index';

  static Future<List<Map<String, dynamic>>> _readIndex(SharedPreferences prefs) async {
    final raw = prefs.getString(_indexKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => (e as Map).cast<String, dynamic>()).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _registerInIndex({required String name, required int days}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = await _readIndex(prefs);
      list.removeWhere((e) => e['key'] == tripKey);
      list.insert(0, {
        'key': tripKey,
        'name': name,
        'days': days,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
      await prefs.setString(_indexKey, jsonEncode(list));
    } catch (_) {}
  }

  /// All locally-saved day-plans, newest first: {key, name, days, ts}.
  static Future<List<Map<String, dynamic>>> savedPlans() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = await _readIndex(prefs);
      list.sort((a, b) => ((b['ts'] as num?) ?? 0).compareTo((a['ts'] as num?) ?? 0));
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Remove a plan from the index (and its stored days).
  static Future<void> removeFromIndex(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = await _readIndex(prefs);
      list.removeWhere((e) => e['key'] == key);
      await prefs.setString(_indexKey, jsonEncode(list));
      await prefs.remove('trip_$key.days');
    } catch (_) {}
  }
}
