import 'dart:math';
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
  final Map<String, List<PlaceOfInterest>>? initialPois;

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
    this.initialPois,
  });

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  bool _saving = false;
  bool _loadingPOIs = true;
  bool _recalculating = false;
  Map<String, List<PlaceOfInterest>> _pois = {};
  final Map<String, String> _resolvedAddresses = {};
  final Set<String> _requestedAddresses = {};
  final _api = ApiService();
  
  late TripPlan _currentPlan;
  late List<GeoPoint> _currentWaypoints;

  final PanelController _panelController = PanelController();

  @override
  void initState() {
    super.initState();
    _currentPlan = widget.plan;
    _currentWaypoints = List.from(widget.waypoints);
    bool hasAllCategories = widget.initialPois != null && widget.initialPois!.isNotEmpty;
    if (hasAllCategories) {
      for (final cat in widget.poiCategories) {
        if (!widget.initialPois!.containsKey(cat) || widget.initialPois![cat] == null) {
          hasAllCategories = false;
          break;
        }
      }
    }

    if (hasAllCategories) {
      // Use pre-fetched POIs from the planner — no need to re-fetch
      _pois = widget.initialPois!;
      _loadingPOIs = false;
    } else {
      _fetchPOIs();
    }
  }

  @override
  void didUpdateWidget(TripScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plan != widget.plan) {
      _currentPlan = widget.plan;
      _currentWaypoints = List.from(widget.waypoints);
    }
    // If new initialPois are provided, use them without re-fetching
    if (widget.initialPois != null && widget.initialPois != oldWidget.initialPois) {
      setState(() {
        _pois = widget.initialPois!;
        _loadingPOIs = false;
      });
    }
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
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Login Required'),
          content: const Text('You must be logged in to save trips. Please sign in from the main menu.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
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

  void _shareTrip() async {
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
    
    try {
      await Share.share(sb.toString(), subject: 'My Trip to ${widget.endAddress}');
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Share Unavailable'),
            content: Text('Sharing is not supported on this browser or device. Error: $e'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      }
    }
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
      final newWaypoint = GeoPoint(lat: place.lat, lng: place.lng, name: place.name);
      
      final routeNodes = [widget.start, ..._currentWaypoints, widget.end];
      int bestIndex = 0;
      double minDetour = double.infinity;
      
      double _dist(GeoPoint p1, GeoPoint p2) {
        final dx = p1.lng - p2.lng;
        final dy = p1.lat - p2.lat;
        return sqrt(dx * dx + dy * dy);
      }

      for (int i = 0; i < routeNodes.length - 1; i++) {
        final p1 = routeNodes[i];
        final p2 = routeNodes[i + 1];
        final detour = _dist(p1, newWaypoint) + _dist(newWaypoint, p2) - _dist(p1, p2);
        if (detour < minDetour) {
          minDetour = detour;
          bestIndex = i;
        }
      }

      final updatedWaypoints = List<GeoPoint>.from(_currentWaypoints);
      updatedWaypoints.insert(bestIndex, newWaypoint);

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
        minHeight: 310, // Show FASTag + Cash (with subtitle) + Fuel card fully
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
        _SummaryCard(plan: _currentPlan, vehicle: widget.vehicle),
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
            subtitle: Builder(
              builder: (context) {
                final poiKey = '${place.lat},${place.lng}';
                final displayAddress = _resolvedAddresses[poiKey] ?? place.address ?? category.toUpperCase();
                
                final isCoordinateFallback = place.address == null || place.address!.contains('°') || place.address!.contains('N,') || place.address!.contains('S,');
                if (isCoordinateFallback && !_resolvedAddresses.containsKey(poiKey) && !_requestedAddresses.contains(poiKey)) {
                  _requestedAddresses.add(poiKey);
                  _api.reverseGeocode(place.lat, place.lng).then((addr) {
                    if (addr != null && mounted) {
                      setState(() {
                        _resolvedAddresses[poiKey] = addr;
                      });
                    }
                  });
                }

                return Text(
                  displayAddress,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.6)),
                );
              },
            ),
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

    // Start point pin
    markers.add(_pin(
      _currentPlan.coordinates.first.toLatLng(),
      Icons.trip_origin,
      Colors.green,
      label: widget.startAddress.isNotEmpty ? widget.startAddress : 'Start',
    ));

    // End point pin
    markers.add(_pin(
      _currentPlan.coordinates.last.toLatLng(),
      Icons.flag,
      Colors.red,
      label: widget.endAddress.isNotEmpty ? widget.endAddress : 'End',
    ));

    // Selected places to visit (waypoints) pins
    for (int i = 0; i < _currentWaypoints.length; i++) {
      final wp = _currentWaypoints[i];
      final wpKey = '${wp.lat},${wp.lng}';
      final name = wp.name ?? _resolvedAddresses[wpKey] ?? 'Stop ${i + 1}';
      markers.add(_pin(
        wp.toLatLng(),
        Icons.location_on,
        const Color(0xFF2E75B6),
        label: name,
      ));
    }

    return markers;
  }

  Marker _pin(LatLng point, IconData icon, Color color, {VoidCallback? onTap, String? label}) {
    return Marker(
      point: point,
      width: label != null ? 120 : 40,
      height: label != null ? 60 : 40,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, spreadRadius: 2),
                  BoxShadow(color: Colors.black26, blurRadius: 4, offset: const Offset(0, 2)),
                ],
                border: Border.all(color: color, width: 2.5),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
          ],
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
  final Vehicle vehicle;
  
  const _SummaryCard({required this.plan, required this.vehicle});

  String _estimateFuelCost(double distance, Vehicle vehicle, String? currency) {
    final eff = vehicle.efficiencyKmPerLiter > 0 ? vehicle.efficiencyKmPerLiter : 15.0;
    final liters = distance / eff;
    final isUSD = currency == 'USD' || currency == 'USD ';
    final fuelPrice = isUSD ? 1.05 : 102.0; // $1.05 per liter or ₹102 per liter
    final cost = liters * fuelPrice;
    final currSymbol = isUSD ? '\$' : '₹';
    return '$currSymbol ${cost.toStringAsFixed(0)}';
  }

  /// Returns display string for toll cost.
  /// - null toll = data unavailable (API quota exhausted)
  /// - hasTolls = false = confirmed no tolls on route
  /// - hasTolls = true = shows estimated range
  String _tollDisplay(TollEstimate? toll) {
    if (toll == null) return 'Checking...';
    if (!toll.hasTolls) return 'No Tolls';
    final curr = toll.currency.isNotEmpty ? toll.currency : 'INR';
    if (toll.minTollCost != null && toll.maxTollCost != null && toll.maxTollCost! > toll.minTollCost!) {
      return '$curr ${toll.minTollCost!.toStringAsFixed(0)}–${toll.maxTollCost!.toStringAsFixed(0)}';
    }
    if (toll.minTollCost != null) {
      return '~$curr ${toll.minTollCost!.toStringAsFixed(0)}';
    }
    return 'Has Tolls';
  }

  @override
  Widget build(BuildContext context) {
    final hours = plan.durationMin ~/ 60;
    final minutes = plan.durationMin % 60;
    final currency = plan.toll?.currency;

    final toll = plan.toll;
    final curr = (toll?.currency.isNotEmpty == true) ? toll!.currency : 'INR';
    final fuelDisplay = toll?.fuelCost != null && toll!.fuelCost! > 0
        ? '$curr ${toll.fuelCost!.toStringAsFixed(0)}'
        : _estimateFuelCost(plan.distanceKm, vehicle, currency);

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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              children: [
                // FASTag toll row
                _feeRow(
                  icon: Icons.contactless,
                  iconColor: const Color(0xFF00E5A0),
                  label: 'FASTag Fees',
                  badge: 'FASTAG',
                  badgeColor: const Color(0xFF00E5A0),
                  value: toll == null
                      ? 'Checking...'
                      : (!toll.hasTolls
                          ? 'No Tolls'
                          : (toll.fastagTollCost != null
                              ? '$curr ${toll.fastagTollCost!.toStringAsFixed(0)}'
                              : (toll.minTollCost != null
                                  ? '$curr ${toll.minTollCost!.toStringAsFixed(0)}'
                                  : 'Has Tolls'))),
                ),
                const Divider(color: Colors.white12, height: 16),
                // Cash toll row
                _feeRow(
                  icon: Icons.toll,
                  iconColor: const Color(0xFFFF6B6B),
                  label: 'Cash Toll',
                  badge: 'CASH',
                  badgeColor: const Color(0xFFFF6B6B),
                  subtitle: '2× FASTag rate (NHAI)',
                  value: toll == null
                      ? 'Checking...'
                      : (!toll.hasTolls
                          ? 'No Tolls'
                          : (toll.cashTollCost != null
                              ? '$curr ${toll.cashTollCost!.toStringAsFixed(0)}'
                              : (toll.minTollCost != null
                                  ? '$curr ${(toll.minTollCost! * 2).toStringAsFixed(0)}'
                                  : 'Has Tolls'))),
                ),
                const Divider(color: Colors.white12, height: 16),
                // Fuel cost row
                _feeRow(
                  icon: Icons.local_gas_station,
                  iconColor: Colors.orangeAccent,
                  label: 'Fuel Cost',
                  badge: 'EST.',
                  badgeColor: Colors.orangeAccent,
                  value: fuelDisplay,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _feeRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String badge,
    required Color badgeColor,
    required String value,
    String? subtitle,
  }) {
    // We use a basic Row with Spacer. This is robust across mobile and desktop.
    // We changed the label "FASTag Toll" to "FASTag Fees" (if passed) in the caller to verify cache busting.
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      margin: const EdgeInsets.symmetric(vertical: 4),
      width: double.infinity,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 10),
          // Label and badge
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.75),
                          fontWeight: FontWeight.w500)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(badge,
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: badgeColor,
                            letterSpacing: 0.5)),
                  ),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withOpacity(0.4))),
              ],
            ],
          ),
          // Takes up all remaining space
          const Spacer(),
          // Value
          Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: iconColor,
            ),
          ),
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

  Widget _statItem(BuildContext context, IconData icon, Color iconColor, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
