import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/api_service.dart';
import '../models/trip_models.dart';
import '../widgets/app_design.dart';
import 'trip_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      setState(() {
        _error = 'You must be logged in to view saved trips';
        _loading = false;
      });
      return;
    }

    try {
      final trips = await _api.getSavedTrips(session.accessToken);
      setState(() {
        _trips = trips;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
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

    if (_trips.isEmpty) {
      return Center(
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
      );
    }

    return ListView.builder(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: kToolbarHeight + MediaQuery.of(context).padding.top,
        bottom: 24,
      ),
      itemCount: _trips.length,
      itemBuilder: (context, index) {
        final trip = _trips[index];
        final start = trip['start_point']?['address'] ?? 'Unknown Start';
        final end = trip['end_point']?['address'] ?? 'Unknown End';

        return RevealIn(
          delay: Duration(milliseconds: 40 + index * 45),
          child: _buildTripCard(
            trip: trip,
            start: start,
            end: end,
            onTap: () async {
              final startLat = trip['start_point']?['lat'] as num?;
              final startLng = trip['start_point']?['lng'] as num?;
              final endLat = trip['end_point']?['lat'] as num?;
              final endLng = trip['end_point']?['lng'] as num?;

              if (startLat == null || startLng == null || endLat == null || endLng == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid saved trip coordinates.')),
                );
                return;
              }

              try {
                setState(() {
                  _loadingTripDetails = true;
                });

                final name = trip['name'] as String? ?? 'Trip';
                final parts = name.split(' to ');
                final startAddress = parts.isNotEmpty ? parts[0] : (trip['start_point']?['address'] as String? ?? 'Start');
                final endAddress = parts.length > 1 ? parts[1] : (trip['end_point']?['address'] as String? ?? 'End');

                final startPoint = GeoPoint(
                  lat: startLat.toDouble(),
                  lng: startLng.toDouble(),
                  name: startAddress,
                );
                final endPoint = GeoPoint(
                  lat: endLat.toDouble(),
                  lng: endLng.toDouble(),
                  name: endAddress,
                );

                final List<dynamic> stopsList = trip['trip_stops'] ?? [];
                stopsList.sort((a, b) => (a['order_index'] as int? ?? 0).compareTo(b['order_index'] as int? ?? 0));
                
                final List<GeoPoint> waypoints = stopsList.map((stop) => GeoPoint(
                  lat: (stop['lat'] as num).toDouble(),
                  lng: (stop['lng'] as num).toDouble(),
                  name: stop['name'] as String? ?? 'Waypoint',
                )).toList();

                final String vehicleType = trip['vehicle_type'] ?? 'car';
                final double efficiencyKmPerLiter = vehicleType == 'motorcycle' ? 40.0 : 18.0;
                final double tankCapacityLiters = vehicleType == 'motorcycle' ? 13.0 : 45.0;
                final vehicle = Vehicle(
                  type: vehicleType,
                  efficiencyKmPerLiter: efficiencyKmPerLiter,
                  tankCapacityLiters: tankCapacityLiters,
                  currentFuelLiters: tankCapacityLiters,
                );

                final plan = await _api.planTrip(
                  start: startPoint,
                  end: endPoint,
                  waypoints: waypoints,
                  vehicle: vehicle,
                );

                if (mounted) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
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
          ),
        );
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
                Icon(Icons.chevron_right,
                    color: Colors.white.withOpacity(0.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
