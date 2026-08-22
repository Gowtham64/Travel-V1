import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../models/trip_models.dart';
import 'trip_planner_screen.dart';
import 'saved_trips_screen.dart';
import 'atlas_screen.dart';
import 'trip_screen.dart';
import '../widgets/profile_menu.dart';
import 'account_screens.dart';

/// Voyplan home — glassmorphic, animated entry point after login.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _api = ApiService();
  List<dynamic> _trips = [];
  bool _loadingTrips = true;
  bool _opening = false;

  late final AnimationController _entrance;
  late final AnimationController _ambient;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();
    _ambient = AnimationController(vsync: this, duration: const Duration(seconds: 16))..repeat();
    _loadTrips();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _ambient.dispose();
    super.dispose();
  }

  Future<void> _loadTrips() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        final trips = await _api.getSavedTrips(session.accessToken);
        if (mounted) setState(() => _trips = trips);
      }
    } catch (_) {
      // best-effort; home still works without recent trips
    } finally {
      if (mounted) setState(() => _loadingTrips = false);
    }
  }

  String get _userName {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email == null || email.isEmpty) return 'Traveller';
    final name = email.split('@').first.replaceAll(RegExp(r'[._]'), ' ');
    return name.isEmpty ? 'Traveller' : name[0].toUpperCase() + name.substring(1);
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void _planTrip() => Navigator.push(context, MaterialPageRoute(builder: (_) => const TripPlannerScreen()));
  void _openSaved() => Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedTripsScreen()));

  Future<void> _logout() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
  }

  // Staggered slide-up + fade entrance.
  Widget _stagger(int index, Widget child) {
    final start = (index * 0.09).clamp(0.0, 0.6);
    final anim = CurvedAnimation(parent: _entrance, curve: Interval(start, (start + 0.55).clamp(0.0, 1.0), curve: Curves.easeOutCubic));
    return AnimatedBuilder(
      animation: anim,
      builder: (_, c) => Opacity(
        opacity: anim.value,
        child: Transform.translate(offset: Offset(0, 26 * (1 - anim.value)), child: c),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Voy.bg,
      body: Stack(
        children: [
          // Drifting aurora orbs behind everything.
          Positioned.fill(child: _aurora()),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: RefreshIndicator(
                  color: Voy.brand,
                  backgroundColor: Voy.surface,
                  onRefresh: _loadTrips,
                  child: ListView(
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 40),
                    children: [
                      _stagger(0, _topBar()),
                      const SizedBox(height: 22),
                      _stagger(1, _heroCta()),
                      const SizedBox(height: 18),
                      _stagger(2, _quickActions()),
                      if (_trips.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _stagger(3, _travelStats()),
                      ],
                      const SizedBox(height: 26),
                      _stagger(4, _recentHeader()),
                      const SizedBox(height: 12),
                      _stagger(5, _recentTrips()),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_opening) _openingOverlay(),
        ],
      ),
    );
  }

  // ---------- animated aurora background ----------
  Widget _aurora() {
    return AnimatedBuilder(
      animation: _ambient,
      builder: (_, __) {
        final t = _ambient.value * 2 * math.pi;
        return Stack(
          children: [
            _orb(Alignment(-0.85 + 0.18 * math.sin(t), -0.95 + 0.12 * math.cos(t)), Voy.violet, 360),
            _orb(Alignment(0.95, -0.5 + 0.22 * math.sin(t + 1.6)), Voy.brand, 320),
            _orb(Alignment(0.15 + 0.25 * math.cos(t), 0.95), Voy.pink, 380),
          ],
        );
      },
    );
  }

  Widget _orb(Alignment align, Color color, double size) {
    return Align(
      alignment: align,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color.withValues(alpha: 0.30), color.withValues(alpha: 0.0)]),
        ),
      ),
    );
  }

  // ---------- frosted-glass helper ----------
  Widget _glass({required Widget child, double radius = 22, EdgeInsetsGeometry? padding, Border? border}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(radius),
            border: border ?? Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: child,
        ),
      ),
    );
  }

  // ---------- top bar ----------
  Widget _topBar() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: Voy.gradient,
            borderRadius: BorderRadius.circular(13),
            boxShadow: [BoxShadow(color: Voy.brand.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: const Icon(Icons.explore_rounded, color: Colors.white, size: 23),
        ),
        const SizedBox(width: 11),
        const Text('Voyplan', style: TextStyle(color: Voy.ink, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
        const Spacer(),
        _Pressable(
          onTap: _openProfileMenu,
          child: _glass(
            radius: 13,
            padding: const EdgeInsets.all(0),
            child: SizedBox(
              width: 42,
              height: 42,
              child: Center(child: Text(_userName[0].toUpperCase(), style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.w800, fontSize: 16))),
            ),
          ),
        ),
      ],
    );
  }

  void _openProfileMenu() {
    final email = Supabase.instance.client.auth.currentUser?.email ?? 'traveller@voyplan.app';
    showProfileMenu(context, name: _userName, email: email, onSelect: _onMenuSelect);
  }

  void _onMenuSelect(String id, String label) {
    void go(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

    switch (id) {
      case 'generate':
        _planTrip();
        break;
      // All trip lists open Saved Trips for now.
      case 'saved':
      case 'upcoming':
      case 'ongoing':
      case 'completed':
      case 'drafts':
      case 'my_itineraries':
        _openSaved();
        break;
      case 'logout':
        _logout();
        break;
      case 'profile':
      case 'edit_profile':
      case 'appearance':
      case 'language':
      case 'currency':
      case 'security':
        go(const SettingsScreen());
        break;
      case 'currency_conv':
        go(const CurrencyConverterScreen());
        break;
      case 'atlas':
        go(const AtlasScreen());
        break;
      default:
        final cfg = configForMenu(id);
        if (cfg != null) {
          go(AccountCrudScreen(config: cfg));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$label — coming soon'), behavior: SnackBarBehavior.floating),
          );
        }
    }
  }

  // ---------- hero ----------
  Widget _heroCta() {
    return _Pressable(
      onTap: _planTrip,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          children: [
            // animated gradient sheen
            AnimatedBuilder(
              animation: _ambient,
              builder: (_, __) {
                final shift = math.sin(_ambient.value * 2 * math.pi);
                return Container(
                  height: 214,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(-1 - shift * 0.3, -1),
                      end: Alignment(1, 1 + shift * 0.3),
                      colors: const [Color(0xFF5B3BE8), Color(0xFF7C3AED), Color(0xFFEC4899), Color(0xFFF59E0B)],
                      stops: const [0.0, 0.38, 0.72, 1.0],
                    ),
                  ),
                );
              },
            ),
            Positioned(
              right: -26,
              top: -14,
              child: Icon(Icons.travel_explore_rounded, size: 210, color: Colors.white.withValues(alpha: 0.13)),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Colors.black.withValues(alpha: 0.32), Colors.transparent],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$_greeting, $_userName 👋',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.95), fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  const Text('Where to next?',
                      style: TextStyle(color: Colors.white, fontSize: 29, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.05)),
                  const SizedBox(height: 5),
                  Text('Plan a road trip with routes, stops, budget & AI.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 13.5)),
                  const SizedBox(height: 18),
                  // glass CTA
                  ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_rounded, size: 22, color: Color(0xFF1A1240)),
                            SizedBox(width: 9),
                            Text('Plan a new trip', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1A1240))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- quick actions ----------
  Widget _quickActions() {
    return Row(
      children: [
        Expanded(child: _quickTile(Icons.add_location_alt_rounded, 'Plan trip', Voy.brand, _planTrip)),
        const SizedBox(width: 12),
        Expanded(child: _quickTile(Icons.bookmark_rounded, 'Saved trips', Voy.violet, _openSaved)),
      ],
    );
  }

  Widget _quickTile(IconData icon, String label, Color color, VoidCallback onTap) {
    return _Pressable(
      onTap: onTap,
      child: _glass(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.65)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(13),
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 5))],
              ),
              child: Icon(icon, color: Colors.white, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(color: Voy.ink, fontSize: 14, fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
  }

  // ---------- travel stats ----------
  /// Aggregates quick stats from the user's saved trips: number of trips, total
  /// places (start + stops + end), and total straight-line distance.
  Widget _travelStats() {
    int places = 0;
    double km = 0;
    double haversine(double lat1, double lng1, double lat2, double lng2) {
      const r = 6371.0; // km
      double toRad(double d) => d * 3.141592653589793 / 180.0;
      final dLat = toRad(lat2 - lat1), dLng = toRad(lng2 - lng1);
      final a = (math.sin(dLat / 2) * math.sin(dLat / 2)) +
          math.cos(toRad(lat1)) * math.cos(toRad(lat2)) * (math.sin(dLng / 2) * math.sin(dLng / 2));
      return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    }

    for (final t in _trips) {
      final route = <List<double>>[];
      final sp = t['start_point'], ep = t['end_point'];
      final stops = (t['trip_stops'] as List?) ?? [];
      if (sp is Map && sp['lat'] != null && sp['lng'] != null) {
        route.add([(sp['lat'] as num).toDouble(), (sp['lng'] as num).toDouble()]);
      }
      for (final s in stops) {
        if (s is Map && s['lat'] != null && s['lng'] != null) {
          route.add([(s['lat'] as num).toDouble(), (s['lng'] as num).toDouble()]);
        }
      }
      if (ep is Map && ep['lat'] != null && ep['lng'] != null) {
        route.add([(ep['lat'] as num).toDouble(), (ep['lng'] as num).toDouble()]);
      }
      places += route.length;
      for (int i = 0; i < route.length - 1; i++) {
        km += haversine(route[i][0], route[i][1], route[i + 1][0], route[i + 1][1]);
      }
    }

    final distanceLabel = km >= 1000 ? '${(km / 1000).toStringAsFixed(1)}k' : km.toStringAsFixed(0);

    return Row(
      children: [
        Expanded(child: _statCard(Icons.route_rounded, '${_trips.length}', 'Trips', Voy.brand)),
        const SizedBox(width: 12),
        Expanded(child: _statCard(Icons.place_rounded, '$places', 'Places', Voy.violet)),
        const SizedBox(width: 12),
        Expanded(child: _statCard(Icons.straighten_rounded, '$distanceLabel km', 'Distance', Voy.coral)),
      ],
    );
  }

  Widget _statCard(IconData icon, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: Voy.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Voy.hairline),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          FittedBox(
            child: Text(value,
                style: const TextStyle(color: Voy.ink, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Voy.sub, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ---------- recent ----------
  Widget _recentHeader() {
    return Row(
      children: [
        const Text('Recent trips', style: TextStyle(color: Voy.ink, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        const Spacer(),
        if (_trips.isNotEmpty) TextButton(onPressed: _openSaved, child: const Text('See all')),
      ],
    );
  }

  Widget _recentTrips() {
    if (_loadingTrips) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: Center(child: CircularProgressIndicator(color: Voy.brand)));
    }
    if (_trips.isEmpty) {
      return _glass(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.map_outlined, color: Voy.sub.withValues(alpha: 0.7), size: 44),
            const SizedBox(height: 12),
            const Text('No trips yet', style: TextStyle(color: Voy.ink, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Plan your first road trip — it’ll show up here.', textAlign: TextAlign.center, style: TextStyle(color: Voy.sub, fontSize: 13)),
            const SizedBox(height: 14),
            ElevatedButton.icon(onPressed: _planTrip, icon: const Icon(Icons.add_rounded, size: 20), label: const Text('Plan a trip')),
          ],
        ),
      );
    }
    final show = _trips.take(4).toList();
    return Column(children: [for (int i = 0; i < show.length; i++) _tripCard(show[i], i)]);
  }

  Widget _tripCard(dynamic trip, int i) {
    final name = (trip['name'] ?? 'Trip').toString();
    // Fall back to the "A to B" name when the stored points have no address.
    final parts = name.split(' to ');
    final start = (trip['start_point']?['address'] ?? (parts.isNotEmpty ? parts.first : 'Start')).toString();
    final end = (trip['end_point']?['address'] ?? (parts.length > 1 ? parts.last : 'End')).toString();
    final vehicleType = (trip['vehicle_type'] ?? 'car').toString();
    final isBike = vehicleType == 'motorcycle';
    final hasItinerary = (trip['itinerary'] is List) || (trip['end_point'] is Map && trip['end_point']['itinerary'] is List);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _Pressable(
        onTap: () => _openTrip(trip),
        child: _glass(
          radius: 18,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: Voy.gradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Voy.brand.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 5))],
                ),
                child: Icon(isBike ? Icons.two_wheeler_rounded : Icons.directions_car_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Voy.ink, fontSize: 15, fontWeight: FontWeight.w700))),
                        if (hasItinerary) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(color: Voy.violet.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(999)),
                            child: const Text('Itinerary', style: TextStyle(color: Voy.violet, fontSize: 9.5, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(Icons.trip_origin, color: Voy.brand, size: 12),
                        const SizedBox(width: 5),
                        Expanded(child: Text('$start  →  $end', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Voy.sub, fontSize: 12.5))),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Voy.sub),
            ],
          ),
        ),
      ),
    );
  }

  Widget _openingOverlay() {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          color: Colors.black.withValues(alpha: 0.45),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Voy.brand),
                SizedBox(height: 16),
                Text('Loading your trip…', style: TextStyle(color: Voy.ink, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Rebuilds a [Vehicle] from the spec persisted with a saved trip, falling
  /// back to type-based defaults for trips saved before specs were stored.
  Vehicle _vehicleFromSaved(dynamic saved, String vehicleType) {
    if (saved is Map) {
      final eff = (saved['efficiencyKmPerLiter'] as num?)?.toDouble();
      final tank = (saved['tankCapacityLiters'] as num?)?.toDouble();
      final cur = (saved['currentFuelLiters'] as num?)?.toDouble();
      if (eff != null && eff > 0 && tank != null && tank > 0) {
        return Vehicle(
          type: (saved['type'] as String?) ?? vehicleType,
          efficiencyKmPerLiter: eff,
          tankCapacityLiters: tank,
          currentFuelLiters: cur ?? tank,
        );
      }
    }
    final eff = vehicleType == 'motorcycle' ? 40.0 : 18.0;
    final tank = vehicleType == 'motorcycle' ? 13.0 : 45.0;
    return Vehicle(
      type: vehicleType,
      efficiencyKmPerLiter: eff,
      tankCapacityLiters: tank,
      currentFuelLiters: tank,
    );
  }

  Future<void> _openTrip(dynamic trip) async {
    final startLat = trip['start_point']?['lat'] as num?;
    final startLng = trip['start_point']?['lng'] as num?;
    final endLat = trip['end_point']?['lat'] as num?;
    final endLng = trip['end_point']?['lng'] as num?;
    if (startLat == null || startLng == null || endLat == null || endLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid saved trip coordinates.')));
      return;
    }
    setState(() => _opening = true);
    try {
      final name = trip['name'] as String? ?? 'Trip';
      final parts = name.split(' to ');
      final startAddress = parts.isNotEmpty ? parts[0] : (trip['start_point']?['address'] as String? ?? 'Start');
      final endAddress = parts.length > 1 ? parts[1] : (trip['end_point']?['address'] as String? ?? 'End');
      final startPoint = GeoPoint(lat: startLat.toDouble(), lng: startLng.toDouble(), name: startAddress);
      final endPoint = GeoPoint(lat: endLat.toDouble(), lng: endLng.toDouble(), name: endAddress);

      final List<dynamic> stopsList = trip['trip_stops'] ?? [];
      stopsList.sort((a, b) => (a['order_index'] as int? ?? 0).compareTo(b['order_index'] as int? ?? 0));
      final waypoints = stopsList
          .map((s) => GeoPoint(lat: (s['lat'] as num).toDouble(), lng: (s['lng'] as num).toDouble(), name: s['name'] as String? ?? 'Waypoint'))
          .toList();

      final vehicleType = (trip['vehicle_type'] ?? 'car').toString();
      // Prefer the exact vehicle spec saved with the trip; fall back to a
      // type-based guess only for older trips saved before specs were persisted.
      final savedVehicle = trip['end_point'] is Map ? trip['end_point']['vehicle'] : null;
      final vehicle = _vehicleFromSaved(savedVehicle, vehicleType);

      final plan = await _api.planTrip(start: startPoint, end: endPoint, waypoints: waypoints, vehicle: vehicle);
      if (!mounted) return;
      setState(() => _opening = false);

      // Restore saved start date/time + AI itinerary (stored inside end_point,
      // with a fallback to dedicated columns if the DB has them).
      final endMeta = trip['end_point'];
      DateTime? savedStart;
      final ts = trip['trip_start'] ?? (endMeta is Map ? endMeta['tripStart'] : null);
      if (ts is String) savedStart = DateTime.tryParse(ts);
      List<Map<String, dynamic>>? savedItinerary;
      final it = trip['itinerary'] ?? (endMeta is Map ? endMeta['itinerary'] : null);
      if (it is List) {
        savedItinerary = it.map((e) => (e as Map).cast<String, dynamic>()).toList();
      }

      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TripScreen(
          plan: plan,
          startAddress: startAddress,
          endAddress: endAddress,
          vehicleType: vehicleType,
          poiCategories: const ['restaurant', 'attraction', 'hotel', 'fuel', 'ev', 'viewpoint'],
          start: startPoint,
          end: endPoint,
          waypoints: waypoints,
          vehicle: vehicle,
          initialTripStart: savedStart,
          savedItinerary: savedItinerary,
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _opening = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load trip: $e')));
    }
  }
}

/// Spring-scale press feedback used across the cards.
class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _Pressable({required this.child, required this.onTap});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
