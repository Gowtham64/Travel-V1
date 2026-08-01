import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../models/trip_models.dart';
import 'trip_planner_screen.dart';
import 'saved_trips_screen.dart';
import 'trip_screen.dart';

/// Voyplan home — the friendly entry point after login. Greets the traveller,
/// offers one clear "Plan a new trip" action, quick shortcuts, and a preview of
/// recent saved trips.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiService();
  List<dynamic> _trips = [];
  bool _loadingTrips = true;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _loadTrips();
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

  void _planTrip() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const TripPlannerScreen()));
  }

  Future<void> _logout() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;
    return Scaffold(
      backgroundColor: Voy.bg,
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: RefreshIndicator(
                  color: Voy.brand,
                  backgroundColor: Voy.surface,
                  onRefresh: _loadTrips,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(18, 14, 18, 40),
                    children: [
                      _topBar(),
                      const SizedBox(height: 22),
                      _heroCta(),
                      const SizedBox(height: 22),
                      _quickActions(),
                      const SizedBox(height: 26),
                      _recentHeader(),
                      const SizedBox(height: 12),
                      _recentTrips(isDesktop),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_opening)
            Container(
              color: Colors.black.withValues(alpha: 0.55),
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
        ],
      ),
    );
  }

  // ---- top bar: brand + greeting + avatar ----
  Widget _topBar() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(gradient: Voy.gradient, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.explore_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 10),
        const Text('Voyplan', style: TextStyle(color: Voy.ink, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        const Spacer(),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'saved') Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedTripsScreen()));
            if (v == 'logout') _logout();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'saved', child: Text('Saved trips')),
            PopupMenuItem(value: 'logout', child: Text('Log out')),
          ],
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Voy.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: Voy.hairline)),
            child: Text(_userName[0].toUpperCase(), style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ),
      ],
    );
  }

  // ---- hero call to action ----
  Widget _heroCta() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          Container(
            height: 210,
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFFEC4899), Color(0xFFF59E0B)],
                stops: [0.0, 0.4, 0.72, 1.0],
              ),
            ),
          ),
          Positioned(
            right: -20,
            top: -10,
            child: Icon(Icons.travel_explore_rounded, size: 190, color: Colors.white.withValues(alpha: 0.12)),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Colors.black.withValues(alpha: 0.35), Colors.transparent],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$_greeting, $_userName 👋',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.92), fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    const Text('Where to next?',
                        style: TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.1)),
                    const SizedBox(height: 4),
                    Text('Plan a road trip with routes, stops, budget & AI.',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                  ],
                ),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _planTrip,
                    icon: const Icon(Icons.add_rounded, size: 22),
                    label: const Text('Plan a new trip', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1A1240),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- quick actions ----
  Widget _quickActions() {
    return Row(
      children: [
        _quickTile(Icons.add_location_alt_rounded, 'Plan trip', Voy.brand, _planTrip),
        const SizedBox(width: 12),
        _quickTile(Icons.bookmark_rounded, 'Saved trips', Voy.violet,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedTripsScreen()))),
      ],
    );
  }

  Widget _quickTile(IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(color: Voy.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Voy.hairline)),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: const TextStyle(color: Voy.ink, fontSize: 14, fontWeight: FontWeight.w700))),
            ],
          ),
        ),
      ),
    );
  }

  // ---- recent trips ----
  Widget _recentHeader() {
    return Row(
      children: [
        const Text('Recent trips', style: TextStyle(color: Voy.ink, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        const Spacer(),
        if (_trips.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedTripsScreen())),
            child: const Text('See all'),
          ),
      ],
    );
  }

  Widget _recentTrips(bool isDesktop) {
    if (_loadingTrips) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Center(child: CircularProgressIndicator(color: Voy.brand)),
      );
    }
    if (_trips.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Voy.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: Voy.hairline)),
        child: Column(
          children: [
            Icon(Icons.map_outlined, color: Voy.sub.withValues(alpha: 0.7), size: 44),
            const SizedBox(height: 12),
            const Text('No trips yet', style: TextStyle(color: Voy.ink, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Plan your first road trip — it’ll show up here.',
                textAlign: TextAlign.center, style: TextStyle(color: Voy.sub, fontSize: 13)),
            const SizedBox(height: 14),
            ElevatedButton.icon(onPressed: _planTrip, icon: const Icon(Icons.add_rounded, size: 20), label: const Text('Plan a trip')),
          ],
        ),
      );
    }
    final show = _trips.take(4).toList();
    return Column(children: [for (final t in show) _tripCard(t)]);
  }

  Widget _tripCard(dynamic trip) {
    final name = (trip['name'] ?? 'Trip').toString();
    final start = (trip['start_point']?['address'] ?? 'Start').toString();
    final end = (trip['end_point']?['address'] ?? 'End').toString();
    final vehicleType = (trip['vehicle_type'] ?? 'car').toString();
    final isBike = vehicleType == 'motorcycle';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _openTrip(trip),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Voy.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: Voy.hairline)),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(gradient: Voy.gradient, borderRadius: BorderRadius.circular(14)),
                child: Icon(isBike ? Icons.two_wheeler_rounded : Icons.directions_car_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Voy.ink, fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(Icons.trip_origin, color: Voy.brand, size: 12),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text('$start  →  $end', maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Voy.sub, fontSize: 12.5)),
                        ),
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
      final eff = vehicleType == 'motorcycle' ? 40.0 : 18.0;
      final tank = vehicleType == 'motorcycle' ? 13.0 : 45.0;
      final vehicle = Vehicle(type: vehicleType, efficiencyKmPerLiter: eff, tankCapacityLiters: tank, currentFuelLiters: tank);

      final plan = await _api.planTrip(start: startPoint, end: endPoint, waypoints: waypoints, vehicle: vehicle);
      if (!mounted) return;
      setState(() => _opening = false);
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
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _opening = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load trip: $e')));
    }
  }
}
