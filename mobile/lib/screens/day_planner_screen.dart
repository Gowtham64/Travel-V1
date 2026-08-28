import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/app_config.dart';
import '../theme/app_theme.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, RealtimeChannel;
import '../widgets/app_design.dart';
import '../services/collab_service.dart';
import 'smart_itinerary_screen.dart';
import 'package:file_picker/file_picker.dart';
import '../models/trip_extras.dart';
import '../services/trip_extras_store.dart';
import '../services/api_service.dart';
import '../utils/plan_export.dart';

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
  ];

  // Item categories (id, label, icon).
  static const List<(String, String, IconData)> _itemCategories = [
    ('place', 'Place', Icons.place_rounded),
    ('restaurant', 'Restaurant', Icons.restaurant_rounded),
    ('stay', 'Stay', Icons.hotel_rounded),
    ('activity', 'Activity', Icons.local_activity_rounded),
  ];

  IconData _transportIcon(String id) =>
      _transportModes.firstWhere((m) => m.$1 == id, orElse: () => _transportModes.first).$3;
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
  bool _loading = true;

  List<Map<String, String>> _results = [];
  bool _searching = false;
  String? _searchError;

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
    _searchCtrl.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    final days = await _store.loadDays();
    if (!mounted) return;
    setState(() {
      _days = days;
      _loading = false;
    });
  }

  void _persist() {
    _store.saveDays(_days);
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
    _store.saveDays(_days); // cache locally, but DON'T re-push
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
    setState(() {
      _days.add(PlanDay(id: _uid(), title: 'Day ${_days.length + 1}'));
      _selectedDay = _days.length - 1;
    });
    _persist();
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final res = await _api.aiSearchPlaces(query: q);
      if (!mounted) return;
      setState(() => _results = res);
    } catch (e) {
      if (!mounted) return;
      setState(() => _searchError = e is ApiException ? e.message : 'Search failed. Try again.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _addSearchedPlace(String name, String area, PlanDay day) async {
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
      child: SizedBox(
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
    );
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
    if (!_collab.isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to share and collaborate on trips.')),
      );
      return;
    }
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
    if (!_collab.isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in to join a shared trip.')));
      return;
    }
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

  /// Open the smart AI planner (start date/time + timeline + auto breaks). Its
  /// "Use this plan" imports the result into a day planner.
  void _openSmartPlanner() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SmartItineraryScreen()),
    );
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
                const Text('Add place / activity', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(targetDay == null ? 'Add a day first' : 'Adding to ${targetDay.title}', style: const TextStyle(color: AppColors.accentLight, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: 'Search places (AI)…',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
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
                        : IconButton(icon: const Icon(Icons.arrow_forward_rounded, color: AppColors.accentLight), onPressed: _search),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(onPressed: _promptAddItem, icon: const Icon(Icons.edit_rounded, size: 16, color: AppColors.accentLight), label: const Text('Add your own', style: TextStyle(color: AppColors.accentLight))),
                ),
              ],
            ),
          ),
        ),
        if (_searchError != null)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(_searchError!, style: const TextStyle(color: Color(0xFFFB7185), fontSize: 12.5))),
        Expanded(
          child: _results.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(_searching ? 'Searching…' : 'Search for attractions, food, stays…', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
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
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: GlassCard(
                        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                        glow: false,
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                  if (!(area.isEmpty && (r['why'] ?? '').isEmpty))
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text([area, r['why'] ?? ''].where((s) => s.isNotEmpty).join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_rounded, color: AppColors.accentLight),
                              onPressed: targetDay == null ? null : () => _addSearchedPlace(name, area, targetDay),
                            ),
                          ],
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
