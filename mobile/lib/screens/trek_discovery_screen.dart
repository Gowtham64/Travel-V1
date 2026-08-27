import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../config/app_config.dart';
import '../models/trip_models.dart';
import '../models/vehicles_data.dart';
import '../services/api_service.dart';
import '../widgets/app_design.dart';
import 'trip_planner_screen.dart';

/// AllTrails-style trek discovery, dressed in the app's cinematic design system:
/// animated background, liquid-glass surfaces, staggered reveals. Search a place,
/// filter real trails near it (OpenStreetMap), preview the route on a map, then
/// hand off into the fully-configured trip planner.
class TrekDiscoveryScreen extends StatefulWidget {
  const TrekDiscoveryScreen({super.key});

  @override
  State<TrekDiscoveryScreen> createState() => _TrekDiscoveryScreenState();
}

class _TrekDiscoveryScreenState extends State<TrekDiscoveryScreen> {
  static const String _bgUrl =
      'https://images.unsplash.com/photo-1551632811-561732d1e306?q=80&w=2000&auto=format&fit=crop';

  final _api = ApiService();
  final _searchController = TextEditingController();

  bool _loading = false;
  String? _error;
  String _searchedLabel = '';
  GeoPoint? _center;
  List<Trek> _treks = [];

  // Filters / sort
  double _radiusKm = 20;
  final Set<String> _difficulties = {}; // empty = all
  String _sort = 'nearest'; // nearest | longest | shortest

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _treks = [];
    });
    try {
      final place = _center != null && _searchedLabel == q
          ? _center!
          : await _api.geocode(q);
      final treks = await _api.searchTreks(
        lat: place.lat,
        lng: place.lng,
        radiusMeters: _radiusKm * 1000,
      );
      if (!mounted) return;
      setState(() {
        _center = place;
        _searchedLabel = q;
        _treks = treks;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Re-query when the radius changes (only meaningful once a place is chosen).
  Future<void> _reQueryRadius() async {
    if (_center == null) return;
    setState(() => _loading = true);
    try {
      final treks = await _api.searchTreks(
        lat: _center!.lat,
        lng: _center!.lng,
        radiusMeters: _radiusKm * 1000,
      );
      if (!mounted) return;
      setState(() => _treks = treks);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _matchesDifficulty(Trek t) {
    if (_difficulties.isEmpty) return true;
    final d = t.difficulty;
    if (d == null) return false;
    // "Hard" bucket also covers Very hard / Expert.
    if (_difficulties.contains('Hard') && (d == 'Hard' || d == 'Very hard' || d == 'Expert')) {
      return true;
    }
    return _difficulties.contains(d);
  }

  List<Trek> get _visible {
    final list = _treks.where(_matchesDifficulty).toList();
    switch (_sort) {
      case 'longest':
        list.sort((a, b) => (b.lengthKm ?? 0).compareTo(a.lengthKm ?? 0));
        break;
      case 'shortest':
        list.sort((a, b) => (a.lengthKm ?? double.infinity).compareTo(b.lengthKm ?? double.infinity));
        break;
      default:
        list.sort((a, b) => a.distanceFromSearchKm.compareTo(b.distanceFromSearchKm));
    }
    return list;
  }

  static Color difficultyColor(String? d) {
    switch (d) {
      case 'Easy':
        return const Color(0xFF22C55E);
      case 'Moderate':
        return const Color(0xFFEAB308);
      case 'Hard':
        return const Color(0xFFF97316);
      case 'Very hard':
      case 'Expert':
        return const Color(0xFFEF4444);
      default:
        return AppColors.accentLight;
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
        title: const Text('Discover treks'),
      ),
      body: AnimatedBackground(
        imageUrl: _bgUrl,
        overlayOpacity: 0.62,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              RevealIn(child: _searchCard()),
              const SizedBox(height: 16),
              if (_error != null) ...[
                RevealIn(child: _errorBanner()),
                const SizedBox(height: 12),
              ],
              ..._results(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchCard() {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Find trails near a place',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Coorg, Manali, Munnar…',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.08),
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 96,
              child: AccentButton(
                padding: const EdgeInsets.symmetric(vertical: 16),
                onPressed: _loading ? null : _search,
                child: const Text('Find'),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          // Radius
          Row(children: [
            const Icon(Icons.my_location, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            Text('Search radius: ${_radiusKm.round()} km',
                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
          ]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.accentLight,
              thumbColor: AppColors.accentLight,
              overlayColor: AppColors.accentLight.withOpacity(0.2),
              inactiveTrackColor: Colors.white.withOpacity(0.15),
            ),
            child: Slider(
              value: _radiusKm,
              min: 5,
              max: 60,
              divisions: 11,
              label: '${_radiusKm.round()} km',
              onChanged: (v) => setState(() => _radiusKm = v),
              onChangeEnd: (_) => _reQueryRadius(),
            ),
          ),
          // Difficulty
          Text('Difficulty', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final d in const ['Easy', 'Moderate', 'Hard'])
              _filterChip(
                label: d,
                selected: _difficulties.contains(d),
                color: difficultyColor(d),
                onTap: () => setState(() =>
                    _difficulties.contains(d) ? _difficulties.remove(d) : _difficulties.add(d)),
              ),
          ]),
          const SizedBox(height: 14),
          // Sort
          Row(children: [
            Text('Sort by', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
            const SizedBox(width: 12),
            for (final s in const [
              ['nearest', 'Nearest'],
              ['longest', 'Longest'],
              ['shortest', 'Shortest'],
            ])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _filterChip(
                  label: s[1],
                  selected: _sort == s[0],
                  color: AppColors.accentLight,
                  onTap: () => setState(() => _sort = s[0]),
                ),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.22) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : Colors.white.withOpacity(0.15), width: selected ? 1.4 : 1),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? color : Colors.white.withOpacity(0.8),
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
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

  List<Widget> _results() {
    if (_loading) {
      return [const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator()))];
    }
    if (_center == null) {
      return [
        RevealIn(
          delay: const Duration(milliseconds: 120),
          child: _hint(Icons.hiking_rounded, 'Find trails near anywhere',
              'Search a town, hill station, or park to discover real hiking and trekking routes around it.'),
        )
      ];
    }
    final visible = _visible;
    if (visible.isEmpty) {
      return [
        RevealIn(
          delay: const Duration(milliseconds: 120),
          child: _hint(Icons.search_off_rounded, 'No matching treks near $_searchedLabel',
              'Try widening the radius, clearing filters, or a nearby hill station. Coverage comes from OpenStreetMap and varies by region.'),
        )
      ];
    }
    return [
      RevealIn(
        delay: const Duration(milliseconds: 80),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 4),
          child: Text('${visible.length} treks near $_searchedLabel',
              style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      ),
      ...RevealIn.stagger(
        [for (final t in visible) _trekCard(t)],
        initial: const Duration(milliseconds: 120),
        step: const Duration(milliseconds: 55),
      ),
    ];
  }

  Widget _hint(IconData icon, String title, String subtitle) => GlassCard(
        padding: const EdgeInsets.all(28),
        child: Column(children: [
          Icon(icon, color: Colors.white.withOpacity(0.4), size: 52),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13, height: 1.4)),
        ]),
      );

  Widget _chip(IconData icon, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _trekCard(Trek t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => TrekDetailScreen(trek: t, bgUrl: _bgUrl))),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(t.name,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white54),
                  ]),
                  const SizedBox(height: 4),
                  Text(t.type, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _chip(Icons.place_outlined, '${t.distanceFromSearchKm.toStringAsFixed(1)} km away', AppColors.accentLight),
                    if (t.lengthKm != null) _chip(Icons.straighten, '${t.lengthKm!.toStringAsFixed(1)} km', const Color(0xFF8B5CF6)),
                    if (t.difficulty != null) _chip(Icons.terrain, t.difficulty!, difficultyColor(t.difficulty)),
                    if (t.hasPath) _chip(Icons.timeline, 'Trail mapped', const Color(0xFF22C55E)),
                  ]),
                  if (t.description != null) ...[
                    const SizedBox(height: 12),
                    Text(t.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12.5, height: 1.35)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Detail view: cinematic background, a map that draws the actual trail line,
/// stats, and a compact trip-options card that pre-configures the planner.
class TrekDetailScreen extends StatefulWidget {
  final Trek trek;
  final String bgUrl;
  const TrekDetailScreen({super.key, required this.trek, required this.bgUrl});

  @override
  State<TrekDetailScreen> createState() => _TrekDetailScreenState();
}

class _TrekDetailScreenState extends State<TrekDetailScreen> {
  late VehicleModel _vehicle = predefinedVehicles.firstWhere((v) => v.type == 'car');
  int _travellers = 2;
  late final TextEditingController _fuelController =
      TextEditingController(text: (_vehicle.tankCapacity * 0.6).toStringAsFixed(0));

  @override
  void dispose() {
    _fuelController.dispose();
    super.dispose();
  }

  LatLngBounds? _pathBounds() {
    if (!widget.trek.hasPath) return null;
    return LatLngBounds.fromPoints(widget.trek.path);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.trek;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppColors.obsidian,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(t.name, overflow: TextOverflow.ellipsis),
      ),
      body: AnimatedBackground(
        imageUrl: widget.bgUrl,
        overlayOpacity: 0.6,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: RevealIn.stagger([
              _mapCard(t),
              const SizedBox(height: 14),
              _statsCard(t),
              const SizedBox(height: 14),
              _optionsCard(),
              const SizedBox(height: 16),
              AccentButton(
                onPressed: _planTrip,
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.route_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('PLAN TRIP TO TRAILHEAD'),
                ]),
              ),
              const SizedBox(height: 10),
              Text('Trail data from OpenStreetMap. Verify access, permits and conditions before you go.',
                  style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 11.5)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _mapCard(Trek t) {
    final bounds = _pathBounds();
    return GlassCard(
      padding: const EdgeInsets.all(6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: 260,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: t.toLatLng(),
              initialZoom: 12,
              initialCameraFit: bounds != null
                  ? CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(28))
                  : null,
            ),
            children: [
              TileLayer(
                urlTemplate: AppConfig.hasMapboxToken
                    ? 'https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/tiles/256/{z}/{x}/{y}?access_token=${AppConfig.mapboxToken}'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.voyplan.app',
              ),
              if (t.hasPath)
                PolylineLayer(polylines: [
                  Polyline(points: t.path, strokeWidth: 4, color: const Color(0xFF22C55E)),
                ]),
              MarkerLayer(markers: [
                Marker(
                  point: t.hasPath ? t.path.first : t.toLatLng(),
                  width: 44,
                  height: 44,
                  child: const Icon(Icons.hiking_rounded, color: Color(0xFF22C55E), size: 38),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statsCard(Trek t) {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.name, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(t.type, style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 13)),
          const SizedBox(height: 16),
          Row(children: [
            _stat('Length', t.lengthKm != null ? '${t.lengthKm!.toStringAsFixed(1)} km' : '—'),
            _stat('Difficulty', t.difficulty ?? '—',
                color: _TrekDiscoveryScreenState.difficultyColor(t.difficulty)),
            _stat('Trailhead', '${t.distanceFromSearchKm.toStringAsFixed(1)} km'),
          ]),
          if (t.description != null) ...[
            const SizedBox(height: 18),
            Text(t.description!, style: TextStyle(color: Colors.white.withOpacity(0.82), fontSize: 14, height: 1.5)),
          ],
        ],
      ),
    );
  }

  Widget _optionsCard() {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Trip options', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Pre-fills the planner for the drive to the trailhead.',
              style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12)),
          const SizedBox(height: 16),
          // Vehicle
          Text('Vehicle', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<VehicleModel>(
                isExpanded: true,
                value: _vehicle,
                dropdownColor: AppColors.slate,
                iconEnabledColor: Colors.white70,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                items: [
                  for (final v in predefinedVehicles)
                    DropdownMenuItem(
                      value: v,
                      child: Text('${v.name}  ·  ${v.mileage.toStringAsFixed(0)} km/L',
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _vehicle = v;
                    _fuelController.text = (v.tankCapacity * 0.6).toStringAsFixed(0);
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            // Travellers
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Travellers', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
                const SizedBox(height: 6),
                Row(children: [
                  _stepBtn(Icons.remove, () => setState(() => _travellers = (_travellers - 1).clamp(1, 12))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text('$_travellers',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  _stepBtn(Icons.add, () => setState(() => _travellers = (_travellers + 1).clamp(1, 12))),
                ]),
              ]),
            ),
            const SizedBox(width: 16),
            // Current fuel
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Current fuel (L)', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: _fuelController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ],
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
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      );

  Widget _stat(String label, String value, {Color? color}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(),
              style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: color ?? Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
      );

  void _planTrip() {
    final fuel = double.tryParse(_fuelController.text);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TripPlannerScreen(
        initialDestination: widget.trek.toGeoPoint(),
        initialDestinationLabel: widget.trek.name,
        initialVehicleId: _vehicle.id,
        initialTravellers: _travellers,
        initialCurrentFuelLiters: fuel,
      ),
    ));
  }
}
