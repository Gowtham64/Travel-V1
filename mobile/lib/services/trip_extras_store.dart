import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/trip_extras.dart';

/// Persists the trip workspace add-ons (packing / expenses / reservations / day plans)
/// locally via shared_preferences AND syncs to Supabase Cloud when authenticated.
class TripExtrasStore {
  final String tripKey;
  TripExtrasStore(this.tripKey);

  String get _packingKey => 'trip_$tripKey.packing';
  String get _expensesKey => 'trip_$tripKey.expenses';
  String get _reservationsKey => 'trip_$tripKey.reservations';
  String get _journalKey => 'trip_$tripKey.journal';
  String get _daysKey => 'trip_$tripKey.days';
  String get _startedKey => 'trip_$tripKey.startedAt';

  /// When the traveller pressed "Start Trip" (active-trip mode), or null.
  Future<DateTime?> loadStartedAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_startedKey);
      return (raw == null || raw.isEmpty) ? null : DateTime.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveStartedAt(DateTime? when) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (when == null) {
        await prefs.remove(_startedKey);
      } else {
        await prefs.setString(_startedKey, when.toIso8601String());
      }
    } catch (_) {/* best-effort */}
  }

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

  String get _galleryKey => 'trip_$tripKey.gallery';
  Future<List<GalleryPhoto>> loadGallery() => _load(_galleryKey, GalleryPhoto.fromJson);
  Future<bool> saveGallery(List<GalleryPhoto> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_galleryKey, jsonEncode(items.map((e) => e.toJson()).toList()));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<PlanDay>> loadDays() async {
    final local = await _load(_daysKey, PlanDay.fromJson);
    if (local.isNotEmpty) return local;

    // Fallback: fetch from Supabase if authenticated
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final rows = await Supabase.instance.client
            .from('trips')
            .select('*')
            .eq('user_id', user.id)
            .order('created_at', ascending: false);
        if (rows is List) {
          for (final r in rows) {
            final endPt = (r['end_point'] as Map?) ?? {};
            final savedKey = endPt['tripKey']?.toString() ?? '';
            final it = endPt['itinerary'];
            final nameStr = (r['name']?.toString() ?? '').toLowerCase();
            if ((savedKey == tripKey || nameStr.contains(tripKey.replaceAll('smart_', ''))) && it is List && it.isNotEmpty) {
              final days = it.map((d) => PlanDay.fromJson((d as Map).cast<String, dynamic>())).toList();
              if (days.isNotEmpty) {
                await saveDays(days, name: r['name']?.toString() ?? 'Synced Plan');
                return days;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Cloud loadDays note: $e');
    }
    return [];
  }

  /// Save the day-by-day plan. When [name] is given and the plan is non-empty,
  /// the plan is recorded in the global index and synced to Supabase.
  Future<void> saveDays(List<PlanDay> items, {String name = ''}) async {
    await _save(_daysKey, items.map((e) => e.toJson()).toList());
    if (name.isNotEmpty) {
      if (items.isNotEmpty) {
        await _registerInIndex(name: name, days: items.length);
      } else {
        await removeFromIndex(tripKey);
      }
    }

    // Two-way Supabase Cloud Sync
    if (items.isNotEmpty) {
      try {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          final planName = name.isNotEmpty ? name : 'My Trip Plan';
          final firstPlace = items.expand((d) => d.items).firstOrNull?.text ?? 'Start';
          final lastPlace = items.expand((d) => d.items).lastOrNull?.text ?? 'Destination';
          
          await Supabase.instance.client.from('trips').upsert({
            'user_id': user.id,
            'name': planName,
            'start_point': {'name': firstPlace, 'lat': 12.9716, 'lng': 77.5946},
            'end_point': {
              'name': lastPlace,
              'lat': 12.2958,
              'lng': 76.6394,
              'tripKey': tripKey,
              'itinerary': items.map((e) => e.toJson()).toList(),
            },
            'vehicle_type': 'car',
          }, onConflict: 'user_id, name');
        }
      } catch (e) {
        debugPrint('Cloud saveDays note: $e');
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

  /// All saved day-plans (locally and from Supabase cloud), newest first.
  static Future<List<Map<String, dynamic>>> savedPlans() async {
    List<Map<String, dynamic>> list = [];
    try {
      final prefs = await SharedPreferences.getInstance();
      list = await _readIndex(prefs);
    } catch (_) {}

    // Merge cloud day-plans from Supabase
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final rows = await Supabase.instance.client
            .from('trips')
            .select('*')
            .eq('user_id', user.id)
            .order('created_at', ascending: false);

        if (rows is List && rows.isNotEmpty) {
          final seenKeys = list.map((e) => (e['key'] ?? '').toString()).toSet();
          for (final r in rows) {
            final endPt = (r['end_point'] as Map?) ?? {};
            final it = endPt['itinerary'];
            if (it is List && it.isNotEmpty) {
              final tripKey = endPt['tripKey']?.toString() ?? 'smart_${(r['name'] ?? 'trip').toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
              if (!seenKeys.contains(tripKey)) {
                list.add({
                  'key': tripKey,
                  'name': r['name'] ?? 'Saved Plan',
                  'days': it.length,
                  'ts': DateTime.tryParse(r['created_at']?.toString() ?? '')?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch,
                });
                seenKeys.add(tripKey);
              }
            }
          }
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_indexKey, jsonEncode(list));
        }
      }
    } catch (e) {
      debugPrint('Cloud savedPlans sync note: $e');
    }

    list.sort((a, b) => ((b['ts'] as num?) ?? 0).compareTo((a['ts'] as num?) ?? 0));
    return list;
  }

  /// Remove a plan from the index (and its stored days).
  static Future<void> removeFromIndex(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = await _readIndex(prefs);
      list.removeWhere((e) => e['key'] == key);
      await prefs.setString(_indexKey, jsonEncode(list));
      await prefs.remove('trip_$key.days');

      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await Supabase.instance.client.from('trips').delete().eq('user_id', user.id).ilike('name', '%$key%');
      }
    } catch (_) {}
  }
}
