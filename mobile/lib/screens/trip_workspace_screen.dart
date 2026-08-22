import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/app_config.dart';
import '../theme/app_theme.dart';
import '../models/trip_models.dart';
import '../models/trip_extras.dart';
import '../services/trip_extras_store.dart';
import 'itinerary_screen.dart';

/// A tabbed "trip workspace" — the single place that brings a trip together:
/// Map, Itinerary, an interactive Packing checklist, an Expense tracker with
/// splitting, and a Reservations manager. The three add-ons persist locally
/// per trip.
class TripWorkspaceScreen extends StatelessWidget {
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
  });

  @override
  Widget build(BuildContext context) {
    final store = TripExtrasStore(tripKey);
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: Voy.bg,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Trip Workspace',
                  style: TextStyle(color: Voy.ink, fontWeight: FontWeight.w800, fontSize: 17)),
              if (tripName.isNotEmpty)
                Text(tripName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Voy.sub, fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ),
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: Voy.brand,
            labelColor: Voy.brand,
            unselectedLabelColor: Voy.sub,
            labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
            tabs: [
              Tab(icon: Icon(Icons.map_rounded), text: 'Map'),
              Tab(icon: Icon(Icons.timeline_rounded), text: 'Itinerary'),
              Tab(icon: Icon(Icons.checklist_rounded), text: 'Packing'),
              Tab(icon: Icon(Icons.payments_rounded), text: 'Expenses'),
              Tab(icon: Icon(Icons.confirmation_number_rounded), text: 'Bookings'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _MapTab(plan: plan, start: start, end: end, waypoints: waypoints),
            ItineraryScreen(
              plan: plan,
              startAddress: startAddress,
              endAddress: endAddress,
              start: start,
              end: end,
              waypoints: waypoints,
              vehicleType: vehicle.type,
              vehicle: vehicle,
              travellers: travellers,
              tripStart: tripStart,
              initialItinerary: savedItinerary,
              embedded: true,
            ),
            _PackingTab(store: store),
            _ExpensesTab(store: store, travellers: travellers, currency: currency),
            _ReservationsTab(store: store),
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

    final total = _items.fold<double>(0, (s, e) => s + e.amount);
    final sym = currencySymbol(widget.currency);

    // Per-person owed totals (how much each person's share adds up to).
    final owed = <String, double>{};
    for (final e in _items) {
      final people = e.sharedWith.isEmpty ? _people : e.sharedWith;
      final share = people.isEmpty ? 0 : e.amount / people.length;
      for (final p in people) {
        owed[p] = (owed[p] ?? 0) + share;
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        backgroundColor: Voy.brand,
        foregroundColor: const Color(0xFF04211F),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add expense'),
      ),
      body: Column(
        children: [
          // Summary header
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Voy.brand.withValues(alpha: 0.20), Voy.violet.withValues(alpha: 0.16)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Voy.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total spent',
                    style: TextStyle(color: Voy.sub, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('$sym${_fmtMoney(total)}',
                    style: const TextStyle(color: Voy.ink, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                if (widget.travellers > 1 && owed.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(color: Voy.hairline, height: 1),
                  const SizedBox(height: 10),
                  const Text('SPLIT — EACH PERSON OWES',
                      style: TextStyle(color: Voy.sub, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in _people)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: Voy.surface2,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Voy.hairline),
                          ),
                          child: Text('$p · $sym${_fmtMoney(owed[p] ?? 0)}',
                              style: const TextStyle(color: Voy.ink, fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _items.isEmpty
                ? _emptyState(Icons.payments_rounded, 'No expenses yet',
                    'Track fuel, food, stays and more — split them across travellers.')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                    itemCount: _items.length,
                    itemBuilder: (ctx, i) {
                      final e = _items[_items.length - 1 - i]; // newest first
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
                      );
                    },
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
  const _ReservationsTab({required this.store});
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        backgroundColor: Voy.brand,
        foregroundColor: const Color(0xFF04211F),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add booking'),
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

  static const _types = ['flight', 'hotel', 'restaurant', 'activity', 'other'];

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
