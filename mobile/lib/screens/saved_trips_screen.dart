import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/api_service.dart';
import '../models/trip_models.dart';
import 'trip_screen.dart';

class SavedTripsScreen extends StatefulWidget {
  const SavedTripsScreen({super.key});

  @override
  State<SavedTripsScreen> createState() => _SavedTripsScreenState();
}

class _SavedTripsScreenState extends State<SavedTripsScreen> {
  final _api = ApiService();
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
      appBar: AppBar(title: const Text('Saved Trips')),
      body: Stack(
        children: [
          _buildBody(),
          if (_loadingTripDetails)
            Container(
              color: Colors.black.withOpacity(0.6),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
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
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
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
      );
    }

    if (_trips.isEmpty) {
      return const Center(child: Text('No saved trips yet.'));
    }

    return ListView.builder(
      itemCount: _trips.length,
      itemBuilder: (context, index) {
        final trip = _trips[index];
        final start = trip['start_point']?['address'] ?? 'Unknown Start';
        final end = trip['end_point']?['address'] ?? 'Unknown End';
        
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: const Icon(Icons.directions_car),
            title: Text(trip['name'] ?? 'Trip'),
            subtitle: Text('$start → $end\nVehicle: ${trip['vehicle_type']}'),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
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
}
