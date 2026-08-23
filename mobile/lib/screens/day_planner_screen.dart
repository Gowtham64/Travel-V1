import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/app_config.dart';
import '../theme/app_theme.dart';
import '../models/trip_extras.dart';
import '../services/trip_extras_store.dart';
import '../services/api_service.dart';

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
  late final TripExtrasStore _store = TripExtrasStore(widget.tripKey);
  final _api = ApiService();
  final _searchCtrl = TextEditingController();

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

  void _persist() => _store.saveDays(_days);

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
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add item'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Voy.ink),
          decoration: const InputDecoration(labelText: 'Place or activity'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    if (text != null && text.isNotEmpty) {
      final idx = _selectedDay.clamp(0, _days.length - 1);
      setState(() => _days[idx].items.add(PlanItem(id: _uid(), text: text)));
      _persist();
    }
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
  /// a rough drive time at ~40 km/h).
  String _legLabel(PlanItem a, PlanItem b) {
    final km = _haversineKm(a.lat!, a.lng!, b.lat!, b.lng!);
    final mins = (km / 40 * 60).round();
    final kmStr = km < 10 ? km.toStringAsFixed(1) : km.toStringAsFixed(0);
    return '≈ $kmStr km · ${mins < 1 ? 1 : mins} min';
  }

  /// Real road leg if we have it (OSRM), otherwise a straight-line estimate
  /// while the real value is fetched in the background.
  String _legDisplay(PlanItem a, PlanItem b) {
    final key = '${a.id}>${b.id}';
    final real = _legCache[key];
    if (real != null) return real;
    _ensureLeg(a, b);
    return '${_legLabel(a, b)} (approx)';
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
      backgroundColor: Voy.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Trip Planner', style: TextStyle(color: Voy.ink, fontWeight: FontWeight.w800, fontSize: 17)),
            Text(widget.tripName, style: const TextStyle(color: Voy.sub, fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth >= 900;
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 320, child: _daysPanel()),
                      const VerticalDivider(width: 1, color: Voy.hairline),
                      Expanded(child: _map()),
                      const VerticalDivider(width: 1, color: Voy.hairline),
                      SizedBox(width: 320, child: _placesPanel()),
                    ],
                  );
                }
                return Scaffold(
                  backgroundColor: Colors.transparent,
                  floatingActionButton: FloatingActionButton.extended(
                    onPressed: _openPlacesSheet,
                    backgroundColor: Voy.brand,
                    foregroundColor: const Color(0xFF04211F),
                    icon: const Icon(Icons.add_location_alt_rounded),
                    label: const Text('Add place'),
                  ),
                  body: _daysPanel(),
                );
              },
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
            Icon(Icons.view_day_rounded, size: 54, color: Voy.sub.withValues(alpha: 0.5)),
            const SizedBox(height: 14),
            const Text('Plan your days', style: TextStyle(color: Voy.ink, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('Add days, then search & add places to each.', style: TextStyle(color: Voy.sub, fontSize: 13)),
            const SizedBox(height: 14),
            ElevatedButton.icon(onPressed: _addDay, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add first day')),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        for (int di = 0; di < _days.length; di++) _dayCard(di),
        const SizedBox(height: 4),
        OutlinedButton.icon(onPressed: _addDay, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add day')),
      ],
    );
  }

  Widget _dayCard(int di) {
    final day = _days[di];
    final selected = di == _selectedDay;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: selected ? Voy.brand : Voy.hairline, width: selected ? 1.6 : 1),
      ),
      child: InkWell(
        onTap: () => setState(() => _selectedDay = di),
        borderRadius: BorderRadius.circular(18),
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
                    decoration: BoxDecoration(color: Voy.brand.withValues(alpha: selected ? 0.25 : 0.15), borderRadius: BorderRadius.circular(9)),
                    child: Text('${di + 1}', style: const TextStyle(color: Voy.brand, fontWeight: FontWeight.w800)),
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
                                Expanded(child: Text(day.items[ii].text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Voy.ink, fontSize: 14))),
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
                                  Text(_legDisplay(day.items[ii], day.items[ii + 1]),
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
    return Container(
      color: Voy.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Add place / activity', style: TextStyle(color: Voy.ink, fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(targetDay == null ? 'Add a day first' : 'Adding to ${targetDay.title}', style: const TextStyle(color: Voy.brand, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Voy.ink),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: 'Search places (AI)…',
                    prefixIcon: const Icon(Icons.search_rounded, color: Voy.sub),
                    suffixIcon: _searching
                        ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                        : IconButton(icon: const Icon(Icons.arrow_forward_rounded, color: Voy.brand), onPressed: _search),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(onPressed: _promptAddItem, icon: const Icon(Icons.edit_rounded, size: 16), label: const Text('Add your own')),
                ),
              ],
            ),
          ),
          if (_searchError != null)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), child: Text(_searchError!, style: const TextStyle(color: Voy.danger, fontSize: 12.5))),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(_searching ? 'Searching…' : 'Search for attractions, food, stays…', textAlign: TextAlign.center, style: TextStyle(color: Voy.sub.withValues(alpha: 0.8), fontSize: 13)),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 20),
                    itemCount: _results.length,
                    itemBuilder: (ctx, i) {
                      final r = _results[i];
                      final name = r['name'] ?? '';
                      final area = r['area'] ?? '';
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          title: Text(name, style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.w600)),
                          subtitle: (area.isEmpty && (r['why'] ?? '').isEmpty)
                              ? null
                              : Text([area, r['why'] ?? ''].where((s) => s.isNotEmpty).join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Voy.sub, fontSize: 12)),
                          trailing: IconButton(
                            icon: const Icon(Icons.add_circle_rounded, color: Voy.brand),
                            onPressed: targetDay == null ? null : () => _addSearchedPlace(name, area, targetDay),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
