import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/app_config.dart';
import '../theme/app_theme.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, RealtimeChannel;
import '../widgets/app_design.dart';
import '../data/attraction_database.dart';
import '../services/collab_service.dart';
import 'smart_itinerary_screen.dart';
import 'trip_demo_screen.dart';
import 'package:file_picker/file_picker.dart';
import '../models/trip_extras.dart';
import '../models/trip_models.dart';
import '../models/vehicles_data.dart';
import 'trip_screen.dart';
import '../services/trip_extras_store.dart';
import '../services/api_service.dart';
import '../utils/plan_export.dart';
import '../utils/gsap_demo.dart';
import 'bookings_screen.dart';
import 'active_trip_screen.dart';
import 'gallery_screen.dart';
import '../services/auth_guard.dart';

/// A standalone day-by-day trip planner (no route/plan required). Opens directly
/// for a "vacation" style trip: organise days, search & add places, see them as
/// numbered pins on the map. Responsive 3-pane on wide screens, stacked on
/// phones. Data persists locally under [tripKey].
class DayPlannerScreen extends StatefulWidget {
  final String tripKey;
  final String tripName;
  const DayPlannerScreen({super.key, this.tripKey = 'standalone', this.tripName = 'My Trip Plan'});

  @override
  State<DayPlannerScreen> createState() => _DayPlannerScreenState();
}

String _uid() => DateTime.now().microsecondsSinceEpoch.toString();

class _DayPlannerScreenState extends State<DayPlannerScreen> {
  // Cinematic theme (matches the trek tool): animated background + glass cards.
  static const String _bgUrl =
      'https://images.unsplash.com/photo-1469474968028-56623f02e42e?q=80&w=2000&auto=format&fit=crop';

  // Modes of transport for a day (id, label, icon, rough km/h for leg estimates).
  static const List<(String, String, IconData, double)> _transportModes = [
    ('car', 'Car', Icons.directions_car_rounded, 45),
    ('bike', 'Bike', Icons.two_wheeler_rounded, 35),
    ('walk', 'Walk', Icons.directions_walk_rounded, 5),
    ('train', 'Train', Icons.train_rounded, 70),
    ('bus', 'Bus', Icons.directions_bus_rounded, 40),
    ('flight', 'Flight', Icons.flight_rounded, 500),
    ('combined', 'Combined', Icons.alt_route_rounded, 45),
  ];

  bool _isOwnVehicleMode(String m) => m == 'car' || m == 'bike';
  bool _isBookingMode(String m) => m == 'train' || m == 'bus' || m == 'flight' || m == 'combined';

  // Item categories (id, label, icon).
  static const List<(String, String, IconData)> _itemCategories = [
    ('place', 'Place', Icons.place_rounded),
    ('restaurant', 'Restaurant', Icons.restaurant_rounded),
    ('stay', 'Stay', Icons.hotel_rounded),
    ('activity', 'Activity', Icons.local_activity_rounded),
  ];

  double _transportSpeed(String id) =>
      _transportModes.firstWhere((m) => m.$1 == id, orElse: () => _transportModes.first).$4;
  IconData _categoryIcon(String id) =>
      _itemCategories.firstWhere((c) => c.$1 == id, orElse: () => _itemCategories.first).$3;

  late final TripExtrasStore _store = TripExtrasStore(widget.tripKey);
  final _api = ApiService();
  final _collab = CollabService();
  final _searchCtrl = TextEditingController();

  // Collaboration: when this plan is linked to a cloud shared_trip, edits sync
  // both ways in real time.
  SharedTrip? _shared;
  RealtimeChannel? _channel;
  bool _applyingRemote = false; // guard so remote updates don't echo back

  List<PlanDay> _days = [];
  int _selectedDay = 0;
  bool _navLoading = false;
  bool _loading = true;
  DateTime? _startedAt; // non-null once the trip is started (active-trip mode)

  List<Map<String, String>> _results = [];
  bool _searching = false;
  String? _searchError;
  Timer? _searchDebounce;
  String _activeCategoryFilter = 'All';

  static const List<String> _quickCategories = [
    'All',
    '✨ Activities',
    '🛕 Temples',
    '🏖️ Beaches',
    '🌄 Viewpoints',
    '🏰 Forts',
    '🌊 Waterfalls',
    '🐘 Wildlife',
    '🍛 Food',
  ];

  // Lazy caches: per-day weather (keyed by day id) and real road legs (keyed by
  // "fromItemId>toItemId"). Populated in the background, then setState refreshes.
  final Map<String, String> _weatherCache = {};
  final Set<String> _weatherPending = {};
  final Map<String, String> _legCache = {};
  final Set<String> _legPending = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    final days = await _store.loadDays();
    final startedAt = await _store.loadStartedAt();
    if (!mounted) return;
    setState(() {
      _days = days;
      _startedAt = startedAt;
      _loading = false;
    });
    _loadSuggestions();
    // Ensure any opened, non-empty plan is listed under "Saved trips".
    if (days.isNotEmpty) _store.saveDays(days, name: widget.tripName);
  }

  void _persist() {
    _store.saveDays(_days, name: widget.tripName);
    // If this plan is shared and we can edit, push the change to collaborators.
    final s = _shared;
    if (s != null && !_applyingRemote && _collab.canEdit(s)) {
      _collab.updateData(s.id, {'days': _days.map((d) => d.toJson()).toList()}).catchError((_) {});
    }
  }

  Map<String, dynamic> _dataPayload() => {'days': _days.map((d) => d.toJson()).toList()};

  void _applyRemote(Map<String, dynamic> data) {
    final list = (data['days'] as List?) ?? [];
    final days = list.map((e) => PlanDay.fromJson((e as Map).cast<String, dynamic>())).toList();
    _applyingRemote = true;
    setState(() {
      _days = days;
      if (_selectedDay >= _days.length) _selectedDay = _days.isEmpty ? 0 : _days.length - 1;
    });
    _store.saveDays(_days, name: widget.tripName); // cache locally, but DON'T re-push
    _applyingRemote = false;
  }

  void _subscribeShared(SharedTrip t) {
    _channel?.unsubscribe();
    _channel = _collab.subscribe(t.id, (data, updatedBy) {
      final myId = Supabase.instance.client.auth.currentSession?.user.id;
      if (updatedBy != null && updatedBy == myId) return; // ignore our own echo
      _applyRemote(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trip updated by a collaborator'), duration: Duration(seconds: 2)),
        );
      }
    });
  }

  void _addDay() {
    if (!AuthGuard.ensure(context, action: 'edit trips')) return;
    setState(() {
      _days.add(PlanDay(id: _uid(), title: 'Day ${_days.length + 1}'));
      _selectedDay = _days.length - 1;
    });
    _persist();
  }

  void _loadSuggestions() {
    final cat = _activeCategoryFilter == 'All'
        ? null
        : _activeCategoryFilter.replaceAll(RegExp(r'[^\w\s]'), '').trim();
    final toCity = _journeyEndpoints().to;
    final results = AttractionDatabase.search(
      '',
      category: cat,
      cityFilter: toCity.isNotEmpty ? toCity : null,
    );
    if (mounted) {
      setState(() {
        _results = results;
        _searchError = null;
      });
    }
  }

  void _onSearchChanged(String val) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (val.trim().isEmpty) {
        _loadSuggestions();
      } else {
        _search();
      }
    });
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      _loadSuggestions();
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final cat = _activeCategoryFilter == 'All'
          ? null
          : _activeCategoryFilter.replaceAll(RegExp(r'[^\w\s]'), '').trim();
      final local = AttractionDatabase.search(q, category: cat);
      if (local.isNotEmpty && mounted) {
        setState(() => _results = local);
      }
      final toCity = _journeyEndpoints().to;
      final res = await _api.aiSearchPlaces(query: q, near: toCity.isNotEmpty ? toCity : null);
      if (!mounted) return;
      if (res.isNotEmpty) {
        setState(() => _results = res);
      } else if (local.isNotEmpty) {
        setState(() => _results = local);
      }
    } catch (e) {
      if (!mounted) return;
      final cat = _activeCategoryFilter == 'All'
          ? null
          : _activeCategoryFilter.replaceAll(RegExp(r'[^\w\s]'), '').trim();
      final local = AttractionDatabase.search(q, category: cat);
      if (local.isNotEmpty) {
        setState(() => _results = local);
      } else {
        setState(() => _searchError = e is ApiException ? e.message : 'Search failed. Try again.');
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _addSearchedPlace(String name, String area, PlanDay day) async {
    if (!AuthGuard.ensure(context, action: 'add places to a trip')) return;
    final label = area.isEmpty ? name : '$name — $area';
    final item = PlanItem(id: _uid(), text: label);
    setState(() => day.items.add(item));
    _persist();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added "$name" to ${day.title}')));
    try {
      final gp = await _api.geocode(area.isEmpty ? name : '$name, $area');
      if (!mounted) return;
      setState(() {
        item.lat = gp.lat;
        item.lng = gp.lng;
      });
      _persist();
    } catch (_) {}
  }

  Future<void> _promptAddItem() async {
    if (!AuthGuard.ensure(context, action: 'add places to a trip')) return;
    if (_days.isEmpty) _addDay();
    final item = await _editItemDialog();
    if (item != null && item.text.isNotEmpty) {
      final idx = _selectedDay.clamp(0, _days.length - 1);
      setState(() => _days[idx].items.add(item));
      _persist();
    }
  }

  /// Tap an existing item to edit its type/time/name/note (keeps its coords).
  Future<void> _editItem(PlanDay day, int index) async {
    final edited = await _editItemDialog(existing: day.items[index]);
    if (edited != null && edited.text.isNotEmpty) {
      setState(() => day.items[index] = edited);
      _persist();
    }
  }

  /// Horizontal selector for the day's mode of transport.
  Widget _transportRow(PlanDay day) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final m in _transportModes)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        setState(() => day.transportMode = m.$1);
                        _persist();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: day.transportMode == m.$1
                              ? AppColors.accentLight.withValues(alpha: 0.22)
                              : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                              color: day.transportMode == m.$1
                                  ? AppColors.accentLight
                                  : Colors.white.withValues(alpha: 0.15)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(m.$3, size: 15,
                              color: day.transportMode == m.$1 ? AppColors.accentLight : Voy.sub),
                          const SizedBox(width: 5),
                          Text(m.$2,
                              style: TextStyle(
                                  color: day.transportMode == m.$1 ? AppColors.accentLight : Voy.sub,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _transportDetail(day),
        ],
      ),
    );
  }

  /// Mode-specific detail: pick your own vehicle (car/bike), or add booking
  /// details (bus/train/flight). Combined shows both.
  Widget _transportDetail(PlanDay day) {
    final m = day.transportMode;
    final rows = <Widget>[];
    if (_isOwnVehicleMode(m) || m == 'combined') {
      final v = day.vehicleId == null
          ? null
          : predefinedVehicles.where((e) => e.id == day.vehicleId).cast<VehicleModel?>().firstWhere((_) => true, orElse: () => null);
      rows.add(_detailChip(
        icon: Icons.directions_car_filled_rounded,
        label: v != null ? '${v.name} · ${v.mileage.toStringAsFixed(0)} km/L' : 'Select your vehicle',
        set: v != null,
        onTap: () => _pickVehicle(day),
      ));
    }
    if (_isBookingMode(m)) {
      final b = day.booking;
      final has = b != null && !b.isEmpty;
      final summary = has
          ? [b.carrier, b.number, if (b.from.isNotEmpty || b.to.isNotEmpty) '${b.from}→${b.to}'].where((s) => s.isNotEmpty).join(' · ')
          : 'Add booking details';
      rows.add(_detailChip(
        icon: Icons.confirmation_number_rounded,
        label: summary.isEmpty ? 'Add booking details' : summary,
        set: has,
        onTap: () => _editBooking(day),
      ));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 8, runSpacing: 8, children: rows),
    );
  }

  Widget _detailChip({required IconData icon, required String label, required bool set, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: set ? AppColors.accent.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: set ? AppColors.accentLight.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: set ? AppColors.accentLight : Voy.sub),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: set ? Colors.white : Voy.sub, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 4),
          Icon(Icons.edit_rounded, size: 13, color: Voy.sub.withValues(alpha: 0.7)),
        ]),
      ),
    );
  }

  /// Choose the traveller's own vehicle for a car/bike/combined day.
  Future<void> _pickVehicle(PlanDay day) async {
    // Bikes show motorcycles; car & combined show cars (combined can still add a booking).
    final wantType = day.transportMode == 'bike' ? 'motorcycle' : 'car';
    // The user's saved account vehicles first, then the built-in list.
    final saved = (await _api.savedVehicles()).where((v) => v.type == wantType).toList();
    final list = [...saved, ...predefinedVehicles.where((v) => v.type == wantType)];
    final chosen = await showModalBottomSheet<VehicleModel>(
      context: context,
      backgroundColor: Voy.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(alignment: Alignment.centerLeft, child: Text('Select your vehicle', style: TextStyle(color: Voy.ink, fontSize: 16, fontWeight: FontWeight.w800))),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (c, i) {
                  final v = list[i];
                  final sel = v.id == day.vehicleId;
                  return ListTile(
                    leading: Icon(day.transportMode == 'bike' ? Icons.two_wheeler_rounded : Icons.directions_car_rounded, color: sel ? AppColors.accentLight : Voy.sub),
                    title: Text(v.name, style: const TextStyle(color: Voy.ink)),
                    subtitle: Text('${v.mileage.toStringAsFixed(0)} km/L · ${v.tankCapacity.toStringAsFixed(0)} L tank', style: const TextStyle(color: Voy.sub, fontSize: 12)),
                    trailing: sel ? const Icon(Icons.check_circle_rounded, color: AppColors.accentLight) : null,
                    onTap: () => Navigator.pop(ctx, v),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen != null) {
      setState(() => day.vehicleId = chosen.id);
      _persist();
    }
  }

  /// Enter/edit booking details for a bus/train/flight/combined day.
  Future<void> _editBooking(PlanDay day) async {
    final b = day.booking ?? TransportBooking();
    final carrier = TextEditingController(text: b.carrier);
    final number = TextEditingController(text: b.number);
    final from = TextEditingController(text: b.from);
    final to = TextEditingController(text: b.to);
    final seat = TextEditingController(text: b.seat);
    final pnr = TextEditingController(text: b.pnr);
    String depart = b.depart;
    String arrive = b.arrive;
    final mode = day.transportMode;
    final carrierLabel = mode == 'flight' ? 'Airline' : mode == 'train' ? 'Train name' : mode == 'bus' ? 'Bus operator' : 'Operator';
    final numberLabel = mode == 'flight' ? 'Flight no.' : mode == 'train' ? 'Train no.' : 'Service no.';

    Widget f(TextEditingController c, String label) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(controller: c, style: const TextStyle(color: Voy.ink), decoration: InputDecoration(labelText: label)),
        );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Widget timeBtn(String label, String value, void Function(String) onPick) => Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.schedule_rounded, size: 16),
                  label: Text(value.isEmpty ? label : '$label $value', overflow: TextOverflow.ellipsis),
                  onPressed: () async {
                    final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.now());
                    if (t != null) setLocal(() => onPick(t.format(ctx)));
                  },
                ),
              );
          return AlertDialog(
            title: Text('${mode[0].toUpperCase()}${mode.substring(1)} booking'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                f(carrier, carrierLabel),
                f(number, numberLabel),
                Row(children: [Expanded(child: f(from, 'From')), const SizedBox(width: 10), Expanded(child: f(to, 'To'))]),
                Row(children: [
                  timeBtn('Departs', depart, (v) => depart = v),
                  const SizedBox(width: 10),
                  timeBtn('Arrives', arrive, (v) => arrive = v),
                ]),
                const SizedBox(height: 10),
                Row(children: [Expanded(child: f(seat, 'Seat')), const SizedBox(width: 10), Expanded(child: f(pnr, 'PNR / ref'))]),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
            ],
          );
        },
      ),
    );
    if (saved == true) {
      setState(() {
        day.booking = TransportBooking(
          carrier: carrier.text.trim(), number: number.text.trim(),
          from: from.text.trim(), to: to.text.trim(),
          depart: depart, arrive: arrive,
          seat: seat.text.trim(), pnr: pnr.text.trim(),
        );
      });
      _persist();
    }
  }

  /// Add/edit dialog capturing category, time, name and note. Returns a new/edited
  /// PlanItem (with a fresh id when [existing] is null), or null if cancelled.
  Future<PlanItem?> _editItemDialog({PlanItem? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.text ?? '');
    final noteCtrl = TextEditingController(text: existing?.note ?? '');
    String category = existing?.category ?? 'place';
    String time = existing?.time ?? '';

    return showDialog<PlanItem>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Add to day' : 'Edit item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Type', style: TextStyle(color: Voy.sub, fontSize: 12.5)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final c in _itemCategories)
                    ChoiceChip(
                      label: Text(c.$2),
                      avatar: Icon(c.$3, size: 16,
                          color: category == c.$1 ? Colors.white : Voy.sub),
                      selected: category == c.$1,
                      selectedColor: AppColors.accent,
                      labelStyle: TextStyle(
                          color: category == c.$1 ? Colors.white : Voy.ink, fontSize: 12.5),
                      onSelected: (_) => setLocal(() => category = c.$1),
                    ),
                ]),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  style: const TextStyle(color: Voy.ink),
                  decoration: const InputDecoration(labelText: 'Name (place / restaurant / activity)'),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.schedule_rounded, size: 18),
                      label: Text(time.isEmpty ? 'Add time' : time),
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay.now(),
                        );
                        if (picked != null) {
                          setLocal(() => time = picked.format(ctx));
                        }
                      },
                    ),
                  ),
                  if (time.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18, color: Voy.sub),
                      onPressed: () => setLocal(() => time = ''),
                    ),
                ]),
                const SizedBox(height: 6),
                TextField(
                  controller: noteCtrl,
                  style: const TextStyle(color: Voy.ink),
                  decoration: const InputDecoration(labelText: 'Note (optional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(
                  ctx,
                  PlanItem(
                    id: existing?.id ?? _uid(),
                    text: name,
                    time: time,
                    note: noteCtrl.text.trim(),
                    lat: existing?.lat,
                    lng: existing?.lng,
                    category: category,
                  ),
                );
              },
              child: Text(existing == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  /// Share this plan for collaboration: creates a cloud copy (if not already
  /// shared), then shows the link + code and starts live sync.
  Future<void> _shareTrip() async {
    if (!AuthGuard.ensure(context, action: 'share & collaborate on trips')) return;
    try {
      if (_shared == null) {
        final s = await _collab.createSharedTrip(
          tripType: 'itinerary',
          name: widget.tripName,
          data: _dataPayload(),
        );
        if (!mounted) return;
        setState(() => _shared = s);
        _subscribeShared(s);
      }
      _showShareSheet(_shared!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Share failed: $e')));
      }
    }
  }

  void _showShareSheet(SharedTrip t) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Voy.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.groups_rounded, color: AppColors.accentLight),
              const SizedBox(width: 8),
              const Text('Collaborate on this trip', style: TextStyle(color: Voy.ink, fontSize: 16, fontWeight: FontWeight.w800)),
              const Spacer(),
              const Icon(Icons.circle, color: Color(0xFF22C55E), size: 10),
              const SizedBox(width: 5),
              const Text('Live', style: TextStyle(color: Color(0xFF22C55E), fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 6),
            const Text('Anyone with the link can view. Signed-in people who join can edit — changes sync live.',
                style: TextStyle(color: Voy.sub, fontSize: 12.5)),
            const SizedBox(height: 16),
            _copyRow(ctx, 'Join code', t.shareCode),
            const SizedBox(height: 10),
            _copyRow(ctx, 'Share link', t.shareUrl),
          ],
        ),
      ),
    );
  }

  Widget _copyRow(BuildContext ctx, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Voy.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: Voy.hairline)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: Voy.sub, fontSize: 11)),
            const SizedBox(height: 2),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Voy.ink, fontSize: 13.5, fontWeight: FontWeight.w600)),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.copy_rounded, color: AppColors.accentLight, size: 20),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Copied ✓'), duration: Duration(seconds: 1)));
          },
        ),
      ]),
    );
  }

  /// Join an existing shared trip by its code, replacing the current view.
  Future<void> _joinByCode() async {
    if (!AuthGuard.ensure(context, action: 'join a shared trip')) return;
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join a shared trip'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: Voy.ink),
          decoration: const InputDecoration(labelText: 'Share code'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Join')),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    try {
      final t = await _collab.joinByCode(code);
      if (t == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No trip found for that code.')));
        return;
      }
      if (!mounted) return;
      setState(() => _shared = t);
      _applyRemote(t.data);
      _subscribeShared(t);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Joined "${t.name}" ✓ — edits sync live')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Join failed: $e')));
    }
  }

  /// Play a visual "demo" of the saved trip: a marker travels through the
  /// itinerary's located stops. Geocodes any missing coordinates first (bounded).
  Future<void> _startDemo() async {
    if (_days.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add some days & places first.')));
      return;
    }
    final context0 = widget.tripName.replaceAll(RegExp(r'\s*\(.*\)\s*'), '').trim();
    final stops = <DemoStop>[];
    int geocodes = 0;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preparing demo…'), duration: Duration(seconds: 1)));
    for (int di = 0; di < _days.length; di++) {
      final day = _days[di];
      for (final it in day.items) {
        LatLng? p;
        if (it.hasCoords) {
          p = LatLng(it.lat!, it.lng!);
        } else if (geocodes < 15 && it.text.trim().isNotEmpty) {
          final q = _placeQueryFor(it) ?? it.text.trim();
          if (q.isNotEmpty) {
            geocodes++;
            try {
              GeoPoint? gp;
              try {
                gp = await _api.geocode(q);
              } catch (_) {
                if (context0.isNotEmpty && !q.contains(',')) {
                  try { gp = await _api.geocode('$q, $context0'); } catch (_) {}
                }
              }
              if (gp != null) {
                p = LatLng(gp.lat, gp.lng);
                it.lat = gp.lat; // cache back so future demos/map reuse it
                it.lng = gp.lng;
              }
            } catch (_) {}
          }
        }
        if (p != null) {
          stops.add(DemoStop(dayLabel: 'Day ${di + 1}', time: it.time, name: it.text, category: it.category, point: p));
        }
      }
    }
    if (geocodes > 0) _persist();
    if (!mounted) return;
    if (stops.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Need at least 2 locatable places for a demo — add places with locations.')),
      );
      return;
    }
    final demoName = context0.isEmpty ? widget.tripName : context0;
    // On the web, launch the richer GSAP-powered demo page (same origin); on
    // native, use the in-app Flutter demo.
    if (kIsWeb && gsapDemoSupported) {
      openGsapDemo(jsonEncode({
        'name': demoName,
        'stops': stops
            .map((s) => {
                  'day': s.dayLabel,
                  'time': s.time,
                  'name': s.name,
                  'category': s.category,
                  'lat': s.point.latitude,
                  'lng': s.point.longitude,
                })
            .toList(),
      }));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TripDemoScreen(stops: stops, tripName: demoName),
    ));
  }

  /// Open the smart AI planner (start date/time + timeline + auto breaks). Its
  /// "Use this plan" imports the result into a day planner.
  void _openSmartPlanner() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SmartItineraryScreen()),
    );
  }

  void _openGallery() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GalleryScreen(store: _store, tripName: widget.tripName),
    ));
  }

  /// Start (or resume) the trip: enter the live active-trip view focused on the
  /// current day's plan. Marks the trip as started on first launch.
  Future<void> _startTrip() async {
    if (_days.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add or generate a day first, then start the trip.')),
      );
      return;
    }
    _startedAt ??= DateTime.now();
    await _store.saveStartedAt(_startedAt);
    if (!mounted) return;
    final ended = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ActiveTripScreen(
        store: _store,
        days: _days,
        startedAt: _startedAt!,
        tripName: widget.tripName,
      ),
    ));
    if (!mounted) return;
    // Reflect any check-offs, additions, edits, and a possible "End trip".
    final refreshedDays = await _store.loadDays();
    if (ended == true) _startedAt = null;
    setState(() {
      _days = refreshedDays;
      if (_selectedDay >= _days.length) {
        _selectedDay = _days.isEmpty ? 0 : _days.length - 1;
      }
    });
  }

  /// Launch turn-by-turn driving navigation for the selected day. Uses the
  /// day's geocoded stops (in order) as the route and the day's chosen vehicle,
  /// then opens the full driving screen (map, voice guidance, car mode + the
  /// live trip-progress notification).
  /// Turn an itinerary line into a geocodable place query: strip leading verbs
  /// ("Drive to", "Visit"…) and generic activity words that aren't places.
  /// Turn an itinerary line into a geocodable place query: strip leading verbs
  /// ("Drive from", "Visit"…) and generic activity words that aren't places.
  String? _placeQueryFor(PlanItem it) {
    var t = it.text.trim();
    if (t.isEmpty) return null;

    // 1. Strip leading descriptive phrases / verbs / meal indicators
    final prefixPattern = RegExp(
      r'^(?:drive\s+(?:from|to|towards)|start\s+(?:from|at)|depart\s+(?:from)?|'
      r'travel\s+(?:to|from)|journey\s+(?:to|from)|head\s+(?:to|towards|from)|'
      r'reach|arrive\s+(?:at|in)?|arrival\s+(?:at|in)?|'
      r'visit|explore|tour|see|stop\s+at|'
      r'(?:arrival\s+)?(?:breakfast|lunch|dinner|brunch|snack|coffee|tea|meal)\s+(?:at|in)?|'
      r'(?:hotel\s+)?(?:check-?in|check-?out|stay|rest|night\s+rest|night\s+stay)\s+(?:at|in)?|'
      r'traditional\s+(?:dinner|lunch|breakfast)\s+(?:at|in)?|'
      r'relax\s+(?:at|in)?|spend\s+time\s+(?:at|in)?)\s+',
      caseSensitive: false,
    );
    t = t.replaceFirst(prefixPattern, '').trim();

    // 2. Strip any remaining prepositions at the start
    t = t.replaceFirst(RegExp(r'^(?:at|in|to|from)\s+', caseSensitive: false), '').trim();

    // 3. Remove parenthetical descriptions, e.g. "(Mysore)" or "(Stay)"
    t = t.replaceAll(RegExp(r'\(.*?\)'), '').trim();

    // 4. Strip surrounding punctuation
    t = t.replaceAll(RegExp(r'^[^\w]+|[^\w]+$'), '').trim();

    // 5. If it's a completely generic word with no place name, skip it
    final genericOnly = RegExp(
      r'^(?:lunch|dinner|breakfast|food|meal|rest|hotel|stay|break|free time|night|home)$',
      caseSensitive: false,
    );
    if (genericOnly.hasMatch(t)) return null;

    return t.isEmpty ? null : t;
  }

  Future<void> _startNavigation() async {
    if (_days.isEmpty) return;
    final day = _days[_selectedDay.clamp(0, _days.length - 1)];
    setState(() => _navLoading = true);

    // Collect route stops in order. Use existing coords; geocode the rest
    // on-demand (AI itinerary items usually aren't geocoded yet).
    final stops = <GeoPoint>[];
    try {
      // Trip context to disambiguate short names (e.g. "to Tirupati").
      final ctx = _journeyEndpoints();
      // Anchor on the trip destination: used to bias every stop's geocode so
      // "Lunch at Ooty" can't resolve to a same-named place on another continent.
      GeoPoint? anchor;
      if (ctx.to.isNotEmpty) {
        try {
          anchor = await _api.geocode(ctx.to);
        } catch (_) {}
      }
      // A cached coordinate is suspect when the item's own text names the trip
      // destination yet its coords sit far from it — stale results saved while
      // geocoding was unbiased (e.g. "Night Rest at Ooty…" pinned in
      // Bengaluru). Those are re-geocoded instead of trusted.
      final destToken = ctx.to.split(',').first.trim().toLowerCase();
      bool suspectCoords(PlanItem it) {
        if (anchor == null || destToken.length < 3 || !it.hasCoords) return false;
        if (!it.text.toLowerCase().contains(destToken)) return false;
        return _haversineKm(it.lat!, it.lng!, anchor.lat, anchor.lng) > 60;
      }

      for (final it in day.items) {
        if (it.hasCoords && !suspectCoords(it)) {
          stops.add(GeoPoint(lat: it.lat!, lng: it.lng!, name: it.text));
          continue;
        }
        final q = _placeQueryFor(it) ?? it.text.trim();
        if (q.isEmpty) continue;
        try {
          GeoPoint? gp;
          // 1. Prefer the context-qualified query for bare place names — a raw
          //    "Botanical Garden" matches worldwide; "…, Ooty" pins it down.
          final contextual =
              (!q.contains(',') && ctx.to.isNotEmpty) ? '$q, ${ctx.to}' : null;
          try {
            gp = await _api.geocode(contextual ?? q, near: anchor);
          } catch (_) {
            // 2. Contextual found nothing — retry the bare query.
            if (contextual != null) {
              try {
                gp = await _api.geocode(q, near: anchor);
              } catch (_) {}
            }
          }
          // A destination-named stop that STILL resolves far from the anchor is
          // the geocoder mistaking a homonym — snap it to the destination town
          // rather than sending the route to the wrong city.
          if (gp != null &&
              anchor != null &&
              destToken.length >= 3 &&
              it.text.toLowerCase().contains(destToken) &&
              _haversineKm(gp.lat, gp.lng, anchor.lat, anchor.lng) > 60) {
            gp = anchor;
          }
          if (gp != null) {
            it.lat = gp.lat;
            it.lng = gp.lng;
            stops.add(GeoPoint(lat: gp.lat, lng: gp.lng, name: it.text));
          }
        } catch (_) {/* couldn't locate this one — skip it */}
      }

      // Guard against bad (often previously cached) geocodes: a day's driving
      // route can't span continents, so keep only the largest group of stops
      // that lie within 500 km of each other and drop far-flung outliers.
      if (stops.length >= 3) {
        var best = <GeoPoint>[];
        for (final a in stops) {
          final cluster = stops
              .where((s) => _haversineKm(a.lat, a.lng, s.lat, s.lng) <= 500)
              .toList();
          if (cluster.length > best.length) best = cluster;
        }
        if (best.length >= 2 && best.length < stops.length) {
          stops
            ..clear()
            ..addAll(best);
        }
      }

      // If we only located 1 stop, try using journey origin (ctx.from) or destination (ctx.to)
      if (stops.length == 1) {
        if (ctx.from.isNotEmpty && stops.first.name != ctx.from) {
          try {
            final startGp = await _api.geocode(ctx.from);
            stops.insert(0, startGp);
          } catch (_) {}
        }
        if (stops.length == 1 && ctx.to.isNotEmpty && stops.first.name != ctx.to) {
          try {
            final endGp = await _api.geocode(ctx.to);
            stops.add(endGp);
          } catch (_) {}
        }
      }

      // Cache the freshly geocoded coords.
      await _store.saveDays(_days, name: widget.tripName);
    } catch (_) {/* fall through to the count check */}

    // Deduplicate consecutive identical/super-close points (>50m away)
    final distinctStops = <GeoPoint>[];
    for (final s in stops) {
      if (distinctStops.isEmpty) {
        distinctStops.add(s);
      } else {
        final prev = distinctStops.last;
        final distKm = _haversineKm(prev.lat, prev.lng, s.lat, s.lng);
        if (distKm > 0.05) {
          distinctStops.add(s);
        }
      }
    }

    if (distinctStops.length >= 2) {
      stops.clear();
      stops.addAll(distinctStops);
    }

    if (stops.length < 2) {
      if (mounted) {
        setState(() => _navLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
              "Couldn't locate enough stops to navigate. Add place names to at least 2 stops and try again.")),
        );
      }
      return;
    }

    // Build the driving vehicle from the day's selection (fall back to a car).
    final vm = day.vehicleId == null
        ? null
        : predefinedVehicles
            .where((e) => e.id == day.vehicleId)
            .cast<VehicleModel?>()
            .firstWhere((_) => true, orElse: () => null);
    final vehicle = Vehicle(
      type: vm?.type ?? 'car',
      efficiencyKmPerLiter: vm?.mileage ?? 15,
      tankCapacityLiters: vm?.tankCapacity ?? 40,
      currentFuelLiters: vm?.tankCapacity ?? 40,
    );

    final start = stops.first;
    final end = stops.last;
    final waypoints = stops.sublist(1, stops.length - 1);

    setState(() => _navLoading = true);
    try {
      final plan = await _api.planTrip(start: start, end: end, waypoints: waypoints, vehicle: vehicle);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TripScreen(
          plan: plan,
          startAddress: start.name ?? 'Start',
          endAddress: end.name ?? 'Destination',
          vehicleType: vehicle.type,
          poiCategories: const [],
          start: start,
          end: end,
          waypoints: waypoints,
          vehicle: vehicle,
        ),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start navigation: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _navLoading = false);
    }
  }

  /// Origin/destination for this journey, used for booking suggestions.
  /// Looks for a "from X to Y" phrase in the trip name or any AI day title
  /// (e.g. "Journey from Mandya to New York City"), then an "A → B" trip name,
  /// then falls back to the trip name as the destination.
  ({String from, String to}) _journeyEndpoints() {
    String clean(String s) => s.replaceAll(RegExp(r'\(.*\)'), '').trim();
    final candidates = <String>[widget.tripName, for (final d in _days) d.title];
    final fromTo = RegExp(r'from\s+(.+?)\s+to\s+(.+)', caseSensitive: false);
    for (final s in candidates) {
      final m = fromTo.firstMatch(s);
      if (m != null) return (from: clean(m.group(1)!), to: clean(m.group(2)!));
    }
    final parts = widget.tripName.split(RegExp(r'\s*(?:→|->)\s*'));
    if (parts.length >= 2) return (from: clean(parts.first), to: clean(parts[1]));
    return (from: '', to: clean(widget.tripName));
  }

  Future<void> _renameDay(PlanDay day) async {
    final ctrl = TextEditingController(text: day.title);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename day'),
        content: TextField(controller: ctrl, autofocus: true, style: const TextStyle(color: Voy.ink), decoration: const InputDecoration(labelText: 'Title')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (text != null && text.isNotEmpty) {
      setState(() => day.title = text);
      _persist();
    }
  }

  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    double toRad(double d) => d * math.pi / 180.0;
    final dLat = toRad(lat2 - lat1), dLng = toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(toRad(lat1)) * math.cos(toRad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Approx travel leg between two consecutive stops (straight-line distance and
  /// a rough time at the day's chosen transport speed).
  String _legLabel(PlanItem a, PlanItem b, double speedKmh) {
    final km = _haversineKm(a.lat!, a.lng!, b.lat!, b.lng!);
    final mins = (km / (speedKmh <= 0 ? 40 : speedKmh) * 60).round();
    final kmStr = km < 10 ? km.toStringAsFixed(1) : km.toStringAsFixed(0);
    return '≈ $kmStr km · ${mins < 1 ? 1 : mins} min';
  }

  /// Real road leg if we have it (OSRM), otherwise a straight-line estimate at
  /// the day's transport speed while the real value is fetched in the background.
  String _legDisplay(PlanItem a, PlanItem b, double speedKmh) {
    final key = '${a.id}>${b.id}';
    final real = _legCache[key];
    if (real != null) return real;
    _ensureLeg(a, b);
    return '${_legLabel(a, b, speedKmh)} (approx)';
  }

  /// Reorders a day's geocoded stops for the shortest path (nearest-neighbour),
  /// keeping any non-geocoded items at the end.
  void _optimizeDay(PlanDay day) {
    final geo = day.items.where((i) => i.hasCoords).toList();
    final rest = day.items.where((i) => !i.hasCoords).toList();
    if (geo.length < 3) return;
    final ordered = <PlanItem>[];
    final remaining = [...geo];
    var current = remaining.removeAt(0);
    ordered.add(current);
    while (remaining.isNotEmpty) {
      remaining.sort((p, q) => _haversineKm(current.lat!, current.lng!, p.lat!, p.lng!)
          .compareTo(_haversineKm(current.lat!, current.lng!, q.lat!, q.lng!)));
      current = remaining.removeAt(0);
      ordered.add(current);
    }
    setState(() => day.items = [...ordered, ...rest]);
    _persist();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Day optimised for the shortest path ✓')));
  }

  Future<void> _exportPdf() async {
    if (_days.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add some days first.')));
      return;
    }
    try {
      await exportPlanPdf(widget.tripName, _days);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF export failed: $e')));
    }
  }

  Future<void> _exportIcs() async {
    if (_days.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add some days first.')));
      return;
    }
    try {
      await exportPlanIcs(widget.tripName, _days);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Calendar export failed: $e')));
    }
  }

  Future<void> _import() async {
    try {
      final res = await FilePicker.pickFiles(withData: true, type: FileType.any);
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      final bytes = f.bytes;
      if (bytes == null) return;
      final content = utf8.decode(bytes, allowMalformed: true);
      final places = parseImportedPlaces(f.name, content);
      if (places.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No places found in that file.')));
        return;
      }
      final day = PlanDay(id: _uid(), title: 'Imported (${places.length})');
      for (final p in places) {
        day.items.add(PlanItem(id: '${_uid()}${day.items.length}', text: p.name, lat: p.lat, lng: p.lng));
      }
      setState(() {
        _days.add(day);
        _selectedDay = _days.length - 1;
      });
      _persist();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported ${places.length} places')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  String _wxIcon(int? code) {
    final c = code ?? 0;
    if (c == 0) return '☀️';
    if (c <= 3) return '⛅';
    if (c <= 48) return '🌫️';
    if (c <= 67) return '🌧️';
    if (c <= 77) return '🌨️';
    if (c <= 82) return '🌧️';
    if (c <= 99) return '⛈️';
    return '☁️';
  }

  /// Fetches current weather for a day's first geocoded stop (Open-Meteo, free).
  Future<void> _ensureWeather(PlanDay day) async {
    if (_weatherCache.containsKey(day.id) || _weatherPending.contains(day.id)) return;
    PlanItem? loc;
    for (final it in day.items) {
      if (it.hasCoords) {
        loc = it;
        break;
      }
    }
    if (loc == null) return;
    _weatherPending.add(day.id);
    try {
      final uri = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=${loc.lat}&longitude=${loc.lng}&current=temperature_2m,weather_code');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final m = jsonDecode(res.body) as Map<String, dynamic>;
        final cur = m['current'] as Map<String, dynamic>?;
        final t = (cur?['temperature_2m'] as num?)?.round();
        final code = (cur?['weather_code'] as num?)?.toInt();
        if (t != null && mounted) {
          setState(() => _weatherCache[day.id] = '$t° ${_wxIcon(code)}');
        }
      }
    } catch (_) {
    } finally {
      _weatherPending.remove(day.id);
    }
  }

  /// Fetches the real driving distance/time between two stops (OSRM, free).
  Future<void> _ensureLeg(PlanItem a, PlanItem b) async {
    final key = '${a.id}>${b.id}';
    if (_legCache.containsKey(key) || _legPending.contains(key)) return;
    _legPending.add(key);
    try {
      final uri = Uri.parse(
          'https://router.project-osrm.org/route/v1/driving/${a.lng},${a.lat};${b.lng},${b.lat}?overview=false');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final m = jsonDecode(res.body) as Map<String, dynamic>;
        final routes = m['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final km = (routes[0]['distance'] as num) / 1000.0;
          final mins = ((routes[0]['duration'] as num) / 60).round();
          final label = '${km < 10 ? km.toStringAsFixed(1) : km.toStringAsFixed(0)} km · ${mins < 1 ? 1 : mins} min';
          if (mounted) setState(() => _legCache[key] = label);
        }
      }
    } catch (_) {
    } finally {
      _legPending.remove(key);
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Trip Planner', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
            Text(widget.tripName, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Smart AI planner', icon: const Icon(Icons.auto_awesome, color: AppColors.accentLight), onPressed: _openSmartPlanner),
          IconButton(tooltip: 'Travel gallery (photos)', icon: const Icon(Icons.photo_library_outlined, color: Colors.white), onPressed: _openGallery),
          IconButton(tooltip: 'Demo / preview trip', icon: const Icon(Icons.play_circle_outline_rounded, color: Colors.white), onPressed: _startDemo),
          IconButton(tooltip: 'Share & collaborate', icon: const Icon(Icons.group_add_rounded, color: Colors.white), onPressed: _shareTrip),
          IconButton(tooltip: 'Join a shared trip', icon: const Icon(Icons.login_rounded, color: Colors.white), onPressed: _joinByCode),
          IconButton(tooltip: 'Import places', icon: const Icon(Icons.file_upload_outlined, color: Colors.white), onPressed: _import),
          IconButton(tooltip: 'Export PDF', icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white), onPressed: _exportPdf),
          IconButton(tooltip: 'Add to calendar (.ics)', icon: const Icon(Icons.event_outlined, color: Colors.white), onPressed: _exportIcs),
          const SizedBox(width: 4),
        ],
      ),
      body: AnimatedBackground(
        imageUrl: _bgUrl,
        overlayOpacity: 0.62,
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, c) {
                    final wide = c.maxWidth >= 900;
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 340, child: _daysPanel()),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
                              child: GlassCard(
                                padding: const EdgeInsets.all(6),
                                child: ClipRRect(borderRadius: BorderRadius.circular(18), child: _map()),
                              ),
                            ),
                          ),
                          SizedBox(width: 340, child: _placesPanel()),
                        ],
                      );
                    }
                    return Scaffold(
                      backgroundColor: Colors.transparent,
                      floatingActionButton: FloatingActionButton.extended(
                        onPressed: _openPlacesSheet,
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        icon: const Icon(Icons.add_location_alt_rounded),
                        label: const Text('Add place'),
                      ),
                      body: _daysPanel(),
                    );
                  },
                ),
        ),
      ),
    );
  }

  void _openPlacesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Voy.surface,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => _placesPanel(scrollController: scroll),
      ),
    );
  }

  // ---- map ----
  Widget _map() {
    final day = _days.isEmpty ? null : _days[_selectedDay.clamp(0, _days.length - 1)];
    final pins = <Marker>[];
    final pts = <LatLng>[];
    if (day != null) {
      int n = 0;
      for (final it in day.items) {
        n++;
        if (!it.hasCoords) continue;
        final p = LatLng(it.lat!, it.lng!);
        pts.add(p);
        final label = n;
        pins.add(Marker(
          point: p,
          width: 30,
          height: 30,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Voy.violet,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 6)],
            ),
            child: Text('$label', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
        ));
      }
    }
    final token = AppConfig.mapboxToken;
    final tileUrl = token.isNotEmpty
        ? 'https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/tiles/256/{z}/{x}/{y}?access_token=$token'
        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    return FlutterMap(
      options: MapOptions(
        initialCameraFit: pts.length > 1 ? CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.all(48)) : null,
        initialCenter: pts.isNotEmpty ? pts.first : const LatLng(20.5937, 78.9629),
        initialZoom: pts.length == 1 ? 12 : 5,
      ),
      children: [
        TileLayer(urlTemplate: tileUrl, userAgentPackageName: 'com.example.travel_app', additionalOptions: {'accessToken': token}),
        MarkerLayer(markers: pins),
      ],
    );
  }

  // ---- days ----
  Widget _daysPanel() {
    if (_days.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_day_rounded, size: 54, color: Colors.white.withValues(alpha: 0.4)),
            const SizedBox(height: 14),
            const Text('Plan your days', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Let AI draft a full itinerary, or build it yourself.', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
            const SizedBox(height: 16),
            SizedBox(
              width: 220,
              child: AccentButton(
                onPressed: _openSmartPlanner,
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.auto_awesome, size: 18, color: Colors.white),
                  SizedBox(width: 8),
                  Text('BUILD WITH AI'),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _addDay,
              icon: const Icon(Icons.add_rounded, size: 18, color: AppColors.accentLight),
              label: const Text('Add a day manually', style: TextStyle(color: AppColors.accentLight)),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        // Start / resume the live active-trip view.
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _startTrip,
            icon: Icon(_startedAt == null ? Icons.play_arrow_rounded : Icons.navigation_rounded, size: 20),
            label: Text(_startedAt == null ? 'START TRIP' : 'RESUME ACTIVE TRIP',
                style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF34D27B),
              foregroundColor: const Color(0xFF04211F),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Turn-by-turn driving navigation for the selected day's route.
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _navLoading ? null : _startNavigation,
            icon: _navLoading
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)))
                : const Icon(Icons.navigation_rounded, size: 20, color: Color(0xFF38BDF8)),
            label: Text(_navLoading ? 'Building route…' : 'START NAVIGATION (DRIVING)',
                style: const TextStyle(color: Color(0xFF7DD3FC), fontWeight: FontWeight.w800, letterSpacing: 0.5)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF38BDF8), width: 1.4),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _dayChipRow(),
        const SizedBox(height: 4),
        ...RevealIn.stagger(
          [for (int di = 0; di < _days.length; di++) _dayCard(di)],
          initial: const Duration(milliseconds: 60),
          step: const Duration(milliseconds: 50),
        ),
        const SizedBox(height: 4),
        AccentButton(
          onPressed: _addDay,
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.add_rounded, size: 18, color: Colors.white),
            SizedBox(width: 6),
            Text('ADD DAY'),
          ]),
        ),
      ],
    );
  }

  /// Horizontal filter-chip row to jump between days (trek-tool chip pattern).
  Widget _dayChipRow() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 2),
        itemCount: _days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final selected = i == _selectedDay;
          return GestureDetector(
            onTap: () => setState(() => _selectedDay = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: selected ? AppColors.accentLight.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: selected ? AppColors.accentLight : Colors.white.withValues(alpha: 0.15),
                    width: selected ? 1.4 : 1),
              ),
              child: Text('Day ${i + 1}',
                  style: TextStyle(
                      color: selected ? AppColors.accentLight : Colors.white.withValues(alpha: 0.8),
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
            ),
          );
        },
      ),
    );
  }

  Widget _dayCard(int di) {
    final day = _days[di];
    final selected = di == _selectedDay;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassCard(
        padding: EdgeInsets.zero,
        glow: selected,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: selected ? AppColors.accentLight : Colors.transparent,
                width: selected ? 1.4 : 0),
          ),
          child: InkWell(
            onTap: () => setState(() => _selectedDay = di),
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: AppColors.accentLight.withValues(alpha: selected ? 0.28 : 0.16), borderRadius: BorderRadius.circular(9)),
                        child: Text('${di + 1}', style: const TextStyle(color: AppColors.accentLight, fontWeight: FontWeight.w800)),
                      ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(day.title, style: const TextStyle(color: Voy.ink, fontSize: 16, fontWeight: FontWeight.w700))),
                  _weatherBadge(day),
                  if (selected)
                    const Padding(padding: EdgeInsets.only(right: 4), child: Text('adding here', style: TextStyle(color: Voy.brand, fontSize: 10.5, fontWeight: FontWeight.w800))),
                  if (day.items.where((i) => i.hasCoords).length >= 3)
                    IconButton(
                      icon: const Icon(Icons.auto_fix_high_rounded, color: Color(0xFF60A5FA), size: 18),
                      tooltip: 'Optimise order',
                      onPressed: () => _optimizeDay(day),
                    ),
                  IconButton(icon: const Icon(Icons.edit_rounded, color: Voy.sub, size: 18), onPressed: () => _renameDay(day)),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Voy.danger, size: 20),
                    onPressed: () {
                      setState(() {
                        _days.removeAt(di);
                        if (_selectedDay >= _days.length) _selectedDay = _days.isEmpty ? 0 : _days.length - 1;
                      });
                      _persist();
                    },
                  ),
                ],
              ),
              _hotelRow(day),
              _transportRow(day),
              if (day.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 0, 6),
                  child: Text('No items yet — search & add places, or type your own.', style: TextStyle(color: Voy.sub.withValues(alpha: 0.8), fontSize: 12.5)),
                )
              else
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorder: (oldI, newI) {
                    setState(() {
                      if (newI > oldI) newI -= 1;
                      final it = day.items.removeAt(oldI);
                      day.items.insert(newI, it);
                    });
                    _persist();
                  },
                  children: [
                    for (int ii = 0; ii < day.items.length; ii++)
                      Column(
                        key: ValueKey(day.items[ii].id),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.only(left: 0, right: 0),
                            horizontalTitleGap: 8,
                            minLeadingWidth: 0,
                            onTap: () => _editItem(day, ii),
                            leading: ReorderableDragStartListener(index: ii, child: const Icon(Icons.drag_indicator_rounded, color: Voy.sub, size: 18)),
                            title: Row(
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(color: day.items[ii].hasCoords ? Voy.violet : Voy.surface2, shape: BoxShape.circle),
                                  child: Text('${ii + 1}', style: TextStyle(color: day.items[ii].hasCoords ? Colors.white : Voy.sub, fontSize: 11, fontWeight: FontWeight.w800)),
                                ),
                                const SizedBox(width: 8),
                                Icon(_categoryIcon(day.items[ii].category), size: 15, color: AppColors.accentLight),
                                const SizedBox(width: 6),
                                Expanded(child: Text(day.items[ii].text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Voy.ink, fontSize: 14))),
                                if (day.items[ii].time.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.accent.withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(day.items[ii].time,
                                        style: const TextStyle(color: AppColors.accentLight, fontSize: 11, fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ],
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.close_rounded, color: Voy.sub, size: 18),
                              onPressed: () {
                                setState(() => day.items.removeAt(ii));
                                _persist();
                              },
                            ),
                          ),
                          // Travel leg to the next stop (both must be geocoded).
                          if (ii < day.items.length - 1 && day.items[ii].hasCoords && day.items[ii + 1].hasCoords)
                            Padding(
                              padding: const EdgeInsets.only(left: 30, bottom: 4),
                              child: Row(
                                children: [
                                  Icon(Icons.arrow_downward_rounded, size: 13, color: Voy.sub.withValues(alpha: 0.7)),
                                  const SizedBox(width: 6),
                                  Text(_legDisplay(day.items[ii], day.items[ii + 1], _transportSpeed(day.transportMode)),
                                      style: TextStyle(color: Voy.sub.withValues(alpha: 0.9), fontSize: 11.5, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() => _selectedDay = di);
                    _promptAddItem();
                  },
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add item'),
                ),
              ),
            ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _weatherBadge(PlanDay day) {
    _ensureWeather(day);
    final w = _weatherCache[day.id];
    if (w == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Text(w, style: const TextStyle(color: Voy.ink, fontSize: 13, fontWeight: FontWeight.w700)),
    );
  }

  Widget _hotelRow(PlanDay day) {
    return InkWell(
      onTap: () => _editHotel(day),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            Icon(Icons.hotel_rounded, size: 16, color: Voy.sub.withValues(alpha: 0.9)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                day.hotel.isEmpty ? 'Add stay / accommodation' : day.hotel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: day.hotel.isEmpty ? Voy.sub.withValues(alpha: 0.8) : Voy.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
            Icon(Icons.edit_rounded, size: 14, color: Voy.sub.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }

  Future<void> _editHotel(PlanDay day) async {
    final ctrl = TextEditingController(text: day.hotel);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stay for this day'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Voy.ink),
          decoration: const InputDecoration(labelText: 'Hotel / accommodation'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (text != null) {
      setState(() => day.hotel = text);
      _persist();
    }
  }

  // ---- places ----
  Widget _placesPanel({ScrollController? scrollController}) {
    final targetDay = _days.isEmpty ? null : _days[_selectedDay.clamp(0, _days.length - 1)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Add place / activity', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.accentLight.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('AUTO-SUGGEST', style: TextStyle(color: AppColors.accentLight, fontSize: 9.5, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(targetDay == null ? 'Add a day first' : 'Adding to ${targetDay.title}', style: const TextStyle(color: AppColors.accentLight, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white),
                  textInputAction: TextInputAction.search,
                  onChanged: _onSearchChanged,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: 'Search places, beaches, temples, food…',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withValues(alpha: 0.7)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                    ),
                    suffixIcon: _searching
                        ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                        : (_searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, color: Colors.white60, size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  _loadSuggestions();
                                },
                              )
                            : IconButton(icon: const Icon(Icons.arrow_forward_rounded, color: AppColors.accentLight), onPressed: _search)),
                  ),
                ),
                const SizedBox(height: 10),
                // Category Filter Chips for instant Autofill
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final cat in _quickCategories) ...[
                        GestureDetector(
                          onTap: () {
                            setState(() => _activeCategoryFilter = cat);
                            if (_searchCtrl.text.trim().isNotEmpty) {
                              _search();
                            } else {
                              _loadSuggestions();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: _activeCategoryFilter == cat
                                  ? AppColors.accentLight.withValues(alpha: 0.25)
                                  : Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _activeCategoryFilter == cat
                                    ? AppColors.accentLight
                                    : Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Text(
                              cat,
                              style: TextStyle(
                                color: _activeCategoryFilter == cat ? Colors.white : Colors.white70,
                                fontSize: 11.5,
                                fontWeight: _activeCategoryFilter == cat ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  TextButton.icon(onPressed: _promptAddItem, icon: const Icon(Icons.edit_rounded, size: 16, color: AppColors.accentLight), label: const Text('Add your own', style: TextStyle(color: AppColors.accentLight))),
                  const Spacer(),
                  TextButton.icon(onPressed: _openGallery, icon: const Icon(Icons.photo_library_rounded, size: 16, color: AppColors.accentLight), label: const Text('Gallery', style: TextStyle(color: AppColors.accentLight))),
                ]),
              ],
            ),
          ),
        ),
        if (_searchError != null)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Text(_searchError!, style: const TextStyle(color: Color(0xFFFB7185), fontSize: 12.5))),
        // Inline bookings column: saved reservations + AI flight/train/hotel
        // suggestions for this journey (bounded so it shares the panel height).
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: GlassCard(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Builder(builder: (_) {
                  final ep = _journeyEndpoints();
                  return BookingsScreen(
                    store: _store,
                    fromName: ep.from,
                    toName: ep.to,
                    travellers: 2,
                    embedded: true,
                  );
                }),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text(
                _searchCtrl.text.trim().isEmpty ? 'SUGGESTED PLACES & ACTIVITIES' : 'SEARCH RESULTS (${_results.length})',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              Text(
                'Tap + to add',
                style: TextStyle(color: AppColors.accentLight.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        Expanded(
          child: _results.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(_searching ? 'Searching places…' : 'No places found. Tap "Add your own" above to add any place.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
                  ),
                )
              : ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                  itemCount: _results.length,
                  itemBuilder: (ctx, i) {
                    final r = _results[i];
                    final name = r['name'] ?? '';
                    final area = r['area'] ?? '';
                    final why = r['why'] ?? '';

                    IconData placeIcon = Icons.place_rounded;
                    Color iconColor = AppColors.accentLight;
                    final lowerName = name.toLowerCase();
                    if (lowerName.contains('temple') || lowerName.contains('darshan') || lowerName.contains('shrine')) {
                      placeIcon = Icons.temple_hindu_rounded;
                      iconColor = const Color(0xFFF59E0B);
                    } else if (lowerName.contains('beach') || lowerName.contains('coast')) {
                      placeIcon = Icons.beach_access_rounded;
                      iconColor = const Color(0xFF38BDF8);
                    } else if (lowerName.contains('view') || lowerName.contains('peak') || lowerName.contains('hill')) {
                      placeIcon = Icons.landscape_rounded;
                      iconColor = const Color(0xFF10B981);
                    } else if (lowerName.contains('fort') || lowerName.contains('palace')) {
                      placeIcon = Icons.castle_rounded;
                      iconColor = const Color(0xFFA855F7);
                    } else if (lowerName.contains('waterfall') || lowerName.contains('falls') || lowerName.contains('lake') || lowerName.contains('river')) {
                      placeIcon = Icons.water_rounded;
                      iconColor = const Color(0xFF06B6D4);
                    } else if (lowerName.contains('thali') || lowerName.contains('lunch') || lowerName.contains('food') || lowerName.contains('dining')) {
                      placeIcon = Icons.restaurant_rounded;
                      iconColor = const Color(0xFFEF4444);
                    } else if (lowerName.contains('safari') || lowerName.contains('zoo') || lowerName.contains('elephant')) {
                      placeIcon = Icons.pets_rounded;
                      iconColor = const Color(0xFF84CC16);
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: GlassCard(
                        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                        glow: false,
                        child: InkWell(
                          onTap: targetDay == null ? null : () => _addSearchedPlace(name, area, targetDay),
                          borderRadius: BorderRadius.circular(12),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: iconColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(placeIcon, size: 18, color: iconColor),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5)),
                                    if (!(area.isEmpty && why.isEmpty))
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          [area, why].where((s) => s.isNotEmpty).join(' · '),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11.5),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_rounded, color: AppColors.accentLight, size: 24),
                                onPressed: targetDay == null ? null : () => _addSearchedPlace(name, area, targetDay),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
