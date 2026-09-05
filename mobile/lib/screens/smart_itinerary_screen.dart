import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/trip_models.dart';
import '../models/trip_extras.dart';
import '../models/vehicles_data.dart';
import '../services/api_service.dart';
import '../services/trip_extras_store.dart';
import '../services/trip_history_service.dart';
import '../services/auth_guard.dart';
import '../widgets/app_design.dart';
import '../data/temple_database.dart';
import '../services/trip_reminder_service.dart';
import '../utils/trip_date_time.dart';
import 'day_planner_screen.dart';
import 'trip_screen.dart';

/// AI-powered smart trip planner: pick a start date/time + destination and the
/// AI builds a realistic, time-blocked day-by-day itinerary with automatic
/// meal/rest breaks, travel time and per-block reasoning — then lets you nudge it
/// (regenerate, optimise, more sightseeing, less travel, pace mode…).
class SmartItineraryScreen extends StatefulWidget {
  const SmartItineraryScreen({super.key});

  @override
  State<SmartItineraryScreen> createState() => _SmartItineraryScreenState();
}

class _SmartItineraryScreenState extends State<SmartItineraryScreen> {
  static const String _bgUrl =
      'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?q=80&w=2000&auto=format&fit=crop';

  final _api = ApiService();
  final _destCtrl = TextEditingController();
  final _startLocCtrl = TextEditingController();
  final _placesCtrl = TextEditingController();
  final _prefsCtrl = TextEditingController();
  final _customPrefCtrl = TextEditingController();
  final _currentFuelCtrl = TextEditingController(text: '30');
  final _mileageCtrl = TextEditingController(text: '15');

  static const String _tripType = 'around'; // Smart AI Planner supports Around Trip only
  int _searchRadiusKm = 25;
  int? _nextSearchRadiusKm;
  int? _placesFoundCount;
  bool _canExpandSearch = false;
  bool _isConfirmed = false;
  bool _navLoading = false;
  double? _totalRouteKm;
  RouteInfo? _currentRoute;
  NavigationRoute? _navigationRoute;
  int _routeVersion = 1;
  bool _isCalculatingRoute = false;
  String? _routeStatusMessage;
  Timer? _statusMessageTimer;

  DateTime? _startDate;
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 0);
  DateTime? _endDate;
  TimeOfDay? _endTime;
  int _days = 2;
  int _travellers = 2;
  String _mode = 'balanced';
  String _transportMode = 'car'; // 'car' or 'bike' — drives the vehicle list + fuel calc
  VehicleModel? _vehicle;

  // Selected Place Categories & Priorities
  final Set<String> _selectedCategoryIds = {
    'temples',
    'historical_heritage',
    'viewpoints',
    'hills_mountains',
    'famous_places',
  };
  final Map<String, String> _categoryPriorities = {
    'temples': 'must_visit',
    'historical_heritage': 'must_visit',
    'viewpoints': 'would_like',
    'hills_mountains': 'would_like',
    'famous_places': 'must_visit',
  };
  bool _showInsufficientPlacesWarning = false;

  // Destination / start-location autocomplete (via the backend proxy).
  Timer? _acDebounce;
  List<Map<String, dynamic>> _destSuggestions = [];
  List<Map<String, dynamic>> _startSuggestions = [];

  bool _loading = false;
  String? _error;
  List<SmartDay> _itinerary = [];
  TripBudget? _budget;
  int _splitCount = 2; // how many ways to split the budget

  // Starting-point quick picks: device GPS + a saved "home" address.
  static const String _homePrefsKey = 'voy_home_location';
  bool _locating = false;
  String? _homeLocation;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) setState(() => _homeLocation = prefs.getString(_homePrefsKey));
    });
  }

  @override
  void dispose() {
    _acDebounce?.cancel();
    _statusMessageTimer?.cancel();
    _destCtrl.dispose();
    _startLocCtrl.dispose();
    _placesCtrl.dispose();
    _prefsCtrl.dispose();
    _customPrefCtrl.dispose();
    _currentFuelCtrl.dispose();
    _mileageCtrl.dispose();
    super.dispose();
  }


  int get _durationDays {
    if (_startDate != null && _endDate != null) {
      final d = _endDate!.difference(DateTime(_startDate!.year, _startDate!.month, _startDate!.day)).inDays + 1;
      return d.clamp(1, 14);
    }
    return _days;
  }

  String _fmtDate(DateTime? d) => d == null ? 'Pick date' : '${d.day}/${d.month}/${d.year}';
  String _fmtTime(TimeOfDay? t) =>
      t == null ? '--:--' : TripDateTime.formatTimeDisplay(DateTime(2026, 1, 1, t.hour, t.minute));

  void _toggleCategory(String id) {
    setState(() {
      if (_selectedCategoryIds.contains(id)) {
        _selectedCategoryIds.remove(id);
        _categoryPriorities.remove(id);
      } else {
        _selectedCategoryIds.add(id);
        _categoryPriorities[id] = 'must_visit';
      }
    });
  }

  void _selectAllCategories() {
    setState(() {
      for (final cat in kPlaceCategories) {
        _selectedCategoryIds.add(cat.id);
        _categoryPriorities.putIfAbsent(cat.id, () => 'must_visit');
      }
    });
  }

  void _clearAllCategories() {
    setState(() {
      _selectedCategoryIds.clear();
      _categoryPriorities.clear();
    });
  }

  void _cyclePriority(String id) {
    setState(() {
      final current = _categoryPriorities[id] ?? 'must_visit';
      if (current == 'must_visit') {
        _categoryPriorities[id] = 'would_like';
      } else if (current == 'would_like') {
        _categoryPriorities[id] = 'optional';
      } else {
        _categoryPriorities[id] = 'must_visit';
      }
    });
  }

  String _priorityLabel(String prio) {
    switch (prio) {
      case 'must_visit':
        return '⭐ Must Visit';
      case 'would_like':
        return '👍 Would Like';
      case 'optional':
        return '💡 Optional';
      default:
        return '⭐ Must Visit';
    }
  }

  Color _priorityColor(String prio) {
    switch (prio) {
      case 'must_visit':
        return const Color(0xFFF59E0B);
      case 'would_like':
        return const Color(0xFF3B82F6);
      case 'optional':
        return const Color(0xFF10B981);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  Future<void> _generate({String directive = ''}) async {
    final dest = _destCtrl.text.trim();
    if (dest.isEmpty) {
      setState(() => _error = 'Enter a destination first.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _showInsufficientPlacesWarning = false;
    });
    try {
      final places = _placesCtrl.text
          .split(RegExp(r'[,\n]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final selectedCategoryLabels = _selectedCategoryIds.map((id) {
        final cat = kPlaceCategories.firstWhere((c) => c.id == id,
            orElse: () => PlaceCategoryOption(id: id, label: id, icon: ''));
        return cat.label;
      }).toList();

      final categoryPrioritiesMapped = <String, String>{};
      for (final entry in _categoryPriorities.entries) {
        final cat = kPlaceCategories.firstWhere((c) => c.id == entry.key,
            orElse: () => PlaceCategoryOption(id: entry.key, label: entry.key, icon: ''));
        categoryPrioritiesMapped[cat.label] = entry.value;
      }

      final res = await _api.aiSmartItinerary(
        destination: dest,
        startLocation: _startLocCtrl.text.trim(),
        places: places,
        startDate: _startDate == null ? '' : _fmtDate(_startDate),
        startTime: TripDateTime.to24Hour(_startTime.hour, _startTime.minute),
        endDate: _endDate == null ? '' : _fmtDate(_endDate),
        endTime: _endTime == null ? '' : TripDateTime.to24Hour(_endTime!.hour, _endTime!.minute),
        durationDays: _durationDays,
        mode: _mode,
        preferences: _prefsCtrl.text.trim(),
        directive: directive,
        travellers: _travellers,
        fuelEfficiency: double.tryParse(_mileageCtrl.text.trim()) ?? _vehicle?.mileage,
        currentFuel: double.tryParse(_currentFuelCtrl.text.trim()),
        tankCapacity: _vehicle?.tankCapacity,
        vehicleType: _transportMode,
        tripType: 'around',
        selectedCategories: selectedCategoryLabels,
        categoryPriorities: categoryPrioritiesMapped,
        customPreferences: _customPrefCtrl.text.trim(),
        searchRadiusKm: _searchRadiusKm,
      );
      if (!mounted) return;
      // Guarantee Day 1 begins at the selected canonical start time
      final targetMin = _startTime.hour * 60 + _startTime.minute;
      if (res.days.isNotEmpty && res.days.first.blocks.isNotEmpty) {
        final d1 = res.days.first;
        final firstBlockStart = d1.blocks.first.start;
        final firstMin = TripDateTime.parseMinutes(firstBlockStart);
        if ((firstMin - targetMin).abs() > 15) {
          int cur = targetMin;
          for (final b in d1.blocks) {
            final dur = b.durationMin > 0 ? b.durationMin : (b.travelMin > 0 ? b.travelMin : 30);
            b.start = TripDateTime.formatMinutes(cur);
            b.end = TripDateTime.formatMinutes(cur + dur);
            cur += dur;
          }
        }
      }

      double totalKm = res.route?.distanceKm ?? 0;
      if (totalKm <= 0) {
        for (final d in res.days) {
          for (final b in d.blocks) {
            totalKm += (b.distanceKm > 0 ? b.distanceKm : 0);
          }
        }
      }

      setState(() {
        _itinerary = res.days;
        _budget = res.budget;
        _currentRoute = res.route;
        _navigationRoute = res.navigationRoute;
        _routeVersion = res.routeVersion ?? 1;
        _splitCount = _travellers; // default: split among travellers
        _isConfirmed = false;
        _totalRouteKm = totalKm > 0 ? totalKm : null;
        _routeStatusMessage = null;
        _searchRadiusKm = res.searchRadiusKm ?? _searchRadiusKm;
        _placesFoundCount = res.placesFoundCount;
        _canExpandSearch = res.canExpandSearch ?? false;
        _nextSearchRadiusKm = res.nextSearchRadiusKm;

        // Check if matching places are sparse
        int activityCount = 0;
        for (final d in res.days) {
          activityCount += d.blocks.where((b) => b.type == 'activity').length;
        }
        if (res.days.isNotEmpty && _selectedCategoryIds.isNotEmpty && activityCount < (_durationDays * 2)) {
          _showInsufficientPlacesWarning = true;
        }
      });

      if (res.days.isNotEmpty) {
        // Auto-schedule departure alerts and confirmation for Day 1
        final tripDate = _startDate ?? DateTime.now();
        final depTime = DateTime(
          tripDate.year,
          tripDate.month,
          tripDate.day,
          _startTime.hour,
          _startTime.minute,
        );
        TripReminderService.instance.scheduleTripStart(
          tripId: 'smart_${dest.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}',
          destination: dest,
          startPoint: _startLocCtrl.text.trim().isNotEmpty ? _startLocCtrl.text.trim() : 'Home',
          departureTime: depTime,
          stops: places.take(5).toList(),
          distanceKm: (_budget?.fuel != null) ? 180.0 : 145.0,
          remindBeforeMinutes: 30,
          vehicleType: _vehicle?.type ?? 'car',
        );
      }

      if (res.days.isEmpty) setState(() => _error = 'The AI returned an empty plan — try again.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setMode(String m) {
    setState(() => _mode = m);
    if (_itinerary.isNotEmpty) _generate();
  }

  /// Convert the AI timeline to PlanDays and persist it locally and to Supabase.
  Future<String> _persistPlan() async {
    final planDays = <PlanDay>[];
    for (int i = 0; i < _itinerary.length; i++) {
      final d = _itinerary[i];
      final items = <PlanItem>[];
      for (int j = 0; j < d.blocks.length; j++) {
        final b = d.blocks[j];
        if (b.title.trim().isEmpty) continue;
        items.add(PlanItem(
          id: '${DateTime.now().microsecondsSinceEpoch}_${i}_$j',
          text: b.title,
          time: TripDateTime.to12Hour(b.start),
          note: b.reason.isNotEmpty ? b.reason : (b.place.isNotEmpty ? b.place : ''),
          lat: b.lat,
          lng: b.lng,
          category: _blockToCategory(b.type),
        ));
      }
      planDays.add(PlanDay(id: '${DateTime.now().microsecondsSinceEpoch}_d$i', title: d.title.isEmpty ? 'Day ${i + 1}' : d.title, items: items));
    }
    final dest = _destCtrl.text.trim();
    final start = _startLocCtrl.text.trim();
    final tripKey = 'smart_${dest.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    final tripTitle = start.isNotEmpty ? '$start to $dest' : '$dest (AI Trip)';

    // Extract real verified coordinates from itinerary blocks
    GeoPoint? startCoord;
    GeoPoint? endCoord;
    final waypoints = <GeoPoint>[];

    for (final d in _itinerary) {
      for (final b in d.blocks) {
        if (b.lat != null && b.lng != null && (b.lat != 0.0 || b.lng != 0.0)) {
          final pt = GeoPoint(lat: b.lat!, lng: b.lng!, name: b.title.isNotEmpty ? b.title : b.place);
          if (startCoord == null) {
            startCoord = pt;
          } else {
            waypoints.add(pt);
          }
        }
      }
    }

    if (waypoints.isNotEmpty) {
      endCoord = waypoints.last;
    } else {
      endCoord = startCoord;
    }

    startCoord ??= GeoPoint(lat: 12.9716, lng: 77.5946, name: start.isNotEmpty ? start : 'Origin');
    endCoord ??= GeoPoint(lat: 12.9716, lng: 77.5946, name: dest.isNotEmpty ? dest : 'Destination');
    
    // 1. Save locally to TripExtrasStore
    await TripExtrasStore(tripKey).saveDays(planDays, name: start.isNotEmpty ? '$start to $dest' : '$dest (AI plan)');

    // 2. Save to TripHistoryService (automatically syncs to local cache & Supabase)
    final historyItem = TripHistoryItem(
      id: 'trip_${DateTime.now().millisecondsSinceEpoch}',
      title: tripTitle,
      startAddress: start.isNotEmpty ? start : 'Origin',
      endAddress: dest.isNotEmpty ? dest : 'Destination',
      waypoints: waypoints.map((w) => w.name ?? '').toList(),
      distanceKm: _totalRouteKm ?? (_budget?.fuel != null ? 180.0 : 145.0),
      durationMinutes: _durationDays * 480,
      vehicleType: _vehicle?.type ?? (_transportMode == 'bike' ? 'motorcycle' : 'car'),
      fuelCost: (_budget?.fuel ?? 0).toDouble(),
      tollCost: (_budget?.tolls ?? 0).toDouble(),
      totalCost: (_budget?.total ?? 0).toDouble(),
      completedAt: DateTime.now(),
      isRoundTrip: _tripType == 'around',
      totalStopsCount: planDays.fold(0, (sum, d) => sum + d.items.length),
    );
    await TripHistoryService.instance.saveTrip(historyItem);

    // 3. Direct Supabase cloud persistence for cross-device sync
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      try {
        final currentFuel = double.tryParse(_currentFuelCtrl.text.trim()) ?? _vehicle?.tankCapacity ?? 45.0;
        final mileage = double.tryParse(_mileageCtrl.text.trim()) ?? _vehicle?.mileage ?? 15.0;
        await _api.saveTrip(
          name: tripTitle,
          start: startCoord,
          end: endCoord,
          waypoints: waypoints,
          vehicleType: _vehicle?.type ?? (_transportMode == 'bike' ? 'motorcycle' : 'car'),
          token: session.accessToken,
          vehicle: Vehicle(
            type: _vehicle?.type ?? (_transportMode == 'bike' ? 'motorcycle' : 'car'),
            efficiencyKmPerLiter: mileage,
            tankCapacityLiters: _vehicle?.tankCapacity ?? 45.0,
            currentFuelLiters: currentFuel,
          ),
          tripStart: _startDate,
        );
      } catch (e) {
        debugPrint('Cloud save trip note: $e');
      }
    }

    return tripKey;
  }

  void _adjustDuration(SmartDay day, TimelineBlock block, int deltaMin) {
    setState(() {
      block.durationMin = (block.durationMin + deltaMin).clamp(15, 360);
      _reanchorDayTiming(day);
    });
  }

  void _removeStop(SmartDay day, TimelineBlock block) {
    final blockName = block.title.isNotEmpty ? block.title : block.place;
    setState(() {
      day.blocks.remove(block);
      _reanchorDayTiming(day);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed "$blockName". Recalculating route...'),
        duration: const Duration(seconds: 2),
      ),
    );
    _recalculateItinerary();
  }

  void _moveStop(SmartDay day, int index, int direction) {
    final targetIndex = index + direction;
    if (targetIndex < 0 || targetIndex >= day.blocks.length) return;
    if (day.blocks[index].type == 'start' || day.blocks[index].type == 'return') return;
    if (day.blocks[targetIndex].type == 'start' || day.blocks[targetIndex].type == 'return') return;
    setState(() {
      final item = day.blocks.removeAt(index);
      day.blocks.insert(targetIndex, item);
      _reanchorDayTiming(day);
    });
    _recalculateItinerary();
  }

  Future<void> _promptAddStop(SmartDay day) async {
    final placeCtrl = TextEditingController();
    List<Map<String, dynamic>> suggestions = [];
    Timer? debounce;
    bool isSearching = false;

    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                const Icon(Icons.add_location_alt_rounded, color: AppColors.accentLight, size: 22),
                const SizedBox(width: 8),
                Text('Add Place to Day ${day.day}',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: placeCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search place, temple, or attraction...',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      prefixIcon: const Icon(Icons.search_rounded, color: Colors.white70),
                      suffixIcon: isSearching
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight),
                              ))
                          : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                    onChanged: (val) {
                      debounce?.cancel();
                      if (val.trim().length < 2) {
                        setDlgState(() => suggestions = []);
                        return;
                      }
                      debounce = Timer(const Duration(milliseconds: 350), () async {
                        setDlgState(() => isSearching = true);
                        try {
                          final res = await _api.autocompletePlaces(val.trim());
                          if (ctx.mounted) {
                            setDlgState(() {
                              suggestions = res;
                              isSearching = false;
                            });
                          }
                        } catch (_) {
                          if (ctx.mounted) setDlgState(() => isSearching = false);
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  if (suggestions.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: suggestions.length,
                        separatorBuilder: (_, __) =>
                            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                        itemBuilder: (_, idx) {
                          final s = suggestions[idx];
                          final name = s['name'] as String? ?? '';
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.location_on_outlined, color: AppColors.accentLight, size: 18),
                            title: Text(name,
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                            onTap: () => Navigator.of(ctx).pop(s),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentLight,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  final text = placeCtrl.text.trim();
                  if (text.isNotEmpty) {
                    Navigator.of(ctx).pop({'name': text});
                  }
                },
                child: const Text('Add Stop', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    debounce?.cancel();

    if (selected != null) {
      final name = (selected['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) return;
      double? lat = (selected['lat'] as num?)?.toDouble();
      double? lng = (selected['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) {
        try {
          final geo = await _api.geocode(name);
          lat = geo?.lat;
          lng = geo?.lng;
        } catch (_) {}
      }
      final newBlock = TimelineBlock(
        start: '12:00',
        end: '13:00',
        type: 'activity',
        title: name,
        place: name,
        reason: 'Added by user',
        durationMin: 60,
        lat: lat,
        lng: lng,
      );
      int insertIdx = day.blocks.length;
      if (day.blocks.isNotEmpty &&
          (day.blocks.last.type == 'return' || day.blocks.last.type == 'checkin')) {
        insertIdx = day.blocks.length - 1;
      }
      setState(() {
        day.blocks.insert(insertIdx, newBlock);
        _reanchorDayTiming(day);
      });
      _recalculateItinerary();
    }
  }

  void _reanchorDayTiming(SmartDay day) {
    int curMin;
    if (day.day == 1) {
      curMin = _startTime.hour * 60 + _startTime.minute;
    } else {
      curMin = 8 * 60 + 30; // 08:30 AM for multi-day
    }
    for (final b in day.blocks) {
      final dur = (b.type == 'travel' || b.type == 'return')
          ? (b.travelMin > 0 ? b.travelMin : 30)
          : (b.durationMin > 0 ? b.durationMin : 45);
      b.start = TripDateTime.formatMinutes(curMin);
      b.end = TripDateTime.formatMinutes(curMin + dur);
      curMin += dur;
    }
  }

  Future<void> _recalculateItinerary() async {
    setState(() {
      _isCalculatingRoute = true;
      _routeStatusMessage = 'Calculating route...';
    });
    try {
      final res = await _api.recalculateSmartItinerary(
        days: _itinerary,
        startTime: TripDateTime.to24Hour(_startTime.hour, _startTime.minute),
        tripType: _tripType,
        origin: _startLocCtrl.text.trim(),
        destination: _destCtrl.text.trim(),
        currentFuel: double.tryParse(_currentFuelCtrl.text.trim()),
        tankCapacity: _vehicle?.tankCapacity,
        fuelEfficiency: double.tryParse(_mileageCtrl.text.trim()) ?? _vehicle?.mileage,
      );
      if (mounted && res != null && res.days.isNotEmpty) {
        setState(() {
          _itinerary = res.days;
          if (res.budget != null) _budget = res.budget;
          _currentRoute = res.route ?? _currentRoute;
          _navigationRoute = res.navigationRoute ?? _navigationRoute;
          _routeVersion = res.routeVersion ?? (_routeVersion + 1);
          _totalRouteKm = res.route?.distanceKm ?? res.totalDistanceKm ?? _totalRouteKm;
          _routeStatusMessage = 'Route updated';
        });
        _statusMessageTimer?.cancel();
        _statusMessageTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _routeStatusMessage = null);
        });
      }
    } catch (e) {
      debugPrint('Recalculate error: $e');
      if (mounted) {
        setState(() {
          _routeStatusMessage = 'Failed to update route';
        });
        _statusMessageTimer?.cancel();
        _statusMessageTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _routeStatusMessage = null);
        });
      }
    } finally {
      if (mounted) setState(() => _isCalculatingRoute = false);
    }
  }

  void _confirmTrip() {
    setState(() {
      _isConfirmed = true;
      for (final day in _itinerary) {
        for (final b in day.blocks) {
          b.isConfirmed = true;
        }
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Trip Confirmed! Stops locked with verified coordinates ✓'),
        backgroundColor: Color(0xFF10B981),
      ),
    );
  }

  /// Save the itinerary without leaving the screen.
  Future<void> _save() async {
    if (!AuthGuard.ensure(context, action: 'save trips')) return;
    await _persistPlan();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Itinerary saved & synced to all your devices ✓')),
    );
  }

  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    double toRad(double d) => d * math.pi / 180.0;
    final dLat = toRad(lat2 - lat1), dLng = toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(toRad(lat1)) * math.cos(toRad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Save and open the day-by-day planner to view/edit the trip checklist.
  Future<void> _openDayPlanner() async {
    if (!AuthGuard.ensure(context, action: 'save & start trips')) return;
    setState(() => _isConfirmed = true);
    final tripKey = await _persistPlan();
    if (!mounted) return;
    final dest = _destCtrl.text.trim();
    final start = _startLocCtrl.text.trim();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DayPlannerScreen(
        tripKey: tripKey,
        tripName: start.isNotEmpty ? '$start to $dest' : '$dest (AI plan)',
      ),
    ));
  }

  Future<void> _start() => _openDayPlanner();

  /// Start full turn-by-turn driving navigation directly from the AI itinerary.
  Future<void> _startNavigation() async {
    if (!AuthGuard.ensure(context, action: 'start navigation')) return;
    if (_itinerary.isEmpty) return;
    setState(() => _navLoading = true);

    try {
      await _persistPlan();
      setState(() => _isConfirmed = true);

      final dest = _destCtrl.text.trim();
      final start = _startLocCtrl.text.trim();

      // Assemble route chain: start -> waypoints -> end
      GeoPoint finalStart;
      GeoPoint finalEnd;
      final waypoints = <GeoPoint>[];

      if (_navigationRoute != null &&
          _navigationRoute!.origin != null &&
          _navigationRoute!.destination != null) {
        final orig = _navigationRoute!.origin!;
        final destObj = _navigationRoute!.destination!;
        finalStart = GeoPoint(
          lat: orig.lat,
          lng: orig.lng,
          name: (orig.name?.isNotEmpty == true) ? orig.name! : (start.isNotEmpty ? start : 'Start'),
        );
        finalEnd = GeoPoint(
          lat: destObj.lat,
          lng: destObj.lng,
          name: (destObj.name?.isNotEmpty == true) ? destObj.name! : (dest.isNotEmpty ? dest : 'Destination'),
        );
        for (final wp in _navigationRoute!.waypoints) {
          waypoints.add(GeoPoint(
            lat: wp.lat,
            lng: wp.lng,
            name: wp.name ?? '',
          ));
        }
      } else {
        // Fallback: Resolve start & destination and extract stops
        GeoPoint? startCoord;
        if (start.isNotEmpty) {
          try {
            startCoord = await _api.geocode(start);
          } catch (_) {}
        }
        if (startCoord == null) {
          try {
            final pos = await _currentPosition();
            startCoord = GeoPoint(lat: pos.latitude, lng: pos.longitude, name: start.isNotEmpty ? start : 'My Location');
          } catch (_) {}
        }

        GeoPoint? destCoord;
        if (dest.isNotEmpty) {
          try {
            destCoord = await _api.geocode(dest);
          } catch (_) {}
        }

        final allStops = <GeoPoint>[];
        for (final d in _itinerary) {
          for (final b in d.blocks) {
            if (b.lat != null && b.lng != null && (b.lat != 0.0 || b.lng != 0.0)) {
              allStops.add(GeoPoint(
                lat: b.lat!,
                lng: b.lng!,
                name: b.place.isNotEmpty ? b.place : b.title,
              ));
            }
          }
        }

        if (startCoord != null) {
          finalStart = startCoord;
          if (destCoord != null) {
            for (final s in allStops) {
              if (_haversineKm(finalStart.lat, finalStart.lng, s.lat, s.lng) > 0.2 &&
                  _haversineKm(destCoord.lat, destCoord.lng, s.lat, s.lng) > 0.2) {
                waypoints.add(s);
              }
            }
            finalEnd = destCoord;
          } else if (allStops.isNotEmpty) {
            waypoints.addAll(allStops.sublist(0, allStops.length - 1));
            finalEnd = allStops.last;
          } else {
            finalEnd = finalStart;
          }
        } else if (allStops.length >= 2) {
          finalStart = allStops.first;
          waypoints.addAll(allStops.sublist(1, allStops.length - 1));
          finalEnd = allStops.last;
        } else if (allStops.length == 1) {
          finalStart = allStops.first;
          finalEnd = destCoord ?? allStops.first;
        } else {
          throw Exception('No valid stops or destination found to navigate.');
        }
      }

      final clampedWaypoints = waypoints.length > 23 ? waypoints.sublist(0, 23) : waypoints;

      final vehicle = Vehicle(
        type: _vehicle?.type ?? (_transportMode == 'bike' ? 'motorcycle' : 'car'),
        efficiencyKmPerLiter: double.tryParse(_mileageCtrl.text.trim()) ?? _vehicle?.mileage ?? 15.0,
        tankCapacityLiters: _vehicle?.tankCapacity ?? 45.0,
        currentFuelLiters: double.tryParse(_currentFuelCtrl.text.trim()) ?? _vehicle?.tankCapacity ?? 45.0,
      );

      final plan = await _api.planTrip(
        start: finalStart,
        end: finalEnd,
        waypoints: clampedWaypoints,
        vehicle: vehicle,
      );

      if (!mounted) return;

      final savedItinerary = <Map<String, dynamic>>[];
      for (final d in _itinerary) {
        for (final b in d.blocks) {
          savedItinerary.add(b.toJson());
        }
      }

      final tripStart = _startDate != null
          ? DateTime(_startDate!.year, _startDate!.month, _startDate!.day, _startTime.hour, _startTime.minute)
          : DateTime.now();

      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TripScreen(
          plan: plan,
          startAddress: finalStart.name ?? (start.isNotEmpty ? start : 'Start'),
          endAddress: finalEnd.name ?? (dest.isNotEmpty ? dest : 'Destination'),
          vehicleType: vehicle.type,
          poiCategories: const ['restaurant', 'attraction', 'hotel', 'fuel', 'ev', 'viewpoint'],
          start: finalStart,
          end: finalEnd,
          waypoints: clampedWaypoints,
          vehicle: vehicle,
          initialTripStart: tripStart,
          savedItinerary: savedItinerary,
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start navigation: $e')),
      );
    } finally {
      if (mounted) setState(() => _navLoading = false);
    }
  }

  String _blockToCategory(String type) {
    switch (type) {
      case 'meal':
      case 'coffee':
        return 'restaurant';
      case 'checkin':
      case 'checkout':
        return 'stay';
      case 'activity':
      case 'shopping':
      case 'freetime':
      case 'rest':
        return 'activity';
      default:
        return 'place';
    }
  }

  (IconData, Color) _blockStyle(String type) {
    switch (type) {
      case 'start':
        return (Icons.flag_rounded, const Color(0xFF22C7C0));
      case 'travel':
        return (Icons.directions_car_rounded, const Color(0xFF94A3B8));
      case 'meal':
        return (Icons.restaurant_rounded, const Color(0xFFF97316));
      case 'coffee':
        return (Icons.local_cafe_rounded, const Color(0xFFD9A066));
      case 'rest':
        return (Icons.airline_seat_recline_normal_rounded, const Color(0xFF8B5CF6));
      case 'checkin':
        return (Icons.hotel_rounded, const Color(0xFF22C55E));
      case 'checkout':
        return (Icons.luggage_rounded, const Color(0xFF22C55E));
      case 'buffer':
        return (Icons.hourglass_bottom_rounded, const Color(0xFF94A3B8));
      case 'shopping':
        return (Icons.shopping_bag_rounded, const Color(0xFFEC4899));
      case 'freetime':
        return (Icons.beach_access_rounded, const Color(0xFF06B6D4));
      case 'return':
        return (Icons.home_rounded, const Color(0xFFEF4444));
      case 'fuel':
        return (Icons.local_gas_station_rounded, const Color(0xFFF59E0B));
      default:
        return (Icons.photo_camera_rounded, AppColors.accentLight);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppColors.obsidian,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Smart AI planner'),
      ),
      body: AnimatedBackground(
        imageUrl: _bgUrl,
        overlayOpacity: 0.64,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              RevealIn(child: _inputCard()),
              const SizedBox(height: 14),
              if (_error != null) ...[
                _errorBanner(),
                const SizedBox(height: 12),
              ],
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_itinerary.isNotEmpty)
                ..._results(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorBanner() => GlassCard(
        padding: const EdgeInsets.all(14),
        glow: false,
        child: Row(children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12.5))),
        ]),
      );

  Widget _field(TextEditingController c, String hint, IconData icon, {int maxLines = 1}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        prefixIcon: Icon(icon, color: Colors.white70, size: 20),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.07),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
      ),
    );
  }

  /// Debounced place autocomplete for the destination / start fields. Queries
  /// the backend proxy (the client Mapbox token is URL-restricted, so direct
  /// Mapbox calls 403 from the app).
  void _onPlaceQuery(String query, bool isDest) {
    _acDebounce?.cancel();
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        if (isDest) {
          _destSuggestions = [];
        } else {
          _startSuggestions = [];
        }
      });
      return;
    }
    _acDebounce = Timer(const Duration(milliseconds: 150), () async {
      final list = await _api.autocompletePlaces(q);
      if (!mounted) return;
      setState(() {
        if (isDest) {
          _destSuggestions = list;
        } else {
          _startSuggestions = list;
        }
      });
    });
  }

  /// Device position with graceful degradation: fresh cached fix → GPS at
  /// decreasing accuracy → any last-known fix → IP-based approximate location.
  Future<Position> _currentPosition() async {
    if (!kIsWeb) {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) return last;
        final ipPos = await _ipApproxPosition();
        if (ipPos != null) return ipPos;
        throw 'Location permission is permanently denied. Enable it for this app in Settings.';
      }
      if (permission == LocationPermission.denied) {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) return last;
        final ipPos = await _ipApproxPosition();
        if (ipPos != null) return ipPos;
        throw 'Location permission was denied. Please allow it to use your current location.';
      }
      if (!serviceEnabled) {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) return last;
        final ipPos = await _ipApproxPosition();
        if (ipPos != null) return ipPos;
        throw 'Location services are turned off. Enable them in device settings and try again.';
      }
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && DateTime.now().difference(last.timestamp).inMinutes < 15) {
          return last;
        }
      } catch (_) {}
    }
    for (final accuracy in const [LocationAccuracy.high, LocationAccuracy.medium, LocationAccuracy.low]) {
      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: accuracy,
            timeLimit: const Duration(seconds: 10),
          ),
        );
      } catch (_) {/* try a lower accuracy */}
    }
    if (!kIsWeb) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) return last;
      } catch (_) {}
    }
    final ipPos = await _ipApproxPosition();
    if (ipPos != null) return ipPos;

    throw "Couldn't get your location — check GPS/permissions, or search instead.";
  }

  /// Approximate location from the caller's IP address (city-level fallback).
  Future<Position?> _ipApproxPosition() async {
    for (final url in const ['https://ipwho.is/', 'https://ipapi.co/json/']) {
      try {
        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) continue;
        final m = jsonDecode(res.body) as Map<String, dynamic>;
        final lat = (m['latitude'] as num?)?.toDouble();
        final lng = (m['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        return Position(
          latitude: lat,
          longitude: lng,
          timestamp: DateTime.now(),
          accuracy: 5000,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
      } catch (_) {}
    }
    return null;
  }

  /// Fill the starting point from the device's current location.
  Future<void> _useCurrentLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final pos = await _currentPosition();
      final address = await _api.reverseGeocode(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        // Fall back to raw coordinates if every reverse geocoder came up empty.
        _startLocCtrl.text = (address == null || address.trim().isEmpty)
            ? '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}'
            : address;
        _startSuggestions = [];
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Fill the starting point from the saved home address (prompt to set it
  /// the first time; long-press the chip to change it later).
  Future<void> _useHomeLocation() async {
    final home = _homeLocation;
    if (home == null || home.trim().isEmpty) {
      await _editHomeLocation();
      return;
    }
    setState(() {
      _startLocCtrl.text = home;
      _startSuggestions = [];
    });
  }

  Future<void> _editHomeLocation() async {
    final ctrl = TextEditingController(text: _homeLocation ?? _startLocCtrl.text.trim());
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF13233B),
        title: const Text('Set home location', style: TextStyle(color: Colors.white, fontSize: 17)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'e.g. Mathikere, Bengaluru',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == null || saved.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_homePrefsKey, saved);
    if (!mounted) return;
    setState(() {
      _homeLocation = saved;
      _startLocCtrl.text = saved;
      _startSuggestions = [];
    });
  }

  /// Small pill button for the starting-point quick picks.
  Widget _quickChip(IconData icon, String label, VoidCallback onTap, {VoidCallback? onLongPress}) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.accentLight, size: 15),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  /// A place text field with a live autocomplete dropdown underneath.
  Widget _placeField(
    TextEditingController c,
    String hint,
    IconData icon, {
    required bool isDest,
  }) {
    final suggestions = isDest ? _destSuggestions : _startSuggestions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: c,
          style: const TextStyle(color: Colors.white),
          onChanged: (v) => _onPlaceQuery(v, isDest),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            prefixIcon: Icon(icon, color: Colors.white70, size: 20),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.07),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
            ),
          ),
        ),
        if (suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF13233B).withValues(alpha: 0.98),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Column(
              children: [
                for (final s in suggestions)
                  InkWell(
                    onTap: () {
                      setState(() {
                        c.text = s['name'] as String;
                        if (isDest) {
                          _destSuggestions = [];
                        } else {
                          _startSuggestions = [];
                        }
                      });
                      FocusScope.of(context).unfocus();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      child: Row(children: [
                        const Icon(Icons.place_outlined, color: Color(0xFF60A5FA), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(s['name'] as String,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _pill(String label, IconData icon, VoidCallback onTap) => Expanded(
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 16, color: AppColors.accentLight),
          label: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      );

  Widget _inputCard() {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Plan a trip with AI', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Set your start date & time — the AI schedules everything, breaks included.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5)),
          const SizedBox(height: 14),
          _tripTypeBadge(),
          _placeField(
            _startLocCtrl,
            '🛫 Starting Location (Origin & return)',
            Icons.my_location_rounded,
            isDest: false,
          ),
          const SizedBox(height: 8),
          // Quick picks: GPS current location + saved home (long-press to change).
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _locating
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight)),
                          SizedBox(width: 6),
                          Text('Locating…',
                              style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    )
                  : _quickChip(Icons.my_location_rounded, 'Current location', _useCurrentLocation),
              _quickChip(
                Icons.home_rounded,
                (_homeLocation == null || _homeLocation!.trim().isEmpty)
                    ? 'Set home'
                    : 'Home',
                _useHomeLocation,
                onLongPress: _editHomeLocation,
              ),
              if (_homeLocation != null && _homeLocation!.trim().isNotEmpty)
                _quickChip(Icons.edit_location_alt_rounded, 'Edit home', _editHomeLocation),
            ],
          ),
          const SizedBox(height: 6),
          Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                setState(() {
                  final tmp = _startLocCtrl.text;
                  _startLocCtrl.text = _destCtrl.text;
                  _destCtrl.text = tmp;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.swap_vert_rounded, color: AppColors.accentLight, size: 16),
                    SizedBox(width: 4),
                    Text('Swap Start & Destination', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          _placeField(
            _destCtrl,
            '🎯 Destination / Trip Area (e.g. Madurai, Mysore, Ooty)',
            Icons.explore_rounded,
            isDest: true,
          ),
          const SizedBox(height: 10),
          _field(_placesCtrl, 'Specific places to visit (comma-separated, optional)', Icons.place_rounded, maxLines: 2),
          const SizedBox(height: 12),
          
          // "Places I Want to Visit" Category Selector
          _placesSelectionSection(),
          
          const SizedBox(height: 14),
          // Start date + time
          Row(children: [
            _pill(_fmtDate(_startDate), Icons.calendar_today_rounded, () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: _startDate ?? now,
                firstDate: DateTime(now.year - 1),
                lastDate: DateTime(now.year + 3),
              );
              if (picked != null) setState(() => _startDate = picked);
            }),
            const SizedBox(width: 10),
            _pill('Start ${_fmtTime(_startTime)}', Icons.schedule_rounded, () async {
              final picked = await showTimePicker(context: context, initialTime: _startTime);
              if (picked != null) {
                setState(() {
                  _startTime = picked;
                  if (_itinerary.isNotEmpty && _itinerary.first.blocks.isNotEmpty) {
                    int cur = picked.hour * 60 + picked.minute;
                    for (final b in _itinerary.first.blocks) {
                      final dur = b.durationMin > 0 ? b.durationMin : (b.travelMin > 0 ? b.travelMin : 30);
                      b.start = TripDateTime.formatMinutes(cur);
                      b.end = TripDateTime.formatMinutes(cur + dur);
                      cur += dur;
                    }
                  }
                });
              }
            }),
          ]),
          const SizedBox(height: 10),
          // Optional end date + time
          Row(children: [
            _pill(_endDate == null ? 'End date (opt)' : _fmtDate(_endDate), Icons.event_rounded, () async {
              final base = _startDate ?? DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: _endDate ?? base,
                firstDate: base,
                lastDate: DateTime(base.year + 3),
              );
              if (picked != null) setState(() => _endDate = picked);
            }),
            const SizedBox(width: 10),
            _pill(_endTime == null ? 'End time (opt)' : 'End ${_fmtTime(_endTime)}', Icons.schedule_outlined, () async {
              final picked = await showTimePicker(context: context, initialTime: _endTime ?? const TimeOfDay(hour: 20, minute: 0));
              if (picked != null) setState(() => _endTime = picked);
            }),
          ]),
          const SizedBox(height: 14),
          // Duration (days) when no end date is set
          if (_endDate == null)
            Row(children: [
              Text('Days', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
              const SizedBox(width: 12),
              _stepBtn(Icons.remove, () => setState(() => _days = (_days - 1).clamp(1, 14))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text('$_days', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              _stepBtn(Icons.add, () => setState(() => _days = (_days + 1).clamp(1, 14))),
            ])
          else
            Text('Duration: $_durationDays day(s)', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
          const SizedBox(height: 12),
          // Travellers (drives the food/budget totals)
          Row(children: [
            Text('Travellers', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
            const SizedBox(width: 12),
            _stepBtn(Icons.remove, () => setState(() => _travellers = (_travellers - 1).clamp(1, 20))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text('$_travellers', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            _stepBtn(Icons.add, () => setState(() => _travellers = (_travellers + 1).clamp(1, 20))),
          ]),
          const SizedBox(height: 14),
          // Vehicle — pick Car or Bike, then choose your vehicle (drives fuel/budget)
          Text('Vehicle', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
          const SizedBox(height: 8),
          Row(children: [
            _transportChip('car', 'Car', Icons.directions_car_rounded),
            const SizedBox(width: 8),
            _transportChip('bike', 'Bike', Icons.two_wheeler_rounded),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _pill(
              _vehicle != null
                  ? '${_vehicle!.name} · ${_vehicle!.mileage.toStringAsFixed(0)} km/L'
                  : 'Select your ${_transportMode == 'bike' ? 'bike' : 'car'}',
              _transportMode == 'bike' ? Icons.two_wheeler_rounded : Icons.directions_car_rounded,
              _pickVehicle,
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _field(_mileageCtrl, 'Mileage (km/L)', Icons.speed_rounded)),
            const SizedBox(width: 10),
            Expanded(child: _field(_currentFuelCtrl, 'Fuel in Tank (L)', Icons.local_gas_station_rounded)),
          ]),
          const SizedBox(height: 14),
          // Pace mode
          Text('Pace', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
          const SizedBox(height: 8),
          Row(children: [
            for (final m in const ['relaxed', 'balanced', 'packed'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _modeChip(m),
              ),
          ]),
          const SizedBox(height: 12),
          _field(_prefsCtrl, 'Additional notes (e.g. pure veg food, early starts)', Icons.tune_rounded, maxLines: 2),
          const SizedBox(height: 16),
          AccentButton(
            onPressed: _loading ? null : () => _generate(),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(_itinerary.isEmpty ? 'GENERATE ITINERARY' : 'REGENERATE'),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _tripTypeBadge() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accentLight.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accentLight.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.sync_rounded, color: AppColors.accentLight, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Around Trip (Circuit)',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                ),
                SizedBox(height: 2),
                Text(
                  'Plans destination-based sights and returns to your starting origin',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placesSelectionSection() {
    final selectedCount = _selectedCategoryIds.length;
    final selectedSummary = kPlaceCategories
        .where((c) => _selectedCategoryIds.contains(c.id))
        .map((c) => '${c.icon} ${c.label.split('&')[0].trim()}')
        .join(' • ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _selectedCategoryIds.isNotEmpty
              ? AppColors.accentLight.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.category_rounded, color: AppColors.accentLight, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'What type of places do you want to visit?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Select categories below. The AI will strictly filter and optimize your route around your preferences.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11.5),
          ),
          const SizedBox(height: 10),
          // Action Buttons: Select All / Clear All
          Row(
            children: [
              InkWell(
                onTap: _selectAllCategories,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.accentLight.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.accentLight.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.done_all_rounded, size: 14, color: AppColors.accentLight),
                      SizedBox(width: 4),
                      Text('Select All', style: TextStyle(color: AppColors.accentLight, fontSize: 11.5, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _clearAllCategories,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.clear_all_rounded, size: 14, color: Colors.white70),
                      SizedBox(width: 4),
                      Text('Clear All', style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '$selectedCount selected',
                style: TextStyle(
                  color: selectedCount > 0 ? AppColors.accentLight : Colors.white54,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Wrap of 16 Category Chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final cat in kPlaceCategories)
                _categoryChip(cat),
            ],
          ),
          if (selectedCount > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.accentLight.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.accentLight.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, size: 14, color: AppColors.accentLight),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      selectedSummary,
                      style: const TextStyle(
                        color: Color(0xFFE2E8F0),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Custom preference text box
          _field(
            _customPrefCtrl,
            'Custom preference (e.g. I want temples, waterfalls and scenic viewpoints)',
            Icons.edit_note_rounded,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _categoryChip(PlaceCategoryOption cat) {
    final isSelected = _selectedCategoryIds.contains(cat.id);
    final priority = _categoryPriorities[cat.id] ?? 'must_visit';
    final prioColor = _priorityColor(priority);

    return InkWell(
      onTap: () => _toggleCategory(cat.id),
      onLongPress: () {
        if (isSelected) _cyclePriority(cat.id);
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? prioColor.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? prioColor : Colors.white.withValues(alpha: 0.15),
            width: isSelected ? 1.4 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: prioColor.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(cat.icon, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 6),
            Text(
              cat.label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.8),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Priority: ${_priorityLabel(priority)}. Tap to cycle priority.',
                child: InkWell(
                  onTap: () => _cyclePriority(cat.id),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: prioColor.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      priority == 'must_visit'
                          ? '⭐ Must'
                          : priority == 'would_like'
                              ? '👍 Like'
                              : '💡 Opt',
                      style: TextStyle(
                        color: prioColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _insufficientPlacesBanner() {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Color(0xFFF59E0B), size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Destination Place Discovery',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _placesFoundCount != null
                ? 'We found $_placesFoundCount relevant places for your selected destination and preferences.'
                : 'Limited places found strictly matching your selected preferences within ${_searchRadiusKm} km.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _showInsufficientPlacesWarning = false);
                },
                icon: const Icon(Icons.check_circle_outline_rounded, size: 14, color: AppColors.accentLight),
                label: const Text('Generate With Fewer Stops', style: TextStyle(color: Colors.white, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.accentLight),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              if (_canExpandSearch || _searchRadiusKm < 100)
                ElevatedButton.icon(
                  onPressed: () {
                    final nextR = _nextSearchRadiusKm ?? (_searchRadiusKm < 50 ? 50 : 100);
                    setState(() {
                      _searchRadiusKm = nextR;
                      _showInsufficientPlacesWarning = false;
                    });
                    _generate();
                  },
                  icon: const Icon(Icons.explore_rounded, size: 14),
                  label: Text('Expand Search Area (${_nextSearchRadiusKm ?? (_searchRadiusKm < 50 ? 50 : 100)} km)', style: const TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentLight,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _showInsufficientPlacesWarning = false);
                },
                icon: const Icon(Icons.category_rounded, size: 14, color: Colors.white70),
                label: const Text('Change Categories', style: TextStyle(color: Colors.white70, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _transportChip(String mode, String label, IconData icon) {
    final selected = _transportMode == mode;
    return GestureDetector(
      onTap: () => setState(() {
        _transportMode = mode;
        // Drop the current vehicle if it no longer matches the chosen type.
        final wantType = mode == 'bike' ? 'motorcycle' : 'car';
        if (_vehicle != null && _vehicle!.type != wantType) _vehicle = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentLight.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.accentLight : Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: selected ? AppColors.accentLight : Colors.white.withValues(alpha: 0.8)),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: selected ? AppColors.accentLight : Colors.white.withValues(alpha: 0.8),
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        ]),
      ),
    );
  }

  /// Pick the traveller's own vehicle from the built-in list, filtered to the
  /// chosen transport type. The vehicle's mileage feeds the fuel/budget calc.
  Future<void> _pickVehicle() async {
    final wantType = _transportMode == 'bike' ? 'motorcycle' : 'car';
    // Saved account vehicles first, then the built-in list.
    final saved = (await _api.savedVehicles()).where((v) => v.type == wantType).toList();
    final list = [...saved, ...predefinedVehicles.where((v) => v.type == wantType)];
    if (!mounted) return;
    final chosen = await showModalBottomSheet<VehicleModel>(
      context: context,
      backgroundColor: const Color(0xFF161326),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Select your ${_transportMode == 'bike' ? 'bike' : 'car'}',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final v = list[i];
                  final sel = v.id == _vehicle?.id;
                  return ListTile(
                    leading: Icon(
                        _transportMode == 'bike' ? Icons.two_wheeler_rounded : Icons.directions_car_rounded,
                        color: sel ? AppColors.accentLight : Colors.white.withValues(alpha: 0.6)),
                    title: Text(v.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    subtitle: Text('${v.mileage.toStringAsFixed(0)} km/L · ${v.tankCapacity.toStringAsFixed(0)} L tank',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
                    trailing: sel ? const Icon(Icons.check_circle, color: AppColors.accentLight) : null,
                    onTap: () => Navigator.pop(ctx, v),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen != null) {
      setState(() {
        _vehicle = chosen;
        _mileageCtrl.text = chosen.mileage.toStringAsFixed(1);
        _currentFuelCtrl.text = chosen.tankCapacity.toStringAsFixed(0);
      });
      // If a plan already exists, refresh its budget with the new mileage.
      if (_itinerary.isNotEmpty) _generate();
    }
  }

  Widget _modeChip(String m) {
    final selected = _mode == m;
    return GestureDetector(
      onTap: () => _setMode(m),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentLight.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.accentLight : Colors.white.withValues(alpha: 0.15)),
        ),
        child: Text('${m[0].toUpperCase()}${m.substring(1)}',
            style: TextStyle(
                color: selected ? AppColors.accentLight : Colors.white.withValues(alpha: 0.8),
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      );

  List<Widget> _results() {
    return [
      if (_loading) ...[
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.accentLight.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.accentLight.withValues(alpha: 0.4)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text(
                'Regenerating balanced itinerary with AI...',
                style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
      // Draft / Confirmed Status Banner
      _tripStatusBanner(),
      const SizedBox(height: 14),
      if (_isCalculatingRoute || _routeStatusMessage != null) ...[
        _routeCalculationBanner(),
        const SizedBox(height: 14),
      ],
      if (_showInsufficientPlacesWarning) ...[
        _insufficientPlacesBanner(),
        const SizedBox(height: 14),
      ],
      if (_budget != null) ...[
        _budgetCard(_budget!),
        const SizedBox(height: 14),
      ],
      _departureReminderCard(),
      const SizedBox(height: 14),
      _controlsCard(),
      const SizedBox(height: 14),
      ...RevealIn.stagger(
        [for (final day in _itinerary) _dayCard(day)],
        initial: const Duration(milliseconds: 80),
        step: const Duration(milliseconds: 60),
      ),
      const SizedBox(height: 6),
      Row(children: [
        OutlinedButton.icon(
          onPressed: _loading ? null : () => _generate(directive: 'Regenerate fresh variety of attractions and balanced pacing.'),
          icon: const Icon(Icons.refresh_rounded, size: 18, color: AppColors.accentLight),
          label: const Text('Regenerate', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: AppColors.accentLight.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.bookmark_add_rounded, size: 18, color: Colors.white),
            label: const Text('Save', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _openDayPlanner,
            icon: const Icon(Icons.calendar_month_rounded, size: 18, color: Color(0xFF60A5FA)),
            label: const Text('Day Plan', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: AccentButton(
          onPressed: _navLoading ? null : _startNavigation,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (_navLoading)
              const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            else
              const Icon(Icons.navigation_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Text(
              _navLoading ? 'CALCULATING ROUTE & STARTING…' : 'START NAVIGATION',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.5),
            ),
          ]),
        ),
      ),
    ];
  }

  Widget _tripStatusBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _isConfirmed
            ? const Color(0xFF10B981).withValues(alpha: 0.15)
            : const Color(0xFF38BDF8).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isConfirmed
              ? const Color(0xFF10B981).withValues(alpha: 0.4)
              : const Color(0xFF38BDF8).withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _isConfirmed
                  ? const Color(0xFF10B981).withValues(alpha: 0.25)
                  : const Color(0xFF38BDF8).withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isConfirmed ? Icons.verified_rounded : Icons.edit_note_rounded,
              color: _isConfirmed ? const Color(0xFF34D399) : const Color(0xFF38BDF8),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _isConfirmed ? 'TRIP CONFIRMED' : 'DRAFT ITINERARY',
                      style: TextStyle(
                        color: _isConfirmed ? const Color(0xFF34D399) : const Color(0xFF38BDF8),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '🔄 Around Trip',
                        style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (_totalRouteKm != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${_totalRouteKm!.toStringAsFixed(0)} km',
                        style: const TextStyle(color: Colors.white54, fontSize: 10.5, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _isConfirmed
                      ? 'All stops verified with GPS waypoints. Ready to navigate.'
                      : 'Review route, adjust visit times, or remove stops before locking your trip.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (!_isConfirmed)
            ElevatedButton(
              onPressed: _confirmTrip,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: const Text('CONFIRM', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
  }

  Widget _routeCalculationBanner() {
    final isUpdating = _isCalculatingRoute;
    final isSuccess = _routeStatusMessage == 'Route updated';
    final color = isUpdating
        ? const Color(0xFF38BDF8)
        : (isSuccess ? const Color(0xFF10B981) : Colors.orangeAccent);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Row(
        children: [
          if (isUpdating)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
            )
          else
            Icon(
              isSuccess ? Icons.check_circle_rounded : Icons.info_outline_rounded,
              color: color,
              size: 18,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isUpdating
                  ? 'Calculating route with live road network...'
                  : (isSuccess
                      ? 'Route updated (v$_routeVersion • ${_totalRouteKm != null ? "${_totalRouteKm!.toStringAsFixed(0)} km" : "Road synced"})'
                      : (_routeStatusMessage ?? 'Route status ready')),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniReorderBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Icon(icon, size: 12, color: Colors.white70),
      ),
    );
  }

  Widget _miniDurationBtn(String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _departureReminderCard() {
    final tripDate = _startDate ?? DateTime.now();
    final depTime = DateTime(
      tripDate.year,
      tripDate.month,
      tripDate.day,
      _startTime.hour,
      _startTime.minute,
    );
    final reminderTime = depTime.subtract(const Duration(minutes: 30));
    final reminderTimeFormatted = TripDateTime.formatTimeDisplay(reminderTime);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF38BDF8).withValues(alpha: 0.15),
            const Color(0xFF6366F1).withValues(alpha: 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.5)),
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: Color(0xFF38BDF8),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '30-Minute Departure Alert',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Alert scheduled for $reminderTimeFormatted',
                      style: const TextStyle(
                        color: Color(0xFF7DD3FC),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.5)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, color: Color(0xFF4ADE80), size: 12),
                    SizedBox(width: 4),
                    Text(
                      'ACTIVE',
                      style: TextStyle(
                        color: Color(0xFF4ADE80),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Voyplan will send a reminder notification 30 minutes before your departure to finish packing, verify fuel/tickets, and start getting ready.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _budgetCard(TripBudget b) {
    final sym = b.currency == 'INR' ? '₹' : '${b.currency} ';
    String m(int v) => '$sym${v.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (x) => '${x[1]},')}';
    Widget row(IconData icon, String label, int value, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13))),
            Text(m(value), style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
          ]),
        );
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.account_balance_wallet_rounded, color: AppColors.accentLight, size: 20),
            const SizedBox(width: 8),
            const Text('Estimated budget', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            if (b.international) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.5)),
                ),
                child: const Text('International',
                    style: TextStyle(color: Color(0xFF7DD3FC), fontSize: 10.5, fontWeight: FontWeight.w700)),
              ),
            ],
            const Spacer(),
            Text('${b.days}d · ${b.travellers} pax',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
          ]),
          const SizedBox(height: 10),
          if (b.transport > 0)
            row(Icons.flight_rounded, 'Flights / tickets', b.transport, const Color(0xFF38BDF8)),
          if (b.fuel > 0) row(Icons.local_gas_station_rounded, 'Fuel', b.fuel, const Color(0xFFF97316)),
          if (b.tolls > 0) row(Icons.toll_rounded, 'Tolls', b.tolls, const Color(0xFFEAB308)),
          if (b.localTransport > 0)
            row(Icons.local_taxi_rounded, 'Local transport', b.localTransport, const Color(0xFFFACC15)),
          row(Icons.restaurant_rounded, 'Food', b.food, const Color(0xFF22C55E)),
          row(Icons.hotel_rounded, 'Hotel stay', b.stay, const Color(0xFF8B5CF6)),
          row(Icons.more_horiz_rounded, 'Buffer (10%)', b.buffer, Colors.white54),
          Divider(color: Colors.white.withValues(alpha: 0.15), height: 20),
          Row(children: [
            const Text('Total', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
            const Spacer(),
            Text(m(b.total), style: const TextStyle(color: AppColors.accentLight, fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 4),
          Text('≈ ${m(b.perDay)}/day',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
          const SizedBox(height: 12),
          // Split the budget
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.groups_rounded, size: 18, color: AppColors.accentLight),
                  const SizedBox(width: 8),
                  const Text('Split the budget', style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  _stepBtn(Icons.remove, () => setState(() => _splitCount = (_splitCount - 1).clamp(1, 20))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('$_splitCount', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  _stepBtn(Icons.add, () => setState(() => _splitCount = (_splitCount + 1).clamp(1, 20))),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Text('$_splitCount ${_splitCount == 1 ? 'person' : 'people'} pay', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12.5)),
                  const Spacer(),
                  Text('${m((b.total / _splitCount).round())} each',
                      style: const TextStyle(color: AppColors.accentLight, fontSize: 15, fontWeight: FontWeight.w800)),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
              b.international
                  ? 'Flights/tickets priced per person; food, stay & local transport at international rates. Adjust travellers above.'
                  : 'Fuel from the routed distance; tolls, food & stay estimated. Adjust travellers above.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _controlsCard() {
    Widget ctl(String label, IconData icon, String directive) => OutlinedButton.icon(
          onPressed: _loading ? null : () => _generate(directive: directive),
          icon: Icon(icon, size: 16, color: AppColors.accentLight),
          label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        );
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, color: AppColors.accentLight, size: 18),
              const SizedBox(width: 8),
              const Text('Tune with AI', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton.icon(
                onPressed: _loading ? null : () => _generate(directive: 'Regenerate fresh variety of attractions and balanced pacing.'),
                icon: const Icon(Icons.autorenew_rounded, size: 16, color: AppColors.accentLight),
                label: const Text('Fresh Plan', style: TextStyle(color: AppColors.accentLight, fontSize: 12.5, fontWeight: FontWeight.w700)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ctl('Optimize', Icons.tune_rounded, 'Optimise the schedule: tighten timings, minimise backtracking, better flow.'),
            ctl('More sightseeing', Icons.add_photo_alternate_rounded, 'Add more sightseeing and notable attractions in selected categories.'),
            ctl('More free time', Icons.self_improvement_rounded, 'Add more free/relaxation time and shorten packed stretches.'),
            ctl('Reduce travel', Icons.route_rounded, 'Reduce travel: group nearby places, cut long transfers.'),
            ctl('Add meal breaks', Icons.restaurant_rounded, 'Ensure proper breakfast, lunch, dinner and a coffee break each day.'),
          ]),
        ],
      ),
    );
  }

  Widget _dayCard(SmartDay day) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: AppColors.accentGradient,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('DAY ${day.day}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(day.title.isEmpty ? '' : day.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700)),
              ),
              if (day.date.isNotEmpty)
                Text(day.date, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11.5)),
            ]),
            const SizedBox(height: 12),
            for (int i = 0; i < day.blocks.length; i++) _blockRow(day, day.blocks[i], i == day.blocks.length - 1),
            if (!_isConfirmed) ...[
              const SizedBox(height: 10),
              InkWell(
                onTap: () => _promptAddStop(day),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.accentLight.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.accentLight.withValues(alpha: 0.25)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_location_alt_rounded, size: 15, color: AppColors.accentLight),
                      SizedBox(width: 6),
                      Text('+ Add Place to Day',
                          style: TextStyle(color: AppColors.accentLight, fontSize: 12, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _travelIcon(String mode) {
    switch (mode) {
      case 'flight':
        return Icons.flight_rounded;
      case 'train':
        return Icons.train_rounded;
      case 'bus':
        return Icons.directions_bus_rounded;
      case 'ferry':
        return Icons.directions_boat_rounded;
      case 'walk':
        return Icons.directions_walk_rounded;
      default:
        return Icons.directions_car_rounded;
    }
  }

  String _travelEmoji(String mode) {
    switch (mode) {
      case 'flight':
        return '✈️';
      case 'train':
        return '🚆';
      case 'bus':
        return '🚌';
      case 'ferry':
        return '⛴️';
      case 'walk':
        return '🚶';
      default:
        return '🚗';
    }
  }

  Widget _blockRow(SmartDay day, TimelineBlock b, bool isLast) {
    final (icon, color) = _blockStyle(b.type);
    // Travel/return legs pick their icon from the mode of transport (flight,
    // train, bus…) so an international flight isn't shown as a car drive.
    final isLeg = b.type == 'travel' || b.type == 'return';
    final legIcon = isLeg ? _travelIcon(b.travelMode) : icon;
    
    // Normalize time display (e.g. 2:00 PM – 3:30 PM)
    String formatTimeStr(String t) {
      final clean = t.trim();
      if (clean.isEmpty) return '';
      return TripDateTime.to12Hour(clean);
    }

    final startLabel = formatTimeStr(b.start);
    final endLabel = formatTimeStr(b.end);
    final timeLabel = endLabel.isNotEmpty && endLabel != startLabel ? '$startLabel–\n$endLabel' : startLabel;
    
    final meta = <String>[];
    if (isLeg) {
      if (b.travelMin > 0) meta.add('${_travelEmoji(b.travelMode)} ${b.travelMin} min');
      if (b.distanceKm > 0) meta.add('${b.distanceKm.toStringAsFixed(1)} km');
    } else {
      if (b.durationMin > 0) meta.add('${b.durationMin} min');
    }
    final isActivity = b.type == 'activity';
    final bool allowTempleRecognition = _selectedCategoryIds.isEmpty || _selectedCategoryIds.contains('temples');
    final temple = (isActivity && allowTempleRecognition && (b.categories.contains('Temples & Religious Places') || b.title.toLowerCase().contains('temple') || b.title.toLowerCase().contains('darshan')))
        ? TempleDatabase.findTemple(b.title.isNotEmpty ? b.title : b.place)
        : null;
    final isTemple = isActivity && temple != null;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time column
          SizedBox(
            width: 82,
            child: Text(timeLabel,
                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
          // Timeline rail
          Column(children: [
            Container(
              width: 30, height: 30, alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isTemple ? const Color(0xFFF59E0B).withValues(alpha: 0.2) : color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(color: isTemple ? const Color(0xFFF59E0B) : color, width: 1.2),
              ),
              child: Icon(isTemple ? Icons.temple_hindu_rounded : legIcon, size: 16, color: isTemple ? const Color(0xFFF59E0B) : color),
            ),
            if (!isLast) Expanded(child: Container(width: 2, color: Colors.white.withValues(alpha: 0.12), margin: const EdgeInsets.symmetric(vertical: 2))),
          ]),
          const SizedBox(width: 10),
          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Container(
                padding: isTemple ? const EdgeInsets.all(10) : EdgeInsets.zero,
                decoration: isTemple
                    ? BoxDecoration(
                        color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                      )
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          b.title.isNotEmpty ? b.title : (temple != null ? 'Darshan at ${temple.canonicalName}' : b.place),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isTemple ? 14.5 : 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (b.breakType.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                          child: Text(b.breakType, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
                        ),
                      if (temple != null)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star, color: Color(0xFFF59E0B), size: 11),
                              const SizedBox(width: 2),
                              Text('${temple.rating}', style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 10.5, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        )
                      else if (b.reason.contains('⭐'))
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star, color: Color(0xFF10B981), size: 11),
                              const SizedBox(width: 2),
                              Text(
                                RegExp(r'⭐\s*([0-9.]+)').firstMatch(b.reason)?.group(1) ?? '4.7',
                                style: const TextStyle(color: Color(0xFF10B981), fontSize: 10.5, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                    ]),
                    if (temple != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '🛕 Deity: ${temple.deity}',
                        style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 11, color: Colors.white.withValues(alpha: 0.6)),
                          const SizedBox(width: 4),
                          Text(temple.timing, style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 10.5)),
                        ],
                      ),
                      if (temple.darshanWaitInfo != null) ...[
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.timer_outlined, size: 12, color: Color(0xFFF87171)),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  '⏳ Darshan Wait: ${temple.darshanWaitInfo}',
                                  style: const TextStyle(
                                    color: Color(0xFFFCA5A5),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 2),
                      Text(
                        '✨ Highlights: ${temple.highlights}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11, fontStyle: FontStyle.italic),
                      ),
                    ],
                    if (meta.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(meta.join(' · '),
                            style: TextStyle(
                              color: isTemple ? const Color(0xFFFBBF24) : Colors.white.withValues(alpha: 0.72),
                              fontSize: 11.5,
                              fontWeight: isTemple ? FontWeight.w700 : FontWeight.w500,
                            )),
                      ),
                    if (b.place.isNotEmpty && b.place != b.title)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            Icon(Icons.location_on_outlined, size: 11, color: Colors.white.withValues(alpha: 0.45)),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                b.place,
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (b.reason.isNotEmpty && (temple == null || !b.reason.contains('Deity:')))
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          b.reason,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.58), fontSize: 11, fontStyle: FontStyle.italic),
                        ),
                      ),
                    if (b.categories.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final cat in b.categories)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.accentLight.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.accentLight.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  cat,
                                  style: const TextStyle(
                                    color: AppColors.accentLight,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (b.whyIncluded.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 1),
                              child: Icon(Icons.lightbulb_outline_rounded, size: 12, color: Color(0xFF38BDF8)),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                'Why included: ${b.whyIncluded}',
                                style: const TextStyle(
                                  color: Color(0xFFE2E8F0),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (b.isFuelStop || b.type == 'fuel')
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.local_gas_station_rounded, size: 13, color: Color(0xFFF59E0B)),
                            SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                '⛽ Recommended Fuel Stop (Smart Refuel Planning)',
                                style: TextStyle(color: Color(0xFFFBBF24), fontSize: 10.5, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (!_isConfirmed && (b.type == 'activity' || b.type == 'shopping' || b.type == 'meal' || b.type == 'coffee' || b.type == 'fuel')) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (b.durationMin > 0) ...[
                            _miniDurationBtn('-15m', () => _adjustDuration(day, b, -15)),
                            const SizedBox(width: 4),
                            _miniDurationBtn('+15m', () => _adjustDuration(day, b, 15)),
                            const SizedBox(width: 8),
                          ],
                          if (b.type != 'start' && b.type != 'return') ...[
                            _miniReorderBtn(Icons.arrow_upward_rounded, () => _moveStop(day, day.blocks.indexOf(b), -1)),
                            const SizedBox(width: 4),
                            _miniReorderBtn(Icons.arrow_downward_rounded, () => _moveStop(day, day.blocks.indexOf(b), 1)),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () => _removeStop(day, b),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.25)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.close_rounded, size: 11, color: Colors.redAccent),
                                    SizedBox(width: 3),
                                    Text('Remove', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          if (b.openingHours.isNotEmpty) ...[
                            const Spacer(),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.schedule_rounded, size: 11, color: Colors.white.withValues(alpha: 0.5)),
                                const SizedBox(width: 3),
                                Text(
                                  b.openingHours,
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
