import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/api_service.dart';
import '../services/trip_extras_store.dart';
import '../services/trip_history_service.dart';
import '../models/trip_models.dart';
import '../widgets/app_design.dart';
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
        title: const Text('Saved Trips',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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

  Widget _buildTripCard({
    required dynamic trip,
    required String start,
    required String end,
    required VoidCallback onTap,
  }) {
    final vehicleType = (trip['vehicle_type'] ?? 'car').toString();
    final isBike = vehicleType == 'motorcycle';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: GlassCard(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: AppColors.accentGradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Icon(
                    isBike ? Icons.two_wheeler : Icons.directions_car_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trip['name'] ?? 'Trip',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.trip_origin,
                              color: AppColors.accentLight, size: 13),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '$start  →  $end',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isBike ? 'Motorcycle' : 'Car',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.45),
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded,
                      color: Colors.white.withOpacity(0.6)),
                  tooltip: 'Delete trip',
                  onPressed: () => _deleteCloudTrip(trip),
                ),
                Icon(Icons.chevron_right,
                    color: Colors.white.withOpacity(0.5)),
              ],
            ),
          ),
        ),
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
        _api.deleteTrip(id, session.accessToken);
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
      // …and from the local trip-history cache and tombstone set.
      await TripHistoryService.instance.deleteTrip(id, title: name);
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
