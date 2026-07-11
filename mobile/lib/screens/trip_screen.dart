import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:share_plus/share_plus.dart';
import '../models/trip_models.dart';
import '../services/api_service.dart';

class TripScreen extends StatefulWidget {
  final TripPlan plan;
  final String startAddress;
  final String endAddress;
  final String vehicleType;
  final List<String> poiCategories;
  final GeoPoint start;
  final GeoPoint end;
  final List<GeoPoint> waypoints;
  final Vehicle vehicle;

  const TripScreen({
    super.key,
    required this.plan,
    required this.startAddress,
    required this.endAddress,
    required this.vehicleType,
    required this.poiCategories,
    required this.start,
    required this.end,
    required this.waypoints,
    required this.vehicle,
  });

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  bool _saving = false;
  bool _loadingPOIs = true;
  bool _recalculating = false;
  Map<String, List<PlaceOfInterest>> _pois = {};
  
  late TripPlan _currentPlan;
  late List<GeoPoint> _currentWaypoints;

  final PanelController _panelController = PanelController();

  @override
  void initState() {
    super.initState();
    _currentPlan = widget.plan;
    _currentWaypoints = List.from(widget.waypoints);
    _fetchPOIs();
  }

  Future<void> _fetchPOIs() async {
    try {
      final api = ApiService();
      final fetchedPois = await api.fetchPOIs(
        routeCoordinates: _currentPlan.coordinates,
        categories: widget.poiCategories,
      );
      if (mounted) {
        setState(() {
          _pois = fetchedPois;
          _loadingPOIs = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load POIs: $e');
      if (mounted) {
        setState(() {
          _loadingPOIs = false;
        });
      }
    }
  }

  Future<void> _saveTrip() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to save trips')),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final api = ApiService();
      await api.saveTrip(
        name: '${widget.startAddress} to ${widget.endAddress}',
        start: _currentPlan.coordinates.first,
        end: _currentPlan.coordinates.last,
        vehicleType: widget.vehicleType,
        token: session.accessToken,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trip saved successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save trip: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _shareTrip() {
    final hours = _currentPlan.durationMin ~/ 60;
    final minutes = _currentPlan.durationMin % 60;
    
    final StringBuffer sb = StringBuffer();
    sb.writeln('🚗 Road Trip Plan!');
    sb.writeln('From: ${widget.startAddress}');
    sb.writeln('To: ${widget.endAddress}');
    sb.writeln('Distance: ${_currentPlan.distanceKm.toStringAsFixed(0)} km');
    sb.writeln('Duration: ${hours}h ${minutes}m');
    sb.writeln('Vehicle: ${widget.vehicleType.toUpperCase()}');
    if (_pois.isNotEmpty) {
      sb.writeln('\n📍 Places to Visit:');
      _pois.forEach((category, places) {
        for (var place in places) {
          sb.writeln('- ${place.name} ($category)');
        }
      });
    }
    sb.writeln('\nCreated with Travel Planner App 🌍');
    
    Share.share(sb.toString(), subject: 'My Trip to ${widget.endAddress}');
  }

  void _confirmAddPOI(PlaceOfInterest place) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Stop?'),
        content: Text('Do you want to add ${place.name} as a stop on your route?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _addStopAndRecalculate(place);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _addStopAndRecalculate(PlaceOfInterest place) async {
    setState(() {
      _recalculating = true;
    });

    try {
      final newWaypoint = GeoPoint(lat: place.lat, lng: place.lng);
      final updatedWaypoints = List<GeoPoint>.from(_currentWaypoints)..add(newWaypoint);

      final api = ApiService();
      final newPlan = await api.planTrip(
        start: widget.start,
        end: widget.end,
        waypoints: updatedWaypoints,
        vehicle: widget.vehicle,
      );

      if (mounted) {
        setState(() {
          _currentPlan = newPlan;
          _currentWaypoints = updatedWaypoints;
          _recalculating = false;
        });
        _fetchPOIs(); // Optionally update POIs for the new route
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _recalculating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to recalculate route: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final routePoints = _currentPlan.coordinates.map((c) => c.toLatLng()).toList();
    final bounds = LatLngBounds.fromPoints(routePoints);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Your Trip', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.black.withOpacity(0.4),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        actions: [
          if (_saving || _recalculating)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else ...[
            Container(
              margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: IconButton(
                icon: const Icon(Icons.share, color: Colors.white),
                tooltip: 'Share Trip',
                onPressed: _shareTrip,
              ),
            ),
            Container(
              margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: IconButton(
                icon: const Icon(Icons.bookmark_add, color: Colors.white),
                tooltip: 'Save Trip',
                onPressed: _saveTrip,
              ),
            ),
          ],
        ],
      ),
      body: SlidingUpPanel(
        controller: _panelController,
        minHeight: 120, // To show the summary card always
        maxHeight: MediaQuery.of(context).size.height * 0.7,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        parallaxEnabled: true,
        parallaxOffset: .5,
        color: const Color(0xFF1A1A1A).withOpacity(0.9), // Dark glass feel
        boxShadow: [
          BoxShadow(blurRadius: 20, color: Colors.black.withOpacity(0.5)),
        ],
        panelBuilder: (sc) => _buildPanel(sc),
        body: Column(
          children: [
            Expanded(
              child: FlutterMap(
                options: MapOptions(
                  initialCameraFit: CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(80)),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/tiles/{z}/{x}/{y}?access_token=pk.eyJ1IjoiZ293dGhhbWVjNjQiLCJhIjoiY21yZzhnOG82MGh2dTJ6c2FuM3h6ZXdkayJ9.PmiHwk5A4-eSWu7zLYkSXQ',
                    userAgentPackageName: 'com.example.travel_app',
                    additionalOptions: const {
                      'accessToken': 'pk.eyJ1IjoiZ293dGhhbWVjNjQiLCJhIjoiY21yZzhnOG82MGh2dTJ6c2FuM3h6ZXdkayJ9.PmiHwk5A4-eSWu7zLYkSXQ',
                    },
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(points: routePoints, strokeWidth: 6, color: const Color(0xFF2E75B6)),
                    ],
                  ),
                  MarkerLayer(markers: _buildMarkers(context)),
                  RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution(
                        'OpenStreetMap contributors',
                        onTap: () {},
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 120), // Padding for the panel
          ],
        ),
      ),
    );
  }

  Widget _buildPanel(ScrollController sc) {
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 50,
          height: 6,
          decoration: BoxDecoration(
            color: Colors.grey[600],
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        const SizedBox(height: 16),
        _SummaryCard(plan: _currentPlan),
        const SizedBox(height: 8),
        const Divider(color: Colors.white24, thickness: 1, indent: 24, endIndent: 24),
        const SizedBox(height: 8),
        Expanded(
          child: _loadingPOIs
              ? const Center(child: CircularProgressIndicator())
              : _buildPOIList(sc),
        ),
      ],
    );
  }

  Widget _buildPOIList(ScrollController sc) {
    final allPois = <MapEntry<String, PlaceOfInterest>>[];
    _pois.forEach((category, places) {
      for (final p in places) {
        allPois.add(MapEntry(category, p));
      }
    });

    if (allPois.isEmpty) {
      return const Center(child: Text("No places of interest found nearby.", style: TextStyle(color: Colors.white70)));
    }

    return ListView.builder(
      controller: sc,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: allPois.length,
      itemBuilder: (context, index) {
        final poi = allPois[index];
        final category = poi.key;
        final place = poi.value;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: _getCategoryColor(category).withOpacity(0.2),
              radius: 24,
              child: Icon(_getCategoryIcon(category), color: _getCategoryColor(category), size: 22),
            ),
            title: Text(place.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
            subtitle: Text(category.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
            trailing: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF2E75B6).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                icon: const Icon(Icons.add_location_alt, size: 22, color: Color(0xFF2E75B6)),
                onPressed: () => _confirmAddPOI(place),
              ),
            ),
            onTap: () => _confirmAddPOI(place),
          ),
        );
      },
    );
  }

  List<Marker> _buildMarkers(BuildContext context) {
    final markers = <Marker>[];

    markers.add(_pin(_currentPlan.coordinates.first.toLatLng(), Icons.trip_origin, Colors.green));
    markers.add(_pin(_currentPlan.coordinates.last.toLatLng(), Icons.flag, Colors.red));

    for (final stop in _currentPlan.fuel.refuelStops) {
      markers.add(_pin(stop.toLatLng(), Icons.local_gas_station, Colors.orange));
    }

    _pois.forEach((category, places) {
      for (final place in places) {
        markers.add(_pin(
          place.toLatLng(),
          _getCategoryIcon(category),
          _getCategoryColor(category),
          onTap: () => _confirmAddPOI(place),
        ));
      }
    });

    return markers;
  }

  Marker _pin(LatLng point, IconData icon, Color color, {VoidCallback? onTap}) {
    return Marker(
      point: point,
      width: 32,
      height: 32,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: const Offset(0, 2))],
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'fuel': return Icons.local_gas_station;
      case 'hotel': return Icons.hotel;
      case 'restaurant': return Icons.restaurant;
      case 'attraction': return Icons.photo_camera;
      case 'hills': return Icons.landscape;
      case 'temple': return Icons.account_balance; // Place of worship
      case 'lake': return Icons.water;
      case 'river': return Icons.waves;
      case 'viewpoint': return Icons.visibility;
      default: return Icons.place;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'fuel': return Colors.orange;
      case 'hotel': return Colors.purple;
      case 'restaurant': return Colors.brown;
      case 'attraction': return Colors.teal;
      case 'hills': return Colors.green[800]!;
      case 'temple': return Colors.deepOrange;
      case 'lake': return Colors.blue;
      case 'river': return Colors.lightBlue;
      case 'viewpoint': return Colors.indigo;
      default: return Colors.grey;
    }
  }
}

class _SummaryCard extends StatelessWidget {
  final TripPlan plan;
  const _SummaryCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    final hours = plan.durationMin ~/ 60;
    final minutes = plan.durationMin % 60;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _stat('${plan.distanceKm.toStringAsFixed(0)} km', 'Distance'),
              _stat('${hours}h ${minutes}m', 'Driving time'),
              _stat('${plan.estimatedDays} day${plan.estimatedDays > 1 ? 's' : ''}', 'Trip length'),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Colors.white)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
      ],
    );
  }
}
