import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/app_config.dart';
import '../theme/app_theme.dart';
import '../models/trip_models.dart';
import '../models/trip_extras.dart';
import '../services/trip_extras_store.dart';
import '../services/trip_history_service.dart';
import '../services/api_service.dart';
import '../data/attraction_database.dart';
import 'itinerary_screen.dart';
import 'bookings_screen.dart';
import 'gallery_screen.dart';
import 'active_trip_screen.dart';

/// A tabbed "trip workspace" — the single place that brings a trip together:
/// Map, Itinerary, an interactive Packing checklist, an Expense tracker with
/// splitting, and a Reservations manager. The add-ons persist locally and sync to cloud.
class TripWorkspaceScreen extends StatefulWidget {
  final String tripKey;
  final String tripName;
  final int travellers;
  final String currency;

  // Trip data used to power the Map and Itinerary tabs.
  final TripPlan plan;
  final GeoPoint start;
  final GeoPoint end;
  final List<GeoPoint> waypoints;
  final Vehicle vehicle;
  final String startAddress;
  final String endAddress;
  final DateTime tripStart;
  final List<Map<String, dynamic>>? savedItinerary;
  /// Which tab to open on (0=Map, 1=Plan, 2=Itinerary, …).
  final int initialTabIndex;

  const TripWorkspaceScreen({
    super.key,
    required this.tripKey,
    required this.tripName,
    required this.plan,
    required this.start,
    required this.end,
    required this.vehicle,
    required this.startAddress,
    required this.endAddress,
    required this.tripStart,
    this.waypoints = const [],
    this.savedItinerary,
    this.travellers = 1,
    this.currency = 'INR',
    this.initialTabIndex = 0,
  });

  @override
  State<TripWorkspaceScreen> createState() => _TripWorkspaceScreenState();
}

class _TripWorkspaceScreenState extends State<TripWorkspaceScreen> {
  @override
  void initState() {
    super.initState();
    _syncTripToCloud();
  }

  void _syncTripToCloud() {
    final toll = widget.plan.toll?.fastagTollCost ?? 0.0;
    final v = widget.vehicle;
    final double litres = v.efficiencyKmPerLiter > 0 ? widget.plan.distanceKm / v.efficiencyKmPerLiter : 0.0;
    final double fuel = widget.plan.toll?.fuelCost ?? (litres * 102.0);
    final double total = toll + fuel;
    final stops = widget.waypoints.map((w) => w.name ?? 'Waypoint').toList();

    TripHistoryService.instance.saveTrip(
      TripHistoryItem(
        id: 'trip_${widget.start.lat.toStringAsFixed(3)}_${widget.end.lat.toStringAsFixed(3)}_${DateTime.now().millisecondsSinceEpoch}',
        title: widget.tripName.isNotEmpty ? widget.tripName : '${widget.startAddress} → ${widget.endAddress} (round trip)',
        startAddress: widget.startAddress,
        endAddress: widget.endAddress,
        waypoints: stops,
        distanceKm: widget.plan.distanceKm,
        durationMinutes: widget.plan.durationMin,
        vehicleType: widget.vehicle.type,
        fuelCost: fuel,
        tollCost: toll,
        totalCost: total,
        completedAt: DateTime.now(),
        isRoundTrip: true,
        totalStopsCount: stops.length,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = TripExtrasStore(widget.tripKey);
    return DefaultTabController(
      length: 7,
      initialIndex: widget.initialTabIndex,
      child: Scaffold(
        backgroundColor: Voy.bg,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Trip Workspace',
                  style: TextStyle(color: Voy.ink, fontWeight: FontWeight.w800, fontSize: 17)),
              if (widget.tripName.isNotEmpty)
                Text(widget.tripName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Voy.sub, fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.cloud_done_rounded, color: Voy.brand),
              tooltip: 'Trip synced to account',
              onPressed: () {
                _syncTripToCloud();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Trip & itinerary synced across your devices!')),
                );
              },
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: Voy.brand,
            labelColor: Voy.brand,
            unselectedLabelColor: Voy.sub,
            labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
            tabs: [
              Tab(icon: Icon(Icons.map_rounded), text: 'Map'),
              Tab(icon: Icon(Icons.view_day_rounded), text: 'Plan'),
              Tab(icon: Icon(Icons.timeline_rounded), text: 'Itinerary'),
              Tab(icon: Icon(Icons.checklist_rounded), text: 'Packing'),
              Tab(icon: Icon(Icons.payments_rounded), text: 'Expenses'),
              Tab(icon: Icon(Icons.confirmation_number_rounded), text: 'Bookings'),
              Tab(icon: Icon(Icons.menu_book_rounded), text: 'Journal'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _MapTab(plan: widget.plan, start: widget.start, end: widget.end, waypoints: widget.waypoints),
            _PlanTab(
              store: store,
              plan: widget.plan,
              start: widget.start,
              end: widget.end,
              waypoints: widget.waypoints,
              startAddress: widget.startAddress,
              endAddress: widget.endAddress,
            ),
            ItineraryScreen(
              plan: widget.plan,
              startAddress: widget.startAddress,
              endAddress: widget.endAddress,
              start: widget.start,
              end: widget.end,
              waypoints: widget.waypoints,
              vehicleType: widget.vehicle.type,
              vehicle: widget.vehicle,
              travellers: widget.travellers,
              tripStart: widget.tripStart,
              initialItinerary: widget.savedItinerary,
              embedded: true,
            ),
            _PackingTab(store: store),
            _ExpensesTab(store: store, travellers: widget.travellers, currency: widget.currency),
            _ReservationsTab(
              store: store,
              fromName: widget.startAddress,
              toName: widget.endAddress,
              travellers: widget.travellers,
            ),
            _JournalTab(store: store),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Map tab — read-only route preview (polyline + start/end/waypoint markers)
// ─────────────────────────────────────────────────────────────────────────────

class _MapTab extends StatelessWidget {
  final TripPlan plan;
  final GeoPoint start;
  final GeoPoint end;
  final List<GeoPoint> waypoints;
  const _MapTab({required this.plan, required this.start, required this.end, required this.waypoints});

  @override
  Widget build(BuildContext context) {
    final points = plan.coordinates.map((c) => LatLng(c.lat, c.lng)).toList();
    final bounds = points.isNotEmpty
        ? LatLngBounds.fromPoints(points)
        : LatLngBounds(LatLng(start.lat, start.lng), LatLng(end.lat, end.lng));
    final token = AppConfig.mapboxToken;
    final tileUrl = token.isNotEmpty
        ? 'https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/tiles/256/{z}/{x}/{y}?access_token=$token'
        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: bounds,
              padding: const EdgeInsets.all(48),
            ),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag | InteractiveFlag.doubleTapZoom,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: tileUrl,
              userAgentPackageName: 'com.example.travel_app',
              additionalOptions: {'accessToken': token},
            ),
            if (points.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(points: points, strokeWidth: 5, color: Voy.brand),
                ],
              ),
            MarkerLayer(
              markers: [
                _pin(LatLng(start.lat, start.lng), Voy.success, Icons.trip_origin_rounded),
                for (final w in waypoints) _pin(LatLng(w.lat, w.lng), Voy.amber, Icons.place_rounded),
                _pin(LatLng(end.lat, end.lng), Voy.coral, Icons.flag_rounded),
              ],
            ),
          ],
        ),
        // Distance / duration summary chip
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Voy.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Voy.hairline),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _stat(Icons.straighten_rounded, '${plan.distanceKm.toStringAsFixed(0)} km', 'Distance'),
                _stat(Icons.schedule_rounded, _fmtDuration(plan.durationMin), 'Drive time'),
                _stat(Icons.place_rounded, '${waypoints.length}', 'Stops'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Marker _pin(LatLng p, Color color, IconData icon) => Marker(
        point: p,
        width: 34,
        height: 34,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 6)],
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      );

  Widget _stat(IconData icon, String value, String label) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Voy.brand, size: 18),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.w800, fontSize: 14)),
          Text(label, style: const TextStyle(color: Voy.sub, fontSize: 11)),
        ],
      );

  String _fmtDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

String currencySymbol(String code) {
  switch (code.toUpperCase()) {
    case 'INR':
      return '₹';
    case 'USD':
    case 'AUD':
    case 'CAD':
    case 'SGD':
      return '\$';
    case 'EUR':
      return '€';
    case 'GBP':
      return '£';
    case 'JPY':
      return '¥';
    case 'AED':
      return 'د.إ';
    case 'THB':
      return '฿';
    default:
      return '$code ';
  }
}

String _fmtMoney(double v) =>
    v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);

String _uid() => DateTime.now().microsecondsSinceEpoch.toString();

Widget _emptyState(IconData icon, String title, String subtitle) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Voy.sub.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Voy.ink, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Voy.sub, fontSize: 13)),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Packing checklist
// ─────────────────────────────────────────────────────────────────────────────

class _PackingTab extends StatefulWidget {
  final TripExtrasStore store;
  const _PackingTab({required this.store});
  @override
  State<_PackingTab> createState() => _PackingTabState();
}

class _PackingTabState extends State<_PackingTab> {
  List<PackingItem> _items = [];
  bool _loading = true;

  static const _categories = ['Essentials', 'Clothes', 'Toiletries', 'Electronics', 'Documents', 'General'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.store.loadPacking();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  void _persist() => widget.store.savePacking(_items);

  void _seedDefaults() {
    const defaults = {
      'Documents': ['ID / License', 'Bookings & tickets'],
      'Essentials': ['Phone charger', 'Power bank', 'Water bottle', 'First-aid kit'],
      'Clothes': ['T-shirts', 'Jacket', 'Footwear'],
      'Toiletries': ['Toothbrush', 'Sunscreen'],
      'Electronics': ['Earphones'],
    };
    setState(() {
      defaults.forEach((cat, names) {
        for (final n in names) {
          _items.add(PackingItem(id: _uid() + n, name: n, category: cat));
        }
      });
    });
    _persist();
  }

  Future<void> _addItem() async {
    final res = await _showItemSheet();
    if (res == null) return;
    setState(() => _items.add(PackingItem(id: _uid(), name: res.$1, category: res.$2)));
    _persist();
  }

  Future<(String, String)?> _showItemSheet() {
    final nameCtrl = TextEditingController();
    String cat = 'General';
    return showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 18, right: 18, top: 18, bottom: MediaQuery.of(ctx).viewInsets.bottom + 18),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add packing item',
                  style: TextStyle(color: Voy.ink, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                style: const TextStyle(color: Voy.ink),
                decoration: const InputDecoration(labelText: 'Item'),
                onSubmitted: (_) {
                  if (nameCtrl.text.trim().isNotEmpty) Navigator.pop(ctx, (nameCtrl.text.trim(), cat));
                },
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in _categories)
                    ChoiceChip(
                      label: Text(c),
                      selected: cat == c,
                      onSelected: (_) => setSheet(() => cat = c),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (nameCtrl.text.trim().isNotEmpty) {
                      Navigator.pop(ctx, (nameCtrl.text.trim(), cat));
                    }
                  },
                  child: const Text('Add'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final packed = _items.where((e) => e.packed).length;
    final total = _items.length;
    final progress = total == 0 ? 0.0 : packed / total;

    // Group by category, keeping a stable category order.
    final byCat = <String, List<PackingItem>>{};
    for (final it in _items) {
      byCat.putIfAbsent(it.category, () => []).add(it);
    }
    final cats = byCat.keys.toList()
      ..sort((a, b) {
        final ia = _categories.indexOf(a), ib = _categories.indexOf(b);
        return (ia == -1 ? 99 : ia).compareTo(ib == -1 ? 99 : ib);
      });

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addItem,
        backgroundColor: Voy.brand,
        foregroundColor: const Color(0xFF04211F),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add item'),
      ),
      body: total == 0
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _emptyState(Icons.checklist_rounded, 'No packing items yet',
                      'Add your own, or start from a smart default list.'),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _seedDefaults,
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: const Text('Use suggested list'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('$packed of $total packed',
                              style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.w700)),
                          Text('${(progress * 100).round()}%',
                              style: const TextStyle(color: Voy.brand, fontWeight: FontWeight.w800)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          backgroundColor: Voy.surface2,
                          valueColor: const AlwaysStoppedAnimation(Voy.brand),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                    children: [
                      for (final cat in cats) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
                          child: Text(cat.toUpperCase(),
                              style: const TextStyle(
                                  color: Voy.sub, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                        ),
                        for (final item in byCat[cat]!)
                          Dismissible(
                            key: ValueKey(item.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              decoration: BoxDecoration(
                                  color: Voy.danger.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(14)),
                              child: const Icon(Icons.delete_outline_rounded, color: Voy.danger),
                            ),
                            onDismissed: (_) {
                              setState(() => _items.remove(item));
                              _persist();
                            },
                            child: Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: CheckboxListTile(
                                value: item.packed,
                                activeColor: Voy.brand,
                                controlAffinity: ListTileControlAffinity.leading,
                                title: Text(item.name,
                                    style: TextStyle(
                                      color: item.packed ? Voy.sub : Voy.ink,
                                      decoration: item.packed ? TextDecoration.lineThrough : null,
                                    )),
                                onChanged: (v) {
                                  setState(() => item.packed = v ?? false);
                                  _persist();
                                },
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expense tracker + split
// ─────────────────────────────────────────────────────────────────────────────

class _ExpensesTab extends StatefulWidget {
  final TripExtrasStore store;
  final int travellers;
  final String currency;
  const _ExpensesTab({required this.store, required this.travellers, required this.currency});
  @override
  State<_ExpensesTab> createState() => _ExpensesTabState();
}

class _ExpensesTabState extends State<_ExpensesTab> {
  List<Expense> _items = [];
  bool _loading = true;

  List<String> get _people =>
      [for (int i = 0; i < widget.travellers; i++) i == 0 ? 'Me' : 'Traveller ${i + 1}'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.store.loadExpenses();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  void _persist() => widget.store.saveExpenses(_items);

  Future<void> _addOrEdit([Expense? existing]) async {
    final result = await showModalBottomSheet<Expense>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ExpenseSheet(
        people: _people,
        currency: widget.currency,
        existing: existing,
      ),
    );
    if (result == null) return;
    setState(() {
      if (existing != null) {
        final i = _items.indexWhere((e) => e.id == existing.id);
        if (i != -1) _items[i] = result;
      } else {
        _items.add(result);
      }
    });
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final sym = currencySymbol(widget.currency);
    final total = _items.fold<double>(0, (s, e) => s + e.amount);
    final multi = widget.travellers > 1;

    // Settle-up maths: what each person PAID vs what their SHARE is. The net
    // (paid − share) tells us who is owed money and who owes it.
    final paid = <String, double>{for (final p in _people) p: 0};
    final share = <String, double>{for (final p in _people) p: 0};
    for (final e in _items) {
      paid[e.paidBy] = (paid[e.paidBy] ?? 0) + e.amount;
      final people = e.sharedWith.isEmpty ? _people : e.sharedWith;
      if (people.isEmpty) continue;
      final each = e.amount / people.length;
      for (final p in people) {
        share[p] = (share[p] ?? 0) + each;
      }
    }
    final me = _people.isNotEmpty ? _people.first : 'Me';
    final myNet = (paid[me] ?? 0) - (share[me] ?? 0);
    final youOwe = myNet < 0 ? -myNet : 0.0;
    final youAreOwed = myNet > 0 ? myNet : 0.0;

    // By category, largest first.
    final byCat = <String, double>{};
    for (final e in _items) {
      byCat[e.category] = (byCat[e.category] ?? 0) + e.amount;
    }
    final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        backgroundColor: Voy.brand,
        foregroundColor: const Color(0xFF04211F),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add expense'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          if (multi)
            Row(
              children: [
                Expanded(child: _miniCard('You owe', '$sym${_fmtMoney(youOwe)}', Voy.danger, Icons.south_rounded)),
                const SizedBox(width: 10),
                Expanded(child: _miniCard('You\'re owed', '$sym${_fmtMoney(youAreOwed)}', Voy.success, Icons.north_rounded)),
              ],
            ),
          if (multi) const SizedBox(height: 10),
          // Total spend card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Voy.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Voy.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.bar_chart_rounded, color: Voy.brand, size: 18),
                  const SizedBox(width: 8),
                  const Text('Total trip spend',
                      style: TextStyle(color: Voy.sub, fontSize: 12.5, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 6),
                Text('$sym${_fmtMoney(total)}',
                    style: const TextStyle(color: Voy.ink, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                if (multi) ...[
                  const SizedBox(height: 4),
                  Text('Your share $sym${_fmtMoney(share[me] ?? 0)}  ·  You paid $sym${_fmtMoney(paid[me] ?? 0)}',
                      style: const TextStyle(color: Voy.sub, fontSize: 12.5)),
                ],
              ],
            ),
          ),
          // Balances per person
          if (multi) ...[
            const SizedBox(height: 14),
            _sectionTitle('BALANCES'),
            const SizedBox(height: 8),
            for (final p in _people)
              _balanceRow(p, (paid[p] ?? 0) - (share[p] ?? 0), sym),
          ],
          // By category
          if (cats.isNotEmpty) ...[
            const SizedBox(height: 14),
            _sectionTitle('BY CATEGORY'),
            const SizedBox(height: 8),
            for (final c in cats)
              _categoryRow(c.key, c.value, total == 0 ? 0 : c.value / total, sym),
          ],
          const SizedBox(height: 16),
          _sectionTitle('EXPENSES'),
          const SizedBox(height: 4),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: _emptyState(Icons.payments_rounded, 'No expenses yet',
                  'Track fuel, food, stays and more — split them across travellers.'),
            )
          else
            for (final e in _items.reversed)
              Dismissible(
                key: ValueKey(e.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                      color: Voy.danger.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.delete_outline_rounded, color: Voy.danger),
                ),
                onDismissed: (_) {
                  setState(() => _items.removeWhere((x) => x.id == e.id));
                  _persist();
                },
                child: Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    onTap: () => _addOrEdit(e),
                    leading: CircleAvatar(
                      backgroundColor: Voy.surface2,
                      child: Icon(_categoryIcon(e.category), color: Voy.brand, size: 20),
                    ),
                    title: Text(e.title,
                        style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${e.paidBy} paid'
                      '${e.sharedWith.length > 1 ? ' · split ${e.sharedWith.length} ways (${currencySymbol(e.currency)}${_fmtMoney(e.perPerson)} each)' : ''}',
                      style: const TextStyle(color: Voy.sub, fontSize: 12),
                    ),
                    trailing: Text('${currencySymbol(e.currency)}${_fmtMoney(e.amount)}',
                        style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _miniCard(String label, String value, Color color, IconData icon) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 15),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(color: Voy.ink, fontSize: 22, fontWeight: FontWeight.w800)),
          ],
        ),
      );

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(t,
            style: const TextStyle(color: Voy.sub, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.7)),
      );

  Widget _balanceRow(String person, double net, String sym) {
    final settled = net.abs() < 0.01;
    final color = settled ? Voy.sub : (net > 0 ? Voy.success : Voy.danger);
    final label = settled
        ? 'settled up'
        : (net > 0 ? 'gets back $sym${_fmtMoney(net)}' : 'owes $sym${_fmtMoney(-net)}');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: Voy.surface2,
            child: Text(person.isNotEmpty ? person[0].toUpperCase() : '?',
                style: const TextStyle(color: Voy.ink, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(person, style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.w600))),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _categoryRow(String cat, double amount, double frac, String sym) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        children: [
          Row(
            children: [
              Icon(_categoryIcon(cat), color: Voy.brand, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(cat, style: const TextStyle(color: Voy.ink, fontSize: 13.5, fontWeight: FontWeight.w600))),
              Text('$sym${_fmtMoney(amount)}', style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.w700, fontSize: 13.5)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: frac.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: Voy.surface2,
              valueColor: const AlwaysStoppedAnimation(Voy.brand),
            ),
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(String c) {
    switch (c) {
      case 'Fuel':
        return Icons.local_gas_station_rounded;
      case 'Food':
        return Icons.restaurant_rounded;
      case 'Stay':
        return Icons.hotel_rounded;
      case 'Tolls':
        return Icons.toll_rounded;
      case 'Activities':
        return Icons.local_activity_rounded;
      case 'Shopping':
        return Icons.shopping_bag_rounded;
      default:
        return Icons.receipt_long_rounded;
    }
  }
}

class _ExpenseSheet extends StatefulWidget {
  final List<String> people;
  final String currency;
  final Expense? existing;
  const _ExpenseSheet({required this.people, required this.currency, this.existing});
  @override
  State<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<_ExpenseSheet> {
  late final TextEditingController _title;
  late final TextEditingController _amount;
  late String _paidBy;
  late Set<String> _split;
  late String _category;

  static const _cats = ['Fuel', 'Food', 'Stay', 'Tolls', 'Activities', 'Shopping', 'General'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _amount = TextEditingController(text: e != null ? _fmtMoney(e.amount) : '');
    _paidBy = e?.paidBy ?? (widget.people.isNotEmpty ? widget.people.first : 'Me');
    _split = {...(e?.sharedWith ?? widget.people)};
    _category = e?.category ?? 'General';
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _save() {
    final amt = double.tryParse(_amount.text.trim());
    if (_title.text.trim().isEmpty || amt == null || amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a title and a valid amount.')),
      );
      return;
    }
    Navigator.pop(
      context,
      Expense(
        id: widget.existing?.id ?? _uid(),
        title: _title.text.trim(),
        amount: amt,
        currency: widget.currency,
        paidBy: _paidBy,
        sharedWith: _split.toList(),
        category: _category,
        date: widget.existing?.date,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 18, right: 18, top: 18, bottom: MediaQuery.of(context).viewInsets.bottom + 18),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.existing == null ? 'Add expense' : 'Edit expense',
                style: const TextStyle(color: Voy.ink, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            TextField(
              controller: _title,
              style: const TextStyle(color: Voy.ink),
              decoration: const InputDecoration(labelText: 'What was it for?'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Voy.ink),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '${currencySymbol(widget.currency)} ',
                prefixStyle: const TextStyle(color: Voy.ink),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Category', style: TextStyle(color: Voy.sub, fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _cats)
                  ChoiceChip(
                    label: Text(c),
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = c),
                  ),
              ],
            ),
            if (widget.people.length > 1) ...[
              const SizedBox(height: 14),
              const Text('Paid by', style: TextStyle(color: Voy.sub, fontSize: 12.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in widget.people)
                    ChoiceChip(
                      label: Text(p),
                      selected: _paidBy == p,
                      onSelected: (_) => setState(() => _paidBy = p),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('Split between', style: TextStyle(color: Voy.sub, fontSize: 12.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in widget.people)
                    FilterChip(
                      label: Text(p),
                      selected: _split.contains(p),
                      onSelected: (v) => setState(() => v ? _split.add(p) : _split.remove(p)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: _save, child: const Text('Save expense')),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reservations
// ─────────────────────────────────────────────────────────────────────────────

class _ReservationsTab extends StatefulWidget {
  final TripExtrasStore store;
  final String fromName;
  final String toName;
  final int travellers;
  const _ReservationsTab({
    required this.store,
    this.fromName = '',
    this.toName = '',
    this.travellers = 1,
  });
  @override
  State<_ReservationsTab> createState() => _ReservationsTabState();
}

class _ReservationsTabState extends State<_ReservationsTab> {
  List<Reservation> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.store.loadReservations();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  void _persist() => widget.store.saveReservations(_items);

  bool _suggesting = false;

  /// Add a suggested option straight into the bookings list.
  void _addSuggestion(String type, String title, String notes) {
    setState(() => _items.add(Reservation(
          id: _uid(),
          type: type,
          title: title,
          confirmation: '',
          date: null,
          notes: notes,
        )));
    _persist();
  }

  /// Ask the AI for realistic flight / train / hotel options for this journey
  /// and show them in a sheet; tapping one saves it as a booking.
  Future<void> _suggest() async {
    if (widget.toName.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This journey has no destination set.')),
      );
      return;
    }
    setState(() => _suggesting = true);
    try {
      final o = await ApiService().aiTravelOptions(
        from: widget.fromName,
        to: widget.toName,
        travellers: widget.travellers,
      );
      if (!mounted) return;
      setState(() => _suggesting = false);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF14121F),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => _SuggestionsSheet(
          from: widget.fromName,
          to: widget.toName,
          flights: o.flights,
          trains: o.trains,
          hotels: o.hotels,
          onAdd: (type, title, notes) {
            _addSuggestion(type, title, notes);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Added "$title" to bookings.')),
            );
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _suggesting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : 'Could not fetch suggestions.')),
      );
    }
  }

  Future<void> _addOrEdit([Reservation? existing]) async {
    final result = await showModalBottomSheet<Reservation>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ReservationSheet(existing: existing),
    );
    if (result == null) return;
    setState(() {
      if (existing != null) {
        final i = _items.indexWhere((e) => e.id == existing.id);
        if (i != -1) _items[i] = result;
      } else {
        _items.add(result);
      }
    });
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final sorted = [..._items]..sort((a, b) {
        if (a.date == null && b.date == null) return 0;
        if (a.date == null) return 1;
        if (b.date == null) return -1;
        return a.date!.compareTo(b.date!);
      });

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'suggestAi',
            onPressed: _suggesting ? null : _suggest,
            backgroundColor: const Color(0xFF6D5EF6),
            foregroundColor: Colors.white,
            icon: _suggesting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome_rounded),
            label: Text(_suggesting ? 'Finding…' : 'Suggest flights, trains & hotels'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'addBooking',
            onPressed: () => _addOrEdit(),
            backgroundColor: Voy.brand,
            foregroundColor: const Color(0xFF04211F),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add booking'),
          ),
        ],
      ),
      body: sorted.isEmpty
          ? _emptyState(Icons.confirmation_number_rounded, 'No bookings yet',
              'Save flights, hotels, restaurants and activities in one place.')
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: sorted.length,
              itemBuilder: (ctx, i) {
                final r = sorted[i];
                return Dismissible(
                  key: ValueKey(r.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                        color: Voy.danger.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.delete_outline_rounded, color: Voy.danger),
                  ),
                  onDismissed: (_) {
                    setState(() => _items.removeWhere((x) => x.id == r.id));
                    _persist();
                  },
                  child: Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      onTap: () => _addOrEdit(r),
                      leading: CircleAvatar(
                        backgroundColor: Voy.surface2,
                        child: Icon(_typeIcon(r.type), color: Voy.brand, size: 20),
                      ),
                      title: Text(r.title,
                          style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        [
                          _typeLabel(r.type),
                          if (r.date != null) _fmtDate(r.date!),
                          if (r.confirmation.isNotEmpty) '#${r.confirmation}',
                        ].join(' · '),
                        style: const TextStyle(color: Voy.sub, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded, color: Voy.sub),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

String _fmtDate(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

IconData _typeIcon(String t) {
  switch (t) {
    case 'flight':
      return Icons.flight_rounded;
    case 'train':
      return Icons.train_rounded;
    case 'hotel':
      return Icons.hotel_rounded;
    case 'restaurant':
      return Icons.restaurant_rounded;
    case 'activity':
      return Icons.local_activity_rounded;
    default:
      return Icons.confirmation_number_rounded;
  }
}

String _typeLabel(String t) => t.isEmpty ? 'Booking' : t[0].toUpperCase() + t.substring(1);

/// Bottom sheet showing AI-suggested flights, trains and hotels for a journey.
class _SuggestionsSheet extends StatelessWidget {
  final String from;
  final String to;
  final List<Map<String, String>> flights;
  final List<Map<String, String>> trains;
  final List<Map<String, String>> hotels;
  final void Function(String type, String title, String notes) onAdd;

  const _SuggestionsSheet({
    required this.from,
    required this.to,
    required this.flights,
    required this.trains,
    required this.hotels,
    required this.onAdd,
  });

  String _join(Iterable<String?> parts) =>
      parts.where((p) => p != null && p.trim().isNotEmpty).map((p) => p!.trim()).join(' · ');

  Widget _sectionHeader(IconData icon, String label, Color color) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _card({required String title, required String subtitle, required String trailing, required VoidCallback onTap}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: ListTile(
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14.5)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (subtitle.isNotEmpty)
              Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5)),
            if (trailing.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(trailing, style: const TextStyle(color: Color(0xFF7DD3FC), fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
          ]),
        ),
        trailing: TextButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
          label: const Text('Add'),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF6D5EF6)),
        ),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final empty = flights.isEmpty && trains.isEmpty && hotels.isEmpty;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (ctx, scroll) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: ListView(
          controller: scroll,
          children: [
            Center(
              child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            ),
            Text('Suggested options', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('${from.isEmpty ? 'Your trip' : from} → $to · typical options, not live prices',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12.5)),
            if (empty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Text('No suggestions returned — try again.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6)))),
              ),
            if (flights.isNotEmpty) _sectionHeader(Icons.flight_rounded, 'Flights', const Color(0xFF38BDF8)),
            for (final f in flights)
              _card(
                title: _join([f['airline'], f['flightNo']]),
                subtitle: _join([f['route'], f['stops']?.toLowerCase() == 'direct' ? 'Direct' : (f['stops'] != null && f['stops']!.isNotEmpty ? 'via ${f['stops']}' : null), f['duration']]),
                trailing: _join([f['priceRange'], f['note']]),
                onTap: () => onAdd('flight', _join([f['airline'], f['flightNo']]),
                    _join([f['route'], f['stops'], f['duration'], f['priceRange'], f['note']])),
              ),
            if (trains.isNotEmpty) _sectionHeader(Icons.train_rounded, 'Trains', const Color(0xFF34D399)),
            for (final t in trains)
              _card(
                title: _join([t['operator'], t['name']]),
                subtitle: _join([t['route'], t['duration']]),
                trailing: _join([t['priceRange'], t['note']]),
                onTap: () => onAdd('train', _join([t['operator'], t['name']]),
                    _join([t['route'], t['duration'], t['priceRange'], t['note']])),
              ),
            if (hotels.isNotEmpty) _sectionHeader(Icons.hotel_rounded, 'Hotels', const Color(0xFFA78BFA)),
            for (final h in hotels)
              _card(
                title: _join([h['name'], h['rating']]),
                subtitle: _join([h['area'], h['note']]),
                trailing: h['pricePerNight'] != null && h['pricePerNight']!.isNotEmpty ? '${h['pricePerNight']} / night' : '',
                onTap: () => onAdd('hotel', h['name'] ?? 'Hotel',
                    _join([h['area'], h['pricePerNight'] != null && h['pricePerNight']!.isNotEmpty ? '${h['pricePerNight']}/night' : null, h['rating'], h['note']])),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ReservationSheet extends StatefulWidget {
  final Reservation? existing;
  const _ReservationSheet({this.existing});
  @override
  State<_ReservationSheet> createState() => _ReservationSheetState();
}

class _ReservationSheetState extends State<_ReservationSheet> {
  late final TextEditingController _title;
  late final TextEditingController _confirmation;
  late final TextEditingController _notes;
  late String _type;
  DateTime? _date;

  static const _types = ['flight', 'train', 'hotel', 'restaurant', 'activity', 'other'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _confirmation = TextEditingController(text: e?.confirmation ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _type = e?.type ?? 'hotel';
    _date = e?.date;
  }

  @override
  void dispose() {
    _title.dispose();
    _confirmation.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _save() {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give the booking a name.')),
      );
      return;
    }
    Navigator.pop(
      context,
      Reservation(
        id: widget.existing?.id ?? _uid(),
        type: _type,
        title: _title.text.trim(),
        confirmation: _confirmation.text.trim(),
        date: _date,
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 18, right: 18, top: 18, bottom: MediaQuery.of(context).viewInsets.bottom + 18),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.existing == null ? 'Add booking' : 'Edit booking',
                style: const TextStyle(color: Voy.ink, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _types)
                  ChoiceChip(
                    avatar: Icon(_typeIcon(t), size: 16, color: _type == t ? const Color(0xFF04211F) : Voy.sub),
                    label: Text(_typeLabel(t)),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              style: const TextStyle(color: Voy.ink),
              decoration: const InputDecoration(labelText: 'Name (e.g. Taj Hotel, IndiGo 6E-123)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmation,
              style: const TextStyle(color: Voy.ink),
              decoration: const InputDecoration(labelText: 'Confirmation number (optional)'),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Date'),
                child: Text(
                  _date == null ? 'Tap to pick a date' : _fmtDate(_date!),
                  style: TextStyle(color: _date == null ? Voy.sub : Voy.ink),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 3,
              style: const TextStyle(color: Voy.ink),
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: _save, child: const Text('Save booking')),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Journal
// ─────────────────────────────────────────────────────────────────────────────

class _JournalTab extends StatefulWidget {
  final TripExtrasStore store;
  const _JournalTab({required this.store});
  @override
  State<_JournalTab> createState() => _JournalTabState();
}

class _JournalTabState extends State<_JournalTab> {
  List<JournalEntry> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.store.loadJournal();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  void _persist() => widget.store.saveJournal(_items);

  Future<void> _addOrEdit([JournalEntry? existing]) async {
    final result = await showModalBottomSheet<JournalEntry>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _JournalSheet(existing: existing),
    );
    if (result == null) return;
    setState(() {
      if (existing != null) {
        final i = _items.indexWhere((e) => e.id == existing.id);
        if (i != -1) _items[i] = result;
      } else {
        _items.add(result);
      }
    });
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final sorted = [..._items]..sort((a, b) => b.date.compareTo(a.date)); // newest first

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        backgroundColor: Voy.brand,
        foregroundColor: const Color(0xFF04211F),
        icon: const Icon(Icons.edit_rounded),
        label: const Text('New entry'),
      ),
      body: sorted.isEmpty
          ? _emptyState(Icons.menu_book_rounded, 'Your travel journal',
              'Jot down memories, highlights and notes as your trip unfolds.')
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: sorted.length,
              itemBuilder: (ctx, i) {
                final e = sorted[i];
                return Dismissible(
                  key: ValueKey(e.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                        color: Voy.danger.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.delete_outline_rounded, color: Voy.danger),
                  ),
                  onDismissed: (_) {
                    setState(() => _items.removeWhere((x) => x.id == e.id));
                    _persist();
                  },
                  child: Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      onTap: () => _addOrEdit(e),
                      title: Text(e.title.isEmpty ? _fmtDate(e.date) : e.title,
                          style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.w700)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (e.title.isNotEmpty)
                            Text(_fmtDate(e.date),
                                style: const TextStyle(color: Voy.sub, fontSize: 11.5)),
                          if (e.body.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(e.body,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Voy.sub, fontSize: 13, height: 1.35)),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _JournalSheet extends StatefulWidget {
  final JournalEntry? existing;
  const _JournalSheet({this.existing});
  @override
  State<_JournalSheet> createState() => _JournalSheetState();
}

class _JournalSheetState extends State<_JournalSheet> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.existing?.title ?? '');
    _body = TextEditingController(text: widget.existing?.body ?? '');
    _date = widget.existing?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _save() {
    if (_title.text.trim().isEmpty && _body.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write something first.')),
      );
      return;
    }
    Navigator.pop(
      context,
      JournalEntry(
        id: widget.existing?.id ?? _uid(),
        title: _title.text.trim(),
        body: _body.text.trim(),
        date: _date,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 18, right: 18, top: 18, bottom: MediaQuery.of(context).viewInsets.bottom + 18),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.existing == null ? 'New journal entry' : 'Edit entry',
                style: const TextStyle(color: Voy.ink, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Date'),
                child: Text(_fmtDate(_date), style: const TextStyle(color: Voy.ink)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              style: const TextStyle(color: Voy.ink),
              decoration: const InputDecoration(labelText: 'Title (optional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              maxLines: 6,
              minLines: 4,
              style: const TextStyle(color: Voy.ink, height: 1.4),
              decoration: const InputDecoration(
                labelText: 'What happened?',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: _save, child: const Text('Save entry')),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Responsive Plan view: day-by-day organizer (left) + map (center) + a search-
// and-add place panel (right). Three panes side-by-side on wide screens; stacked
// with an "Add place" sheet on phones.
// ─────────────────────────────────────────────────────────────────────────────

class _PlanTab extends StatefulWidget {
  final TripExtrasStore store;
  final TripPlan plan;
  final GeoPoint start;
  final GeoPoint end;
  final List<GeoPoint> waypoints;
  final String startAddress;
  final String endAddress;
  const _PlanTab({
    required this.store,
    required this.plan,
    required this.start,
    required this.end,
    required this.waypoints,
    required this.startAddress,
    this.endAddress = '',
  });
  @override
  State<_PlanTab> createState() => _PlanTabState();
}

class _PlanTabState extends State<_PlanTab> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();

  List<PlanDay> _days = [];
  int _selectedDay = 0;
  bool _loading = true;

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final days = await widget.store.loadDays();
    if (!mounted) return;
    setState(() {
      _days = days;
      _selectedDay = 0;
      _loading = false;
    });
    _loadSuggestions();
  }

  void _loadSuggestions() {
    final cat = _activeCategoryFilter == 'All'
        ? null
        : _activeCategoryFilter.replaceAll(RegExp(r'[^\w\s]'), '').trim();
    final toCity = widget.endAddress.isNotEmpty ? widget.endAddress : widget.startAddress;
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

  void _persist() => widget.store.saveDays(_days);

  Future<void> _startTrip() async {
    if (_days.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add or generate a day first, then start the trip.')),
      );
      return;
    }
    var startedAt = await widget.store.loadStartedAt();
    startedAt ??= DateTime.now();
    await widget.store.saveStartedAt(startedAt);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ActiveTripScreen(
        store: widget.store,
        days: _days,
        startedAt: startedAt!,
        tripName: widget.startAddress.isNotEmpty ? '${widget.startAddress} → ${widget.endAddress} (round trip)' : 'Active Trip',
      ),
    ));
    if (!mounted) return;
    final refreshed = await widget.store.loadDays();
    setState(() {
      _days = refreshed;
      if (_selectedDay >= _days.length) {
        _selectedDay = _days.isEmpty ? 0 : _days.length - 1;
      }
    });
  }

  void _seedDays() {
    final n = widget.plan.estimatedDays < 1 ? 1 : widget.plan.estimatedDays;
    setState(() {
      for (int i = 0; i < n; i++) {
        _days.add(PlanDay(id: '${_uid()}$i', title: 'Day ${i + 1}'));
      }
    });
    _persist();
  }

  void _addDay() {
    setState(() {
      _days.add(PlanDay(id: _uid(), title: 'Day ${_days.length + 1}'));
      _selectedDay = _days.length - 1;
    });
    _persist();
  }

  void _addTextToSelectedDay(String text) {
    if (text.trim().isEmpty) return;
    if (_days.isEmpty) _addDay();
    final idx = _selectedDay.clamp(0, _days.length - 1);
    setState(() => _days[idx].items.add(PlanItem(id: _uid(), text: text.trim())));
    _persist();
  }

  /// Adds a searched place to the selected day, then geocodes it in the
  /// background so it shows as a numbered pin on the map (best-effort).
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
    } catch (_) {/* item stays without a pin */}
  }

  /// Edit an item's text, time and note.
  Future<void> _editItem(PlanItem item) async {
    final textCtrl = TextEditingController(text: item.text);
    final noteCtrl = TextEditingController(text: item.note);
    String time = item.time;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              left: 18, right: 18, top: 18, bottom: MediaQuery.of(ctx).viewInsets.bottom + 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Edit item', style: TextStyle(color: Voy.ink, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              TextField(controller: textCtrl, style: const TextStyle(color: Voy.ink), decoration: const InputDecoration(labelText: 'Place or activity')),
              const SizedBox(height: 12),
              Row(children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final now = TimeOfDay.now();
                    final picked = await showTimePicker(context: ctx, initialTime: now);
                    if (picked != null) {
                      setSheet(() => time = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
                    }
                  },
                  icon: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text(time.isEmpty ? 'Set time' : time),
                ),
                if (time.isNotEmpty)
                  TextButton(onPressed: () => setSheet(() => time = ''), child: const Text('Clear')),
              ]),
              const SizedBox(height: 12),
              TextField(controller: noteCtrl, maxLines: 2, style: const TextStyle(color: Voy.ink), decoration: const InputDecoration(labelText: 'Note (optional)')),
              const SizedBox(height: 18),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))),
            ],
          ),
        ),
      ),
    );
    if (saved == true) {
      setState(() {
        item.text = textCtrl.text.trim();
        item.time = time;
        item.note = noteCtrl.text.trim();
      });
      _persist();
    }
  }

  Future<void> _renameDay(PlanDay day) async {
    final ctrl = TextEditingController(text: day.title);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename day'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Voy.ink),
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    setState(() => day.title = text);
    _persist();
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
      final toCity = widget.endAddress.isNotEmpty ? widget.endAddress : widget.startAddress;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 320, child: _daysPanel()),
              const VerticalDivider(width: 1, color: Voy.hairline),
              Expanded(child: _planMap()),
              const VerticalDivider(width: 1, color: Voy.hairline),
              SizedBox(width: 320, child: _placesPanel()),
            ],
          );
        }
        // Narrow: days list, with a FAB to open the add-place panel as a sheet.
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
    );
  }

  void _openPlacesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Voy.surface,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => _placesPanel(scrollController: scroll),
      ),
    );
  }

  // ---- Center: map with the selected day's numbered pins ----
  Widget _planMap() {
    final routePts = widget.plan.coordinates.map((c) => LatLng(c.lat, c.lng)).toList();
    final day = _days.isEmpty ? null : _days[_selectedDay.clamp(0, _days.length - 1)];
    final dayPins = <Marker>[];
    if (day != null) {
      int n = 0;
      for (final it in day.items) {
        n++;
        if (!it.hasCoords) continue;
        final label = n;
        dayPins.add(Marker(
          point: LatLng(it.lat!, it.lng!),
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
    final fitPts = [...routePts, ...dayPins.map((m) => m.point)];
    final token = AppConfig.mapboxToken;
    final tileUrl = token.isNotEmpty
        ? 'https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/tiles/256/{z}/{x}/{y}?access_token=$token'
        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    return FlutterMap(
      options: MapOptions(
        initialCameraFit: fitPts.length > 1
            ? CameraFit.bounds(bounds: LatLngBounds.fromPoints(fitPts), padding: const EdgeInsets.all(48))
            : null,
        initialCenter: routePts.isNotEmpty ? routePts.first : const LatLng(20.5937, 78.9629),
        initialZoom: 6,
      ),
      children: [
        TileLayer(
          urlTemplate: tileUrl,
          userAgentPackageName: 'com.example.travel_app',
          additionalOptions: {'accessToken': token},
        ),
        if (routePts.length > 1)
          PolylineLayer(polylines: [Polyline(points: routePts, strokeWidth: 5, color: Voy.brand)]),
        MarkerLayer(markers: [
          _pin(LatLng(widget.start.lat, widget.start.lng), Voy.success, Icons.trip_origin_rounded),
          _pin(LatLng(widget.end.lat, widget.end.lng), Voy.coral, Icons.flag_rounded),
          ...dayPins,
        ]),
      ],
    );
  }

  Marker _pin(LatLng p, Color color, IconData icon) => Marker(
        point: p,
        width: 32,
        height: 32,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 6)],
          ),
          child: Icon(icon, color: Colors.white, size: 17),
        ),
      );

  // ---- Left: days ----
  Widget _daysPanel() {
    if (_days.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _emptyState(Icons.view_day_rounded, 'Plan your days',
                'Organise places and activities into a day-by-day plan.'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _seedDays,
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text('Start with ${widget.plan.estimatedDays < 1 ? 1 : widget.plan.estimatedDays} day(s)'),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ElevatedButton.icon(
            onPressed: _startTrip,
            style: ElevatedButton.styleFrom(
              backgroundColor: Voy.brand,
              foregroundColor: const Color(0xFF04211F),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.navigation_rounded),
            label: const Text('START / RESUME ACTIVE TRIP', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
          ),
        ),
        for (int di = 0; di < _days.length; di++) _dayCard(di),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: _addDay,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add day'),
        ),
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
                    decoration: BoxDecoration(
                        color: Voy.brand.withValues(alpha: selected ? 0.25 : 0.15),
                        borderRadius: BorderRadius.circular(9)),
                    child: Text('${di + 1}',
                        style: const TextStyle(color: Voy.brand, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(day.title,
                        style: const TextStyle(color: Voy.ink, fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  if (selected)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Text('adding here',
                          style: TextStyle(color: Voy.brand, fontSize: 10.5, fontWeight: FontWeight.w800)),
                    ),
                  IconButton(
                    icon: const Icon(Icons.edit_rounded, color: Voy.sub, size: 18),
                    onPressed: () => _renameDay(day),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Voy.danger, size: 20),
                    onPressed: () {
                      setState(() {
                        _days.removeAt(di);
                        // Keep _selectedDay pointing at the SAME day: shift it down
                        // when a day at or before it is removed, then clamp.
                        if (di < _selectedDay) {
                          _selectedDay -= 1;
                        }
                        if (_selectedDay >= _days.length) {
                          _selectedDay = _days.isEmpty ? 0 : _days.length - 1;
                        }
                        if (_selectedDay < 0) _selectedDay = 0;
                      });
                      _persist();
                    },
                  ),
                ],
              ),
              if (day.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 0, 6),
                  child: Text('No items yet — search & add places, or type your own.',
                      style: TextStyle(color: Voy.sub.withValues(alpha: 0.8), fontSize: 12.5)),
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
                      ListTile(
                        key: ValueKey(day.items[ii].id),
                        contentPadding: const EdgeInsets.only(left: 0, right: 0),
                        horizontalTitleGap: 8,
                        minLeadingWidth: 0,
                        onTap: () => _editItem(day.items[ii]),
                        leading: ReorderableDragStartListener(
                          index: ii,
                          child: const Icon(Icons.drag_indicator_rounded, color: Voy.sub, size: 18),
                        ),
                        title: Row(
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: day.items[ii].hasCoords ? Voy.violet : Voy.surface2,
                                shape: BoxShape.circle,
                              ),
                              child: Text('${ii + 1}',
                                  style: TextStyle(
                                      color: day.items[ii].hasCoords ? Colors.white : Voy.sub,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(width: 8),
                            if (day.items[ii].time.isNotEmpty) ...[
                              Text(day.items[ii].time,
                                  style: const TextStyle(color: Voy.brand, fontSize: 12.5, fontWeight: FontWeight.w700)),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(day.items[ii].text,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Voy.ink, fontSize: 14)),
                            ),
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

  Future<void> _promptAddItem() async {
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
    if (text != null && text.isNotEmpty) _addTextToSelectedDay(text);
  }

  // ---- Right: add place / activity ----
  Widget _placesPanel({ScrollController? scrollController}) {
    final targetDay = _days.isEmpty
        ? null
        : _days[_selectedDay.clamp(0, _days.length - 1)];
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
                Row(
                  children: [
                    const Text('Add place / activity',
                        style: TextStyle(color: Voy.ink, fontSize: 16, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Voy.brand.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('AUTO-SUGGEST', style: TextStyle(color: Voy.brand, fontSize: 9.5, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(targetDay == null ? 'Add a day first' : 'Adding to ${targetDay.title}',
                    style: const TextStyle(color: Voy.brand, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Voy.ink),
                  textInputAction: TextInputAction.search,
                  onChanged: _onSearchChanged,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: 'Search places, beaches, temples, food…',
                    hintStyle: const TextStyle(color: Voy.sub, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, color: Voy.sub),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : (_searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, color: Voy.sub, size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  _loadSuggestions();
                                },
                              )
                            : IconButton(icon: const Icon(Icons.arrow_forward_rounded, color: Voy.brand), onPressed: _search)),
                  ),
                ),
                const SizedBox(height: 10),
                // Category Filter Chips
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
                                  ? Voy.brand.withValues(alpha: 0.15)
                                  : Voy.surface2,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _activeCategoryFilter == cat
                                    ? Voy.brand
                                    : Voy.hairline,
                              ),
                            ),
                            child: Text(
                              cat,
                              style: TextStyle(
                                color: _activeCategoryFilter == cat ? Voy.brand : Voy.ink,
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
                  TextButton.icon(
                    onPressed: _promptAddItem,
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text('Add your own'),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => GalleryScreen(store: widget.store, tripName: widget.startAddress.isNotEmpty ? '${widget.startAddress} trip' : 'My Trip'),
                    )),
                    icon: const Icon(Icons.photo_library_rounded, size: 16),
                    label: const Text('Gallery'),
                  ),
                ]),
              ],
            ),
          ),
          if (_searchError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Text(_searchError!, style: const TextStyle(color: Voy.danger, fontSize: 12.5)),
            ),
          // Inline bookings column: saved reservations + AI flight/train/hotel
          // suggestions for this journey.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Voy.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Voy.hairline),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  child: BookingsScreen(
                    store: widget.store,
                    fromName: widget.startAddress,
                    toName: widget.endAddress.isNotEmpty ? widget.endAddress : (widget.end.name ?? ''),
                    travellers: 2,
                    embedded: true,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                Text(
                  _searchCtrl.text.trim().isEmpty ? 'SUGGESTED PLACES & ACTIVITIES' : 'SEARCH RESULTS (${_results.length})',
                  style: const TextStyle(
                    color: Voy.sub,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const Spacer(),
                const Text(
                  'Tap + to add',
                  style: TextStyle(color: Voy.brand, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        _searching ? 'Searching places…' : 'No places found. Tap "Add your own" above.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Voy.sub.withValues(alpha: 0.8), fontSize: 13),
                      ),
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
                      final why = r['why'] ?? '';

                      IconData placeIcon = Icons.place_rounded;
                      Color iconColor = Voy.brand;
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

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Voy.hairline),
                        ),
                        child: InkWell(
                          onTap: targetDay == null ? null : () => _addSearchedPlace(name, area, targetDay),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: iconColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(placeIcon, size: 18, color: iconColor),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(name, style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.w600, fontSize: 13.5)),
                                      if (!(area.isEmpty && why.isEmpty))
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(
                                            [area, why].where((s) => s.isNotEmpty).join(' · '),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: Voy.sub, fontSize: 11.5),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_rounded, color: Voy.brand, size: 24),
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
      ),
    );
  }
}
