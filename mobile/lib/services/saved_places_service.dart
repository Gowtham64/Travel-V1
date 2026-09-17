import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/saved_place_model.dart';
import 'api_service.dart';

class SavedPlacesService extends ChangeNotifier {
  static final SavedPlacesService _instance = SavedPlacesService._internal();
  factory SavedPlacesService() => _instance;
  SavedPlacesService._internal();

  static const String _storageKey = 'voyplan_saved_individual_places_v1';
  final _api = ApiService();
  List<SavedPlace> _places = [];
  bool _initialized = false;

  List<SavedPlace> get places => List.unmodifiable(_places);

  Future<void> init() async {
    if (_initialized) return;
    await _loadFromLocal();
    _initialized = true;
    _syncWithCloud();
  }

  Future<void> _loadFromLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> list = jsonDecode(raw);
        _places = list.map((item) => SavedPlace.fromJson(Map<String, dynamic>.from(item))).toList();
      } else {
        // Seed default high-quality popular travel locations on first launch
        _places = _getSeedPlaces();
        await _saveToLocal();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[SavedPlacesService] Error loading local places: $e');
      if (_places.isEmpty) {
        _places = _getSeedPlaces();
      }
    }
  }

  Future<void> _saveToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_places.map((p) => p.toJson()).toList());
      await prefs.setString(_storageKey, raw);
      notifyListeners();
    } catch (e) {
      debugPrint('[SavedPlacesService] Error saving to local: $e');
    }
  }

  Future<void> _syncWithCloud() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;

    try {
      final data = await _api.accountList('favorites');
      if (data.isNotEmpty) {
        final cloudPlaces = data.map((fav) {
          final lat = (fav['lat'] as num?)?.toDouble() ?? 12.9716;
          final lng = (fav['lng'] as num?)?.toDouble() ?? 77.5946;
          return SavedPlace(
            id: fav['id']?.toString() ?? fav['ref_id']?.toString() ?? fav['name'].toString(),
            name: fav['name']?.toString() ?? 'Saved Place',
            category: (fav['type']?.toString() ?? 'Attraction').toUpperCase(),
            location: fav['note']?.toString() ?? '',
            lat: lat,
            lng: lng,
            rating: 4.6,
            image: fav['image_url']?.toString(),
            description: fav['note']?.toString(),
            savedAt: fav['created_at'] != null ? (DateTime.tryParse(fav['created_at'].toString()) ?? DateTime.now()) : DateTime.now(),
          );
        }).toList();

        final seenIds = _places.map((p) => p.name.toLowerCase()).toSet();
        for (final cp in cloudPlaces) {
          if (!seenIds.contains(cp.name.toLowerCase())) {
            _places.add(cp);
          }
        }
        await _saveToLocal();
      }
    } catch (e) {
      debugPrint('[SavedPlacesService] Cloud sync skipped: $e');
    }
  }

  Future<void> savePlace(SavedPlace place) async {
    final existingIdx = _places.indexWhere((p) =>
        p.id == place.id ||
        (p.name.trim().toLowerCase() == place.name.trim().toLowerCase() &&
            (p.lat - place.lat).abs() < 0.01 &&
            (p.lng - place.lng).abs() < 0.01));

    if (existingIdx >= 0) {
      _places[existingIdx] = place;
    } else {
      _places.insert(0, place);
    }
    await _saveToLocal();

    // Sync to backend if session exists
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      try {
        await _api.accountCreate('favorites', {
          'type': place.category.toLowerCase(),
          'name': place.name,
          'lat': place.lat,
          'lng': place.lng,
          'note': place.description ?? place.location,
          'image_url': place.image,
        });
      } catch (_) {}
    }
  }

  Future<void> removePlace(String id) async {
    _places.removeWhere((p) => p.id == id);
    await _saveToLocal();

    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      try {
        await _api.accountDelete('favorites', id);
      } catch (_) {}
    }
  }

  bool isPlaceSaved(String name) {
    final q = name.trim().toLowerCase();
    return _places.any((p) => p.name.trim().toLowerCase() == q);
  }

  List<SavedPlace> _getSeedPlaces() {
    return [
      SavedPlace(
        id: 'seed_abbey_falls',
        name: 'Abbey Falls',
        category: 'Waterfall',
        location: 'Madikeri, Coorg, Karnataka',
        lat: 12.4514,
        lng: 75.7176,
        rating: 4.6,
        image: 'https://images.unsplash.com/photo-1546587348-d12660c30c50?q=80&w=800&auto=format&fit=crop',
        description: 'Roaring cascade surrounded by lush Western Ghats spice estates and coffee plantations.',
        savedAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
      SavedPlace(
        id: 'seed_mysore_palace',
        name: 'Mysore Palace',
        category: 'Temple & Heritage',
        location: 'Sayyaji Rao Rd, Mysuru, Karnataka',
        lat: 12.3052,
        lng: 76.6552,
        rating: 4.8,
        image: 'https://images.unsplash.com/photo-1590766940554-634a7ed41450?q=80&w=800&auto=format&fit=crop',
        description: 'Spectacular Indo-Saracenic royal palace with illuminated arches and gold ceilings.',
        savedAt: DateTime.now().subtract(const Duration(days: 5)),
      ),
      SavedPlace(
        id: 'seed_chamundi_viewpoint',
        name: 'Chamundi Hills Viewpoint',
        category: 'Viewpoint',
        location: 'Chamundi Hill Rd, Mysuru',
        lat: 12.2748,
        lng: 76.6710,
        rating: 4.7,
        image: 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?q=80&w=800&auto=format&fit=crop',
        description: 'Panoramic sunrise vista overlooking the heritage city and palace grounds.',
        savedAt: DateTime.now().subtract(const Duration(days: 7)),
      ),
      SavedPlace(
        id: 'seed_mtr_cafe',
        name: 'Mavalli Tiffin Room (MTR)',
        category: 'Restaurant',
        location: 'Lalbagh Fort Rd, Bangalore',
        lat: 12.9554,
        lng: 77.5855,
        rating: 4.7,
        image: 'https://images.unsplash.com/photo-1626777552726-4a6b54c97e46?q=80&w=800&auto=format&fit=crop',
        description: 'Legendary 1924 heritage restaurant famous for rava idli and filter coffee.',
        savedAt: DateTime.now().subtract(const Duration(days: 10)),
      ),
      SavedPlace(
        id: 'seed_raja_seat',
        name: 'Raja\'s Seat Sunset Point',
        category: 'Viewpoint',
        location: 'Madikeri, Karnataka',
        lat: 12.4216,
        lng: 75.7335,
        rating: 4.5,
        image: 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?q=80&w=800&auto=format&fit=crop',
        description: 'Historic garden pavilion with dramatic sunsets over the Coorg mountain valleys.',
        savedAt: DateTime.now().subtract(const Duration(days: 12)),
      ),
    ];
  }
}
