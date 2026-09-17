import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/api_service.dart';
import '../services/trip_extras_store.dart';
import '../services/trip_history_service.dart';
import '../models/trip_models.dart';
import '../widgets/app_design.dart';
import '../widgets/trip_modal.dart';
import 'saved_places_screen.dart';
import 'trip_screen.dart';
import 'day_planner_screen.dart';

class SavedTripsScreen extends StatefulWidget {
  const SavedTripsScreen({super.key});

  @override
  State<SavedTripsScreen> createState() => _SavedTripsScreenState();
}

class _SavedTripsScreenState extends State<SavedTripsScreen> {
  final _api = ApiService();
  final String _bgUrl =
      'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?q=80&w=2000&auto=format&fit=crop';
  bool _loading = true;
  bool _loadingTripDetails = false;
  String? _error;
  List<dynamic> _trips = [];
  List<Map<String, dynamic>> _localPlans = []; // day-by-day / AI itineraries saved on this device

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    // Local day-by-day / AI itineraries are available to everyone (no login).
    final localPlans = await TripExtrasStore.savedPlans();

    final session = Supabase.instance.client.auth.currentSession;
    List<dynamic> cloudTrips = [];
    String? err;
    if (session != null) {
      try {
        cloudTrips = await _api.getSavedTrips(session.accessToken);
      } catch (e) {
        err = e.toString();
      }
    }

    // Also load from synced TripHistoryService
    try {
      final historyItems = await TripHistoryService.instance.getHistory();
      final seenNames = <String>{};
      for (final ct in cloudTrips) {
        seenNames.add((ct['name'] ?? '').toString().toLowerCase());
      }
      for (final h in historyItems) {
        final title = h.title.isNotEmpty ? h.title : '${h.startAddress} to ${h.endAddress}';
        if (!seenNames.contains(title.toLowerCase())) {
          cloudTrips.add({
            'id': h.id,
            'name': title,
            'vehicle_type': h.vehicleType,
            'start_point': {'name': h.startAddress, 'lat': 12.9716, 'lng': 77.5946},
            'end_point': {
              'name': h.endAddress,
              'lat': 13.6288,
              'lng': 79.4192,
              'distanceKm': h.distanceKm,
              'durationMinutes': h.durationMinutes,
              'isRoundTrip': h.isRoundTrip,
            },
            'trip_stops': h.waypoints.map((w) => {'name': w}).toList(),
            'created_at': h.completedAt.toIso8601String(),
          });
          seenNames.add(title.toLowerCase());
        }
      }
    } catch (_) {}

    // Strict tombstone filtering: never resurrect or display deleted trips
    final deletedIds = await TripHistoryService.instance.getDeletedIds();
    final activeLocalPlans = localPlans.where((p) {
      final key = (p['key'] ?? '').toString();
      final name = (p['name'] ?? '').toString().trim().toLowerCase();
      return !deletedIds.contains(key) && !deletedIds.contains(name);
    }).toList();

    final activeCloudTrips = cloudTrips.where((ct) {
      final id = (ct['id'] ?? '').toString();
      final name = (ct['name'] ?? '').toString().trim().toLowerCase();
      final status = (ct['status'] ?? '').toString();
      final isDeleted = status == 'DELETED' || ct['deleted_at'] != null;
      return !isDeleted && !deletedIds.contains(id) && !deletedIds.contains(name);
    }).toList();

    if (!mounted) return;
    setState(() {
      _localPlans = activeLocalPlans;
      _trips = activeCloudTrips;
      // Only surface an error if we have nothing at all to show.
      _error = (activeLocalPlans.isEmpty && activeCloudTrips.isEmpty && err != null) ? err : null;
      _loading = false;
    });
  }

  Future<void> _openLocalPlan(Map<String, dynamic> p) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DayPlannerScreen(
        tripKey: (p['key'] ?? '').toString(),
        tripName: (p['name'] ?? 'My Trip Plan').toString(),
      ),
    ));
    _loadTrips(); // refresh counts/order on return
  }

  Future<void> _deleteLocalPlan(Map<String, dynamic> p) async {
    final key = (p['key'] ?? '').toString();
    final name = (p['name'] ?? '').toString();
    await TripHistoryService.instance.deleteTrip(key, title: name, tripKey: key);
    await TripExtrasStore.removeFromIndex(key);
    _loadTrips();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppColors.obsidian,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('My Trips', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 18)),
            Text('Manage your planned journeys, routes & navigation', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.55),
                Colors.black.withOpacity(0.0),
              ],
            ),
          ),
        ),
      ),
      body: AnimatedBackground(
        imageUrl: _bgUrl,
        overlayOpacity: 0.62,
        child: Stack(
          children: [
            SafeArea(child: _buildBody()),
            if (_loadingTripDetails)
              ClipRect(
                child: Container(
                  color: Colors.black.withOpacity(0.55),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppColors.accentLight),
                        SizedBox(height: 16),
                        Text(
                          'Loading Trip Details...',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Rebuilds a [Vehicle] from the spec persisted with a saved trip. Falls back
  /// to sensible type-based defaults for trips saved before specs were stored.
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

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.accentLight));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: RevealIn(
            child: GlassCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded,
                      color: Colors.redAccent, size: 40),
                  const SizedBox(height: 16),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 20),
                  AccentButton(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 14),
                    onPressed: () {
                      setState(() {
                        _loading = true;
                        _error = null;
                      });
                      _loadTrips();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_trips.isEmpty && _localPlans.isEmpty) {
      // Wrapped in a scrollable so the user can still pull-to-refresh here.
      return RefreshIndicator(
        color: AppColors.accentLight,
        onRefresh: _loadTrips,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.28),
            Center(
              child: RevealIn(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.map_outlined,
                        color: Colors.white.withOpacity(0.5), size: 56),
                    const SizedBox(height: 16),
                    const Text('No saved trips yet.',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text('Plan a trip and it will show up here.',
                        style: TextStyle(color: Colors.white.withOpacity(0.6))),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.accentLight,
      onRefresh: _loadTrips,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: kToolbarHeight + MediaQuery.of(context).padding.top,
          bottom: 24,
        ),
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                const Icon(Icons.favorite_rounded, color: Color(0xFFEC4899), size: 18),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Saved Places', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      Text('View bookmarked waterfalls, cafes & stays', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedPlacesScreen())),
                  icon: const Text('Open', style: TextStyle(color: Color(0xFFEC4899), fontWeight: FontWeight.bold, fontSize: 12)),
                  label: const Icon(Icons.arrow_forward_rounded, color: Color(0xFFEC4899), size: 14),
                ),
              ],
            ),
          ),
          if (_localPlans.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text('Your itineraries', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            for (int i = 0; i < _localPlans.length; i++)
              RevealIn(delay: Duration(milliseconds: 40 + i * 45), child: _localPlanCard(_localPlans[i])),
            const SizedBox(height: 10),
          ],
          if (_trips.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text('Saved road trips', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            for (int i = 0; i < _trips.length; i++)
              RevealIn(delay: Duration(milliseconds: 40 + i * 45), child: _cloudTripCard(_trips[i])),
          ],
        ],
      ),
    );
  }

  /// A locally-saved day-by-day / AI itinerary card.
  Widget _localPlanCard(Map<String, dynamic> p) {
    final name = (p['name'] ?? 'My Trip Plan').toString();
    final days = (p['days'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => _openLocalPlan(p),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Container(
                  width: 42, height: 42, alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.accentLight.withOpacity(0.18), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.event_note_rounded, color: AppColors.accentLight),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('$days day${days == 1 ? '' : 's'} · on this device', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12.5)),
                  ]),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, color: Colors.white.withOpacity(0.6)),
                  onPressed: () => _deleteLocalPlan(p),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cloudTripCard(dynamic trip) {
    final name = (trip['name'] as String?) ?? 'Trip';
    final parts = name.split(' to ');
    final start = (trip['start_point']?['name'] ?? trip['start_point']?['address'] ?? (parts.isNotEmpty ? parts.first : 'Start')).toString();
    final end = (trip['end_point']?['name'] ?? trip['end_point']?['address'] ?? (parts.length > 1 ? parts.last : 'End')).toString();

    return _buildTripCard(
      trip: trip,
      start: start,
      end: end,
      onTap: () async {
              final endMeta = trip['end_point'];
              final it = trip['itinerary'] ?? (endMeta is Map ? endMeta['itinerary'] : null);
              final tripKey = endMeta is Map ? endMeta['tripKey'] : null;

              // If it's a day-planner/itinerary trip, open in DayPlannerScreen directly
              if (tripKey != null || (it is List && it.isNotEmpty)) {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => DayPlannerScreen(
                    tripKey: tripKey?.toString() ?? 'smart_${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}',
                    tripName: name,
                  ),
                ));
                _loadTrips();
                return;
              }

              final startLat = (trip['start_point']?['lat'] as num?)?.toDouble() ?? 12.9716;
              final startLng = (trip['start_point']?['lng'] as num?)?.toDouble() ?? 77.5946;
              final endLat = (trip['end_point']?['lat'] as num?)?.toDouble() ?? 12.2958;
              final endLng = (trip['end_point']?['lng'] as num?)?.toDouble() ?? 76.6394;

              try {
                setState(() {
                  _loadingTripDetails = true;
                });

                final startPoint = GeoPoint(
                  lat: startLat,
                  lng: startLng,
                  name: start,
                );
                final endPoint = GeoPoint(
                  lat: endLat,
                  lng: endLng,
                  name: end,
                );

                final List<dynamic> stopsList = trip['trip_stops'] ?? [];
                stopsList.sort((a, b) => (a['order_index'] as int? ?? 0).compareTo(b['order_index'] as int? ?? 0));
                
                final List<GeoPoint> waypoints = stopsList.map((stop) => GeoPoint(
                  lat: (stop['lat'] as num).toDouble(),
                  lng: (stop['lng'] as num).toDouble(),
                  name: stop['name'] as String? ?? 'Waypoint',
                )).toList();

                final String vehicleType = trip['vehicle_type'] ?? 'car';
                // Prefer the exact vehicle spec saved with the trip; only fall
                // back to a type-based guess for older trips saved before specs
                // were persisted.
                final savedVehicle = trip['end_point'] is Map
                    ? trip['end_point']['vehicle']
                    : null;
                final vehicle = _vehicleFromSaved(savedVehicle, vehicleType);

                final plan = await _api.planTrip(
                  start: startPoint,
                  end: endPoint,
                  waypoints: waypoints,
                  vehicle: vehicle,
                );

                final endMeta = trip['end_point'];
                DateTime? savedStart;
                final ts = trip['trip_start'] ?? (endMeta is Map ? endMeta['tripStart'] : null);
                if (ts is String) savedStart = DateTime.tryParse(ts);
                List<Map<String, dynamic>>? savedItinerary;
                final it = trip['itinerary'] ?? (endMeta is Map ? endMeta['itinerary'] : null);
                if (it is List) {
                  savedItinerary = it.map((e) => (e as Map).cast<String, dynamic>()).toList();
                }

                if (mounted) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TripScreen(
                        plan: plan,
                        startAddress: start,
                        endAddress: end,
                        vehicleType: vehicleType,
                        poiCategories: const ['restaurant', 'attraction', 'hotel', 'fuel', 'ev', 'viewpoint'],
                        start: startPoint,
                        end: endPoint,
                        waypoints: waypoints,
                        vehicle: vehicle,
                        initialTripStart: savedStart,
                        savedItinerary: savedItinerary,
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to load trip: $e'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              } finally {
                if (mounted) {
                  setState(() {
                    _loadingTripDetails = false;
                  });
                }
              }
            },
    );
  }

  Future<void> _duplicateTrip(dynamic trip) async {
    try {
      final name = '${trip['name'] ?? 'Road Trip'} (Copy)';
      final startPt = trip['start_point'];
      final endPt = trip['end_point'];
      final startLat = (startPt is Map ? (startPt['lat'] as num?)?.toDouble() : null) ?? 12.9716;
      final startLng = (startPt is Map ? (startPt['lng'] as num?)?.toDouble() : null) ?? 77.5946;
      final endLat = (endPt is Map ? (endPt['lat'] as num?)?.toDouble() : null) ?? 12.2958;
      final endLng = (endPt is Map ? (endPt['lng'] as num?)?.toDouble() : null) ?? 76.6394;
      final startGeo = GeoPoint(lat: startLat, lng: startLng, name: (startPt is Map ? startPt['name']?.toString() : null) ?? 'Start');
      final endGeo = GeoPoint(lat: endLat, lng: endLng, name: (endPt is Map ? endPt['name']?.toString() : null) ?? 'End');
      final stops = trip['trip_stops'] ?? [];
      final List<GeoPoint> waypointGeos = (stops is List)
          ? stops.map((s) => GeoPoint(
                lat: (s is Map ? (s['lat'] as num?)?.toDouble() : null) ?? 0.0,
                lng: (s is Map ? (s['lng'] as num?)?.toDouble() : null) ?? 0.0,
                name: (s is Map ? s['name']?.toString() : null) ?? 'Stop',
              )).toList()
          : [];
      final vType = trip['vehicle_type'];
      
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        await _api.saveTrip(
          token: session.accessToken,
          name: name,
          start: startGeo,
          end: endGeo,
          vehicleType: vType?.toString() ?? 'car',
          waypoints: waypointGeos,
        );
      }
      await _loadTrips();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Duplicated "$name" successfully!'), backgroundColor: const Color(0xFF10B981)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to duplicate: $e')));
      }
    }
  }

  void _editTrip(dynamic trip) {
    final start = (trip['start_point']?['name'] ?? trip['start_point']?['address'] ?? '').toString();
    final end = (trip['end_point']?['name'] ?? trip['end_point']?['address'] ?? '').toString();
    final name = (trip['name'] ?? '').toString().toLowerCase();
    final isRound = name.contains('round') || name.contains('return') || (trip['end_point']?['isRoundTrip'] == true);

    showVoyPlanTripModal(
      context,
      initialMode: isRound ? 'round_trip' : 'one_way',
      initialOrigin: start.isNotEmpty ? start : null,
      initialDestination: end.isNotEmpty ? end : null,
    );
  }

  Widget _buildTripCard({
    required dynamic trip,
    required String start,
    required String end,
    required VoidCallback onTap,
  }) {
    final vehicleType = (trip['vehicle_type'] ?? 'car').toString();
    final isBike = vehicleType == 'motorcycle' || vehicleType == 'bike';
    final name = (trip['name'] ?? 'Road Trip').toString();
    final isRound = name.toLowerCase().contains('round') || name.toLowerCase().contains('return') || (trip['end_point']?['isRoundTrip'] == true);
    final tripTypeLabel = isRound ? 'ROUND TRIP' : 'ONE WAY';

    final endMeta = trip['end_point'] is Map ? trip['end_point'] : {};
    final distKm = (trip['distanceKm'] as num?)?.toDouble() ?? (endMeta['distanceKm'] as num?)?.toDouble() ?? 295.0;
    final durMin = (trip['durationMinutes'] as num?)?.toInt() ?? (endMeta['durationMinutes'] as num?)?.toInt() ?? 380;
    final durH = durMin ~/ 60;
    final durM = durMin % 60;

    final fuelCost = (trip['fuelCost'] as num?)?.toDouble() ?? (endMeta['fuelCost'] as num?)?.toDouble() ?? (distKm * 6.5);
    final tollCost = (trip['tollCost'] as num?)?.toDouble() ?? (endMeta['tollCost'] as num?)?.toDouble() ?? (distKm * 1.5);
    final totalBudget = fuelCost + tollCost;

    final List<dynamic> stops = trip['trip_stops'] ?? [];
    final status = (trip['status'] ?? endMeta['status'] ?? 'UPCOMING').toString().toUpperCase();

    Color statusColor = const Color(0xFF2563EB);
    if (status == 'ACTIVE') statusColor = const Color(0xFF10B981);
    if (status == 'COMPLETED') statusColor = const Color(0xFF8B5CF6);
    if (status == 'DRAFT') statusColor = const Color(0xFF64748B);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Icon, Name, Type Chip, and Delete
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: AppColors.accentGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isBike ? Icons.two_wheeler_rounded : Icons.directions_car_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: isRound ? const Color(0xFF8B5CF6).withValues(alpha: 0.2) : const Color(0xFF38BDF8).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              tripTypeLabel,
                              style: TextStyle(
                                color: isRound ? const Color(0xFFA78BFA) : const Color(0xFF38BDF8),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(color: statusColor, fontSize: 9.5, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        name,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, color: Color(0xFF94A3B8), size: 18),
                  tooltip: 'Duplicate Trip',
                  onPressed: () => _duplicateTrip(trip),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                  tooltip: 'Delete Trip',
                  onPressed: () => _deleteCloudTrip(trip),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Origin -> Destination
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.trip_origin_rounded, color: Color(0xFF38BDF8), size: 14),
                  const SizedBox(width: 6),
                  Expanded(child: Text(start, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600))),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.arrow_forward_rounded, color: Color(0xFF64748B), size: 14),
                  ),
                  const Icon(Icons.location_on_rounded, color: Color(0xFFF43F5E), size: 14),
                  const SizedBox(width: 6),
                  Expanded(child: Text(end, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600))),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Metrics Grid (Distance, Duration, Budget, Stops)
            Row(
              children: [
                Expanded(
                  child: _metricBox(Icons.straighten_rounded, '${distKm.toStringAsFixed(0)} km', 'Distance'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _metricBox(Icons.timer_rounded, '${durH}h ${durM}m', 'Est. Time'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _metricBox(Icons.account_balance_wallet_rounded, '₹${totalBudget.toStringAsFixed(0)}', 'Est. Budget'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _metricBox(Icons.place_rounded, '${stops.length}', 'Stops'),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Actions Row: Continue Trip, Start Navigation, Edit
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF38BDF8)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _editTrip(trip),
                    icon: const Icon(Icons.edit_road_rounded, color: Color(0xFF38BDF8), size: 15),
                    label: const Text('Edit Trip', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: onTap,
                    icon: const Icon(Icons.navigation_rounded, color: Colors.white, size: 15),
                    label: const Text('Start Nav', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricBox(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFF94A3B8), size: 12),
              const SizedBox(width: 4),
              Flexible(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold))),
            ],
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 10)),
        ],
      ),
    );
  }

  /// Delete a saved road trip from the cloud (and local cache), then refresh.
  Future<void> _deleteCloudTrip(dynamic trip) async {
    final id = (trip['id'] ?? '').toString();
    final name = (trip['name'] ?? 'this trip').toString();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16242C),
        title: const Text('Delete trip?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Remove "$name" from your saved trips? This can\'t be undone.',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    // Optimistically drop it from the list.
    setState(() => _trips.removeWhere((t) => (t['id'] ?? '').toString() == id));

    try {
      final name = (trip['name'] ?? '').toString();
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null && id.isNotEmpty) {
        await _api.deleteTrip(id, session.accessToken);
      }
      // Remove the specific cloud row by id (covers real cloud trips)…
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null && id.isNotEmpty) {
        try {
          await Supabase.instance.client
              .from('trips')
              .update({'status': 'DELETED', 'deleted_at': DateTime.now().toIso8601String()})
              .eq('id', id);
          await Supabase.instance.client.from('trips').delete().eq('id', id);
        } catch (e) {
          debugPrint('Cloud delete note: $e');
        }
      }
      // Purge from local stores and tombstones
      await TripExtrasStore.removeFromIndex(id);
      await TripHistoryService.instance.deleteTrip(id, title: name, tripKey: id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not delete trip: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
    if (mounted) _loadTrips();
  }
}
