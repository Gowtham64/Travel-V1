import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../models/trip_models.dart';
import '../models/car_mode_models.dart';
import '../services/api_service.dart';
import '../services/car_guidance_service.dart';
import '../services/car_platform_channel.dart';
import '../widgets/three_d_map.dart';
import '../widgets/car_mode_overlay.dart';

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
  final bool isEmbedded;
  /// Optional finer-grained key for choosing the 3D model (e.g. 'scooter' vs the
  /// generic 'motorcycle'). Falls back to [vehicle].type when null.
  final String? modelSubtype;

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
    this.isEmbedded = false,
    this.modelSubtype,
  });

  @override
  State<TripScreen> createState() => _TripScreenState();
}

enum MapStyle { outdoors2D, satellite2D, satellite3D }

class _TripScreenState extends State<TripScreen> with TickerProviderStateMixin {
  // Drives the staggered slide/fade entrance of the map control overlays.
  late final AnimationController _overlayCtrl;
  bool _saving = false;
  bool _loadingPOIs = true;
  bool _recalculating = false;
  MapStyle _mapStyle = MapStyle.satellite3D;
  Map<String, List<PlaceOfInterest>> _pois = {};
  bool _isCarMode = false;
  final CarGuidanceService _carGuidance = CarGuidanceService();
  
  final MapController _mapController = MapController();
  bool _isPlayingAnimation = false;
  bool _isPreviewMode = false;
  // Live GPS navigation (Start Trip) — driven by the device location stream
  // rather than the simulated ticker used by Preview.
  bool _isLiveNavigating = false;
  StreamSubscription<Position>? _positionStream;
  double _liveSpeedKmh = 0.0;
  bool _navSoundOn = true;
  double _liveRemainingKm = 0.0;
  int _liveRemainingMin = 0;
  int _animationIndex = 0;
  LatLng? _animatedVehiclePosition;
  double _vehicleRotation = 0.0;
  double _currentSpeedModifier = 1.0;
  Timer? _animationTimer;
  Ticker? _ticker;
  bool _isSlowingDown = false;
  bool _isTurningLeft = false;
  bool _isTurningRight = false;
  final Set<String> _visitedStops = {};
  int _pauseTicksRemaining = 0;
  PlaceOfInterest? _activeStopHighlight;
  bool _isTollStop = false;
  bool _showCinematicOverlay = false;
  double _eventZoom = 15.5;
  double _tripProgressPercent = 0.0;
  final Map<String, String> _resolvedAddresses = {};
  final Set<String> _requestedAddresses = {};
  final _api = ApiService();
  
  late TripPlan _currentPlan;
  late List<GeoPoint> _currentWaypoints;

  @override
  void initState() {
    super.initState();
    _overlayCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    )..forward();
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

    // Headless test hook: auto-start the 3D preview so screenshots can verify
    // the 3D vehicle without needing to tap the CanvasKit-painted button.
    if (kIsWeb && Uri.base.toString().contains('test_preview=true')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) _startAnimation(preview: true);
        });
      });
    }
    if (kIsWeb && Uri.base.toString().contains('car_mode=true')) {
      _isCarMode = true;
    }
  }

  @override
  void dispose() {
    _overlayCtrl.dispose();
    _animationTimer?.cancel();
    _ticker?.dispose();
    _positionStream?.cancel();
    super.dispose();
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

  /// Builds a self-contained shareable URL that encodes the whole trip (start,
  /// end, waypoints, vehicle) so anyone who opens it re-plans the same trip.
  String? _buildShareLink() {
    try {
      final payload = {
        's': [widget.start.lat, widget.start.lng],
        'e': [widget.end.lat, widget.end.lng],
        'w': widget.waypoints.map((w) => [w.lat, w.lng]).toList(),
        'v': {
          't': widget.vehicle.type,
          'e': widget.vehicle.efficiencyKmPerLiter,
          'tk': widget.vehicle.tankCapacityLiters,
          'cf': widget.vehicle.currentFuelLiters,
        },
        'sa': widget.startAddress,
        'ea': widget.endAddress,
      };
      final encoded = base64Url.encode(utf8.encode(jsonEncode(payload)));
      return 'https://gowtham64.github.io/Travel-V1/app/?trip=$encoded';
    } catch (_) {
      return null;
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
    final link = _buildShareLink();
    if (link != null) {
      sb.writeln('\n🔗 Open this trip:');
      sb.writeln(link);
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
    final fullRoutePoints = _currentPlan.coordinates.map((c) => c.toLatLng()).toList();
    
    // Mathematically calculate initial center and zoom to bypass layout race conditions
    LatLng mapCenter = const LatLng(20.5937, 78.9629);
    double mapZoom = 4.5;
    if (fullRoutePoints.length >= 2) {
      final lats = fullRoutePoints.map((p) => p.latitude).toList();
      final lngs = fullRoutePoints.map((p) => p.longitude).toList();
      final midLat = lats.reduce((a, b) => a + b) / lats.length;
      final midLng = lngs.reduce((a, b) => a + b) / lngs.length;
      mapCenter = LatLng(midLat, midLng);
      
      final latSpan = lats.reduce((a, b) => a > b ? a : b) - lats.reduce((a, b) => a < b ? a : b);
      final lngSpan = lngs.reduce((a, b) => a > b ? a : b) - lngs.reduce((a, b) => a < b ? a : b);
      final span = latSpan > lngSpan ? latSpan : lngSpan;
      mapZoom = span < 0.5 ? 12.0 : span < 2 ? 9.0 : span < 5 ? 7.0 : span < 10 ? 5.5 : 4.5;
    }

    // During the simulated preview we draw a growing trail; during live GPS
    // navigation we keep the full route visible so the road ahead is shown.
    final routePoints = (_isPlayingAnimation && !_isLiveNavigating)
        ? fullRoutePoints.take(_animationIndex + 1).toList()
        : fullRoutePoints;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 900;
    final isMobile = !isDesktop;

    final Widget rawMapWidget = _mapStyle == MapStyle.satellite3D
        ? ThreeDMap(
            key: const ValueKey('mapbox-3d-map'),
            routePoints: _currentPlan.coordinates,
            pois: _pois,
            start: widget.start,
            end: widget.end,
            waypoints: _currentWaypoints,
            useSatellite: true,
            vehicleType: widget.modelSubtype ?? widget.vehicle.type,
            animatedVehiclePosition: _animatedVehiclePosition != null
                ? GeoPoint(lat: _animatedVehiclePosition!.latitude, lng: _animatedVehiclePosition!.longitude)
                : null,
            vehicleRotation: _vehicleRotation,
            speed: _currentSpeedModifier,
            customZoom: _eventZoom,
            onAddWaypoint: (place) {
              _confirmAddPOI(place);
            },
          )
        : FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: mapCenter,
              initialZoom: mapZoom,
            ),
            children: [
              TileLayer(
                urlTemplate: _mapStyle == MapStyle.satellite2D
                    ? 'https://api.mapbox.com/styles/v1/mapbox/satellite-streets-v12/tiles/256/{z}/{x}/{y}?access_token=pk.eyJ1IjoiZ293dGhhbWVjNjQiLCJhIjoiY21yZzhnOG82MGh2dTJ6c2FuM3h6ZXdkayJ9.PmiHwk5A4-eSWu7zLYkSXQ'
                    : 'https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/tiles/256/{z}/{x}/{y}?access_token=pk.eyJ1IjoiZ293dGhhbWVjNjQiLCJhIjoiY21yZzhnOG82MGh2dTJ6c2FuM3h6ZXdkayJ9.PmiHwk5A4-eSWu7zLYkSXQ',
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
          );

    final mapWidget = rawMapWidget;

    if (widget.isEmbedded) {
      return _buildMapStackWithOverlays(mapWidget, topPadding: 24.0, rightPadding: 24.0);
    }

    final appBarWidget = AppBar(
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
    );

    if (isDesktop) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: appBarWidget,
        body: Row(
          children: [
            // Left sidebar: Details (Summary + POIs)
            Container(
              width: 420,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                border: Border(right: BorderSide(color: Colors.white.withOpacity(0.1))),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  _SummaryCard(plan: _currentPlan, vehicle: widget.vehicle),
                  const SizedBox(height: 12),
                  _buildDriveActions(),
                  const SizedBox(height: 10),
                  _buildTripActions(),
                  const SizedBox(height: 8),
                  const Divider(color: Colors.white24, thickness: 1, indent: 24, endIndent: 24),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _loadingPOIs
                        ? const Center(child: CircularProgressIndicator())
                        : _buildPOIList(null),
                  ),
                ],
              ),
            ),
            // Right side: Map
            Expanded(
              child: _buildMapStackWithOverlays(mapWidget, topPadding: 24.0, rightPadding: 24.0),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: appBarWidget,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top portion: Map
          Expanded(
            flex: 50, // 50% height for Map
            child: _buildMapStackWithOverlays(mapWidget, topPadding: 16.0, rightPadding: 16.0),
          ),
          // Bottom portion: Details (Summary + POIs)
          Expanded(
            flex: 50, // 50% height for Details
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
              ),
              child: (_isPlayingAnimation && (_activeStopHighlight != null || _isTollStop))
                  ? Center(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(horizontal: 24, vertical: isMobile ? 4 : 12),
                        child: _buildStopHighlightCard(0.0),
                      ),
                    )
                  // Whole details panel scrolls as one unit so the weather strip and
                  // budget card below the summary are always reachable on small screens.
                  : SingleChildScrollView(
                      child: Column(
                        children: [
                          const SizedBox(height: 16),
                          _SummaryCard(plan: _currentPlan, vehicle: widget.vehicle),
                          const SizedBox(height: 12),
                          _buildDriveActions(),
                          const SizedBox(height: 10),
                          _buildTripActions(),
                          const SizedBox(height: 8),
                          const Divider(color: Colors.white24, thickness: 1, indent: 24, endIndent: 24),
                          const SizedBox(height: 8),
                          if (_loadingPOIs)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 28),
                              child: Column(
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 12),
                                  Text(
                                    "Finding nearby food, fuel & stays...",
                                    style: TextStyle(color: Colors.white60, fontSize: 13),
                                  ),
                                ],
                              ),
                            )
                          else
                            _buildPOIList(null, shrinkWrap: true),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMapStyleSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Widget buildStyleCard(MapStyle style, String title, IconData icon, String description) {
              final isSelected = _mapStyle == style;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _mapStyle = style;
                    });
                    setModalState(() {});
                    Navigator.pop(context);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF2E75B6).withOpacity(0.15) : Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF2E75B6) : Colors.white.withOpacity(0.1),
                        width: isSelected ? 2.0 : 1.0,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          color: isSelected ? const Color(0xFF2E75B6) : Colors.white70,
                          size: 32,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          title,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 9,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Select Map Style",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      buildStyleCard(
                        MapStyle.outdoors2D,
                        "2D Map",
                        Icons.map,
                        "Standard view",
                      ),
                      buildStyleCard(
                        MapStyle.satellite2D,
                        "Satellite",
                        Icons.satellite_alt,
                        "High res photo",
                      ),
                      buildStyleCard(
                        MapStyle.satellite3D,
                        "3D Map",
                        Icons.terrain,
                        "3D navigation",
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLayersButton() {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A).withOpacity(0.9),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _showMapStyleSheet,
          child: const Icon(
            Icons.layers,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }



  Widget _buildPOIList(ScrollController? sc, {bool shrinkWrap = false}) {
    final allPois = <MapEntry<String, PlaceOfInterest>>[];
    _pois.forEach((category, places) {
      for (final p in places) {
        allPois.add(MapEntry(category, p));
      }
    });

    if (allPois.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text("No places of interest found nearby.", style: TextStyle(color: Colors.white70))),
      );
    }

    return ListView.builder(
      controller: sc,
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
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

    // End point pin (pop up when reached)
    if (!_isPlayingAnimation || _animationIndex >= _currentPlan.coordinates.length - 2) {
      markers.add(_pin(
        _currentPlan.coordinates.last.toLatLng(),
        Icons.flag,
        Colors.red,
        label: widget.endAddress.isNotEmpty ? widget.endAddress : 'End',
      ));
    }

    // Selected places to visit (waypoints) pins (pop up as passed)
    for (int i = 0; i < _currentWaypoints.length; i++) {
      final wp = _currentWaypoints[i];
      if (!_isPointVisited(wp)) continue;
      
      final wpKey = '${wp.lat},${wp.lng}';
      final name = wp.name ?? _resolvedAddresses[wpKey] ?? 'Stop ${i + 1}';
      markers.add(_pin(
        wp.toLatLng(),
        Icons.location_on,
        const Color(0xFF2E75B6),
        label: name,
      ));
    }

    // Animated vehicle marker using 3D Asset or Emoji and Pulsing Ring
    if (_animatedVehiclePosition != null) {
      final isCar = widget.vehicle.type.toLowerCase() == 'car' || widget.vehicle.type.toLowerCase() == 'suv';
      markers.add(Marker(
        point: _animatedVehiclePosition!,
        width: 50,
        height: 50,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const _PulsingRing(),
            // Soft contact shadow so the vehicle reads as sitting on the road.
            Positioned(
              bottom: 6,
              child: Container(
                width: 24,
                height: 7,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.28),
                  borderRadius: BorderRadius.circular(50),
                ),
              ),
            ),
            _DrivingWobble(
              child: isCar
                  ? Transform.rotate(
                      angle: (_isPlayingAnimation ? 0.0 : _vehicleRotation) + (3 * pi / 4), // 135 degree offset for SW isometric car
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Image.asset(
                            'assets/images/isometric_car.png',
                            width: 28,
                            height: 28,
                            fit: BoxFit.contain,
                          ),
                          // Subtle rear brake lights (UR corner of SW car)
                          if (_isSlowingDown)
                            Positioned(
                              top: 2,
                              right: 2,
                              child: Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.red.withOpacity(0.8),
                                      blurRadius: 4,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          // Left Indicator (bottom-right front corner of SW car)
                          if (_isTurningLeft)
                            const Positioned(
                              bottom: 3,
                              right: 3,
                              child: _BlinkingIndicator(),
                            ),
                          // Right Indicator (top-left front corner of SW car)
                          if (_isTurningRight)
                            const Positioned(
                              top: 3,
                              left: 3,
                              child: _BlinkingIndicator(),
                            ),
                        ],
                      ),
                    )
                  : Transform.rotate(
                      angle: (_isPlayingAnimation ? 0.0 : _vehicleRotation) + (pi / 2), // 90 degree offset for emojis
                      child: Text(
                        _getVehicleEmoji(widget.vehicle.type),
                        style: const TextStyle(fontSize: 26),
                      ),
                    ),
            ),
          ],
        ),
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
      case 'charging': return Icons.ev_station;
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
      case 'charging': return Colors.greenAccent;
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


  /// Ensures location services are on and permission is granted before
  /// starting live navigation. Throws a human-readable message on failure.
  Future<void> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw 'Location services are disabled. Enable GPS/location and try again.';
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw 'Location permission denied.';
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw 'Location permission permanently denied. Enable it in settings.';
    }
  }

  /// Starts REAL navigation: follows the device's live GPS position along the
  /// route, moving the vehicle marker and camera as the user actually moves,
  /// and updating live speed / remaining distance / ETA.
  Future<void> _startLiveNavigation() async {
    _stopAnimation(); // clean up any preview/sim in progress

    try {
      await _ensureLocationPermission();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.redAccent),
        );
      }
      return;
    }

    final routePoints = _currentPlan.coordinates.map((c) => c.toLatLng()).toList();
    if (routePoints.isEmpty) return;

    setState(() {
      _isPlayingAnimation = true;
      _isLiveNavigating = true;
      _isPreviewMode = false;
      _animationIndex = 0;
      _visitedStops.clear();
      _tripProgressPercent = 0.0;
      _liveSpeedKmh = 0.0;
    });

    // Snap camera to the user immediately using the last/first fix.
    try {
      final first = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      _onLivePosition(first, routePoints);
    } catch (_) {
      // Stream will deliver a fix shortly; ignore a slow first read.
    }

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // metres between updates
    );
    _positionStream =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) => _onLivePosition(pos, routePoints),
      onError: (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('GPS error: $e'), backgroundColor: Colors.redAccent),
          );
        }
      },
    );
  }

  /// Handles one live GPS fix: projects it onto the route, updates the marker,
  /// heading, camera, and the live trip stats.
  void _onLivePosition(Position pos, List<LatLng> routePoints) {
    if (!mounted || !_isLiveNavigating) return;

    final here = LatLng(pos.latitude, pos.longitude);

    // Nearest route vertex → progress along the planned route.
    int nearestIdx = 0;
    double minDist = double.infinity;
    for (int i = 0; i < routePoints.length; i++) {
      final d = _getDistance(here, routePoints[i]);
      if (d < minDist) {
        minDist = d;
        nearestIdx = i;
      }
    }
    final double progress = routePoints.length > 1
        ? (nearestIdx / (routePoints.length - 1)).clamp(0.0, 1.0)
        : 0.0;

    final double totalKm = _currentPlan.distanceKm;
    final double remainingKm = ((1.0 - progress) * totalKm).clamp(0.0, totalKm);

    // Live speed (m/s → km/h); heading in degrees clockwise from north.
    final double speedKmh = (pos.speed.isFinite && pos.speed > 0) ? pos.speed * 3.6 : 0.0;
    final double headingRad = (pos.heading.isFinite && pos.heading >= 0)
        ? pos.heading * pi / 180.0
        : _vehicleRotation;

    // ETA from current speed, falling back to the planned pace when stationary.
    final double paceKmh = speedKmh > 5 ? speedKmh : (totalKm > 0 && _currentPlan.durationMin > 0
        ? totalKm / (_currentPlan.durationMin / 60.0)
        : 40.0);
    final int remainingMin = paceKmh > 0 ? (remainingKm / paceKmh * 60).round() : 0;

    setState(() {
      _animatedVehiclePosition = here;
      _vehicleRotation = headingRad;
      _animationIndex = nearestIdx;
      _tripProgressPercent = progress;
      _liveSpeedKmh = speedKmh;
      _liveRemainingKm = remainingKm;
      _liveRemainingMin = remainingMin;
    });

    // Follow camera on the 2D maps (the 3D map follows the marker internally).
    if (_mapStyle != MapStyle.satellite3D) {
      try {
        _mapController.moveAndRotate(here, 16.5, pos.heading.isFinite ? -pos.heading : 0.0);
      } catch (_) {
        try {
          _mapController.move(here, 16.5);
        } catch (_) {}
      }
    }

    // Arrival: within ~120 m of the destination.
    final destDist = _getDistance(here, routePoints.last);
    if (destDist < 0.0011 && !_visitedStops.contains('live_arrival')) {
      _visitedStops.add('live_arrival');
      setState(() {
        _activeStopHighlight = PlaceOfInterest(
          id: 999,
          name: widget.end.name ?? 'Destination',
          lat: widget.end.lat,
          lng: widget.end.lng,
          address: 'You have arrived!',
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🎉 You have arrived at your destination!')),
        );
      }
    }
  }

  /// Drives the route. In [preview] mode it is a fast aerial fly-through of the
  /// whole route — no stopover / toll / arrival pauses — so the user can quickly
  /// see the journey before committing to the full simulated drive.
  void _startAnimation({bool preview = false}) {
    final routePoints = _currentPlan.coordinates.map((c) => c.toLatLng()).toList();
    if (routePoints.isEmpty) return;

    _stopAnimation(); // Clean up if any
    
    // Calculate cumulative distances
    final List<double> cumulativeDistances = [0.0];
    for (int i = 1; i < routePoints.length; i++) {
      cumulativeDistances.add(
        cumulativeDistances[i - 1] + 
        _getDistance(routePoints[i - 1], routePoints[i])
      );
    }
    
    final totalDistance = cumulativeDistances.last;
    if (totalDistance == 0.0) return;

    setState(() {
      _isPlayingAnimation = true;
      _isPreviewMode = preview;
      _animationIndex = 0;
      _animatedVehiclePosition = routePoints.first;
      _vehicleRotation = 0.0;
      _currentSpeedModifier = 1.0;
      _isSlowingDown = false;
      _isTurningLeft = false;
      _isTurningRight = false;
      _visitedStops.clear();
      _pauseTicksRemaining = 0;
      _activeStopHighlight = null;
      _isTollStop = false;
      _tripProgressPercent = 0.0;
    });

    double currentDistance = 0.0;
    double currentHeading = 0.0;
    bool isFirstTick = true;
    Duration? lastElapsed;
    int leftTurnTicks = 0;
    int rightTurnTicks = 0;
    int slowDownTicks = 0;
    
    LatLng cameraPosition = routePoints.first;

    // Flutter native Ticker for smooth 60fps/120fps physics updates
    _ticker = createTicker((elapsed) {
      if (!mounted) {
        _ticker?.stop();
        return;
      }

      if (lastElapsed == null) {
        lastElapsed = elapsed;
        return;
      }

      final double dt = (elapsed.inMicroseconds - lastElapsed!.inMicroseconds) / 1000000.0;
      lastElapsed = elapsed;

      // Event processing during active stops or tolls
      if (_pauseTicksRemaining > 0) {
        _pauseTicksRemaining--;
        
        // Dynamic camera zoom calculations (Dive & Flyout Transitions)
        double currentZoom = 15.5;
        bool showOverlay = false;

        if (_pauseTicksRemaining > 105) {
          // 1. Dive zoom (first 15 ticks: 120 -> 105)
          double progress = ((120 - _pauseTicksRemaining) / 15.0).clamp(0.0, 1.0);
          currentZoom = 15.5 + (18.8 - 15.5) * progress;
        } else if (_pauseTicksRemaining <= 105 && _pauseTicksRemaining > 20) {
          // 2. Cinematic overlay (middle 85 ticks: 105 -> 20)
          currentZoom = 18.8;
          showOverlay = true;
        } else {
          // 3. Flyout zoom (last 20 ticks: 20 -> 0)
          double progress = ((20 - _pauseTicksRemaining) / 20.0).clamp(0.0, 1.0);
          currentZoom = 18.8 - (18.8 - 15.5) * progress;
        }

        setState(() {
          _eventZoom = currentZoom;
          _showCinematicOverlay = showOverlay;
        });

        // Move and rotate 2D Map camera dynamically during dive/flyout
        if (_mapStyle != MapStyle.satellite3D) {
          final double rotationDeg = -_vehicleRotation * (180 / pi);
          try {
            _mapController.moveAndRotate(cameraPosition, currentZoom, rotationDeg);
          } catch (e) {
            try {
              _mapController.move(cameraPosition, currentZoom);
            } catch (e2) {
              print("Trip MapController not ready yet: $e2");
            }
          }
        }

        if (_pauseTicksRemaining == 0) {
          setState(() {
            _activeStopHighlight = null;
            _isTollStop = false;
            _showCinematicOverlay = false;
            _eventZoom = 15.5;
          });
        }
        return;
      }

      if (currentDistance >= totalDistance) {
        // If we reached the end and haven't triggered arrival popup yet.
        // Preview mode skips the celebratory pause and just ends the fly-through.
        if (!_isPreviewMode && !_visitedStops.contains("destination_arrival")) {
          _visitedStops.add("destination_arrival");
          setState(() {
            _activeStopHighlight = PlaceOfInterest(
              id: 999,
              name: widget.end.name ?? "Destination",
              lat: widget.end.lat,
              lng: widget.end.lng,
              address: "Welcome! Trip completed successfully.",
            );
            _pauseTicksRemaining = 160; // 5.3 seconds celebratory pause
            _currentSpeedModifier = 0.0;
            _isSlowingDown = true;
          });
          return;
        }
        _stopAnimation();
        return;
      }

      // Find segment index where currentDistance lies
      int segmentIdx = 0;
      for (int i = 0; i < cumulativeDistances.length - 1; i++) {
        if (currentDistance >= cumulativeDistances[i] && 
            currentDistance <= cumulativeDistances[i + 1]) {
          segmentIdx = i;
          break;
        }
      }

      final p1 = routePoints[segmentIdx];
      final p2 = routePoints[segmentIdx + 1];
      
      final segLength = cumulativeDistances[segmentIdx + 1] - cumulativeDistances[segmentIdx];
      final segProgress = currentDistance - cumulativeDistances[segmentIdx];
      final double t = segLength > 0 ? (segProgress / segLength).clamp(0.0, 1.0) : 0.0;

      // Coordinate interpolation
      final lat = p1.latitude + (p2.latitude - p1.latitude) * t;
      final lng = p1.longitude + (p2.longitude - p1.longitude) * t;
      final currentLatLng = LatLng(lat, lng);

      // Bearing
      final segmentBearing = atan2(
        p2.longitude - p1.longitude,
        p2.latitude - p1.latitude,
      );

      if (isFirstTick) {
        currentHeading = segmentBearing;
        isFirstTick = false;
      } else {
        double diff = segmentBearing - currentHeading;
        while (diff < -pi) diff += 2 * pi;
        while (diff > pi) diff -= 2 * pi;
        currentHeading += diff * 0.15; // Smooth rotation interpolation
      }

      // Turn indicator & Speed controller (look ahead 20m)
      double speedModifier = 1.0;
      bool turningLeft = false;
      bool turningRight = false;
      bool slowingDown = false;

      // Look ahead to next segments
      if (segmentIdx < routePoints.length - 2) {
        final p3 = routePoints[segmentIdx + 2];
        final nextBearing = atan2(
          p3.longitude - p2.longitude,
          p3.latitude - p2.latitude,
        );
        double bearingChange = nextBearing - segmentBearing;
        while (bearingChange < -pi) bearingChange += 2 * pi;
        while (bearingChange > pi) bearingChange -= 2 * pi;

        if (bearingChange.abs() > 0.17) {
          slowingDown = true;
          speedModifier = 0.45;
          
          if (bearingChange > 0) {
            turningRight = true;
          } else {
            turningLeft = true;
          }
        }
      }

      // Pause length: shorter in preview so the fly-through still stops to show
      // each stop-point animation (toll, fuel, stopover) without dragging.
      final int stopPause = _isPreviewMode ? 70 : 120;

      // Look ahead for user stopover waypoints (pause at waypoint). Now shown in
      // preview too so the journey's stop points are visible during the preview.
      for (final wp in _currentWaypoints) {
        final wpLatLng = wp.toLatLng();
        final dist = _getDistance(currentLatLng, wpLatLng);
        final stopId = "stop_${wp.lat}_${wp.lng}";
        if (dist < 0.0025 && !_visitedStops.contains(stopId)) {
          _visitedStops.add(stopId);
          setState(() {
            _activeStopHighlight = PlaceOfInterest(
              id: DateTime.now().millisecondsSinceEpoch,
              name: wp.name ?? "Way Point Stop",
              lat: wp.lat,
              lng: wp.lng,
              address: "Scheduled Stopover",
            );
            _pauseTicksRemaining = stopPause;
            _currentSpeedModifier = 0.0;
            _isSlowingDown = true;
          });
          return;
        }
      }

      final double progressPercent = (currentDistance / totalDistance).clamp(0.0, 1.0);

      // Automatic fuel-station stop near the midpoint — pulls up and refuels with
      // the fuel-pump animation ('fuel' category shows _buildFuelAnimation).
      if (progressPercent >= 0.49 && progressPercent <= 0.52 &&
          !_visitedStops.contains("fuel_stop")) {
        _visitedStops.add("fuel_stop");
        setState(() {
          _activeStopHighlight = PlaceOfInterest(
            id: DateTime.now().millisecondsSinceEpoch,
            name: "Highway Fuel Station",
            lat: currentLatLng.latitude,
            lng: currentLatLng.longitude,
            address: "Refuel stop",
          );
          _pauseTicksRemaining = stopPause;
          _currentSpeedModifier = 0.0;
          _isSlowingDown = true;
        });
        return;
      }

      // Look ahead for Toll Plazas (at 33% and 66% progress) — shown in preview too.
      if (((progressPercent >= 0.33 && progressPercent <= 0.35) ||
           (progressPercent >= 0.66 && progressPercent <= 0.68)) &&
          !_visitedStops.contains("toll_${(progressPercent * 10).round()}")) {
        _visitedStops.add("toll_${(progressPercent * 10).round()}");
        setState(() {
          _isTollStop = true;
          _pauseTicksRemaining = stopPause;
          _currentSpeedModifier = 0.0;
          _isSlowingDown = true;
        });
        return;
      }

      // Advance simulated distance using delta time. Preview is a relaxed
      // fly-through (~40s); the full simulated drive takes ~60s.
      final double baseSpeed = totalDistance / (_isPreviewMode ? 40.0 : 60.0);
      currentDistance += baseSpeed * speedModifier * dt;

      // Camera trails the vehicle with a snappy follow (0.12 lerp) — tight enough
      // to feel like live navigation, loose enough to stay smooth.
      cameraPosition = LatLng(
        cameraPosition.latitude + (currentLatLng.latitude - cameraPosition.latitude) * 0.12,
        cameraPosition.longitude + (currentLatLng.longitude - cameraPosition.longitude) * 0.12,
      );

      if (turningLeft) {
        leftTurnTicks = 45; // Hold state for ~0.75s at 60fps
      } else if (leftTurnTicks > 0) {
        leftTurnTicks--;
      }

      if (turningRight) {
        rightTurnTicks = 45; // Hold state for ~0.75s at 60fps
      } else if (rightTurnTicks > 0) {
        rightTurnTicks--;
      }

      if (slowingDown) {
        slowDownTicks = 45;
      } else if (slowDownTicks > 0) {
        slowDownTicks--;
      }

      setState(() {
        _animationIndex = segmentIdx;
        _animatedVehiclePosition = currentLatLng;
        _vehicleRotation = currentHeading;
        _currentSpeedModifier = slowDownTicks > 0 ? 0.45 : 1.0;
        _isSlowingDown = slowDownTicks > 0;
        _isTurningLeft = leftTurnTicks > 0;
        _isTurningRight = rightTurnTicks > 0;
        _tripProgressPercent = progressPercent;
      });

      // Move and rotate camera smoothly to face the direction of travel (like Google Maps Navigation).
      // The camera targets a point AHEAD of the vehicle (along the heading) so the car sits in the
      // lower third of the screen with the road ahead visible — the classic turn-by-turn framing.
      if (_mapStyle != MapStyle.satellite3D) {
        final double dynamicZoom = 16.6 - (speedModifier - 0.45) * (1.2 / 0.55);
        final double zoom = dynamicZoom.clamp(15.4, 17.0);
        final double rotationDeg = -currentHeading * (180 / pi);

        // Look-ahead offset: ~0.24 km in the direction of travel (heading measured
        // as atan2(dLng, dLat), so 0 = north, increasing clockwise toward east).
        const double lookAheadDeg = 0.0022;
        final double cosLat = cos(lat * pi / 180).clamp(0.2, 1.0);
        final LatLng camTarget = LatLng(
          cameraPosition.latitude + cos(currentHeading) * lookAheadDeg,
          cameraPosition.longitude + sin(currentHeading) * lookAheadDeg / cosLat,
        );

        try {
          _mapController.moveAndRotate(camTarget, zoom, rotationDeg);
        } catch (e) {
          try {
            _mapController.move(camTarget, zoom);
          } catch (e2) {
            print("Trip MapController not ready yet: $e2");
          }
        }
      }
    });

    _ticker?.start();
  }

  double _getDistance(LatLng p1, LatLng p2) {
    return sqrt(
      (p1.latitude - p2.latitude) * (p1.latitude - p2.latitude) +
      (p1.longitude - p2.longitude) * (p1.longitude - p2.longitude)
    );
  }

  void _stopAnimation() {
    _animationTimer?.cancel();
    _animationTimer = null;
    _ticker?.stop();
    _positionStream?.cancel();
    _positionStream = null;
    try {
      _mapController.rotate(0.0);
    } catch (e) {
      print("Error resetting rotation: $e");
    }
    setState(() {
      _isPlayingAnimation = false;
      _isPreviewMode = false;
      _isLiveNavigating = false;
      _animatedVehiclePosition = null;
      _isSlowingDown = false;
      _isTurningLeft = false;
      _isTurningRight = false;
      _activeStopHighlight = null;
      _isTollStop = false;
      _tripProgressPercent = 0.0;
    });
  }

  /// Preview + Start buttons for the animated journey. Preview is a fast aerial
  /// fly-through of the whole route; Start runs the full simulated drive with
  /// stopover, toll and arrival cards. While playing, this collapses to a single
  /// Stop button.
  Widget _buildDriveActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _isPlayingAnimation
          ? SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _stopAnimation,
                icon: const Icon(Icons.stop, size: 18),
                label: Text(_isPreviewMode ? 'Stop Preview' : 'Stop Trip'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            )
          : Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _startAnimation(preview: true),
                    icon: const Icon(Icons.visibility, size: 18),
                    label: const Text('Preview Trip'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withOpacity(0.25)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _startLiveNavigation,
                    icon: const Icon(Icons.navigation, size: 20),
                    label: const Text('Start Trip'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E75B6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// Save + Share buttons shown directly in the details panel so they are
  /// always reachable — the app-bar copies are hidden in the embedded/desktop
  /// layout, which previously left no way to save or share a trip.
  Widget _buildTripActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _shareTrip,
              icon: const Icon(Icons.share, size: 18),
              label: const Text('Share'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withOpacity(0.25)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _saveTrip,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.bookmark_add, size: 18),
              label: Text(_saving ? 'Saving…' : 'Save Trip'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E75B6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapStackWithOverlays(Widget mapWidget, {double topPadding = 24.0, double rightPadding = 24.0}) {
    if (_isCarMode) {
      final currentPos = _animatedVehiclePosition ?? widget.start.toLatLng();
      final maneuver = _carGuidance.calculateManeuver(
        currentPos: currentPos,
        routePoints: _currentPlan.coordinates,
        end: widget.end,
        waypoints: _currentWaypoints,
      );
      if (_isPlayingAnimation || _isLiveNavigating) {
        _carGuidance.announceManeuver(maneuver);
      }
      final v = widget.vehicle;
      final double litresNeeded =
          v.efficiencyKmPerLiter > 0 ? _currentPlan.distanceKm / v.efficiencyKmPerLiter : 0;
      final telemetry = CarTelemetry(
        speedKmh: _displaySpeedKmh.toDouble(),
        remainingDistanceKm: max(0.0, (1 - _tripProgressPercent) * _currentPlan.distanceKm),
        remainingDurationMin: max(0, ((1 - _tripProgressPercent) * _currentPlan.durationMin).round()),
        progressPercent: _tripProgressPercent,
        hasTollAhead: (_currentPlan.toll?.fastagTollCost ?? 0) > 0,
        needsRefuel: v.currentFuelLiters < litresNeeded,
      );

      CarPlatformChannel.updateNavigation(maneuver: maneuver, telemetry: telemetry);

      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: mapWidget),
          Positioned.fill(
            child: CarModeOverlay(
              maneuver: maneuver,
              telemetry: telemetry,
              isPlayingAnimation: _isPlayingAnimation,
              speechMuted: _carGuidance.speechMuted,
              onTogglePlayPause: () {
                if (_isPlayingAnimation) {
                  _stopAnimation();
                } else {
                  _startAnimation(preview: true);
                }
              },
              onToggleMute: () {
                setState(() {
                  _carGuidance.speechMuted = !_carGuidance.speechMuted;
                });
              },
              onRecenterMap: _recenterMap,
              onExitCarMode: () {
                setState(() {
                  _isCarMode = false;
                });
              },
            ),
          ),
        ],
      );
    }

    final isDesktop = MediaQuery.of(context).size.width > 900;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: mapWidget),

        if (isDesktop) ...[
          // Desktop has width for a top row + a control stack below it.
          Positioned(
            right: rightPadding,
            top: topPadding,
            child: Row(
              children: [
                _buildLayersButton(),
                const SizedBox(width: 10),
                _buildMapDriveCluster(true),
              ],
            ),
          ),
          Positioned(
            right: rightPadding,
            top: topPadding + 70,
            child: _buildNavControlStack(),
          ),
        ] else
          // Mobile: ONE unified right rail so the controls never overlap, with a
          // staggered slide-in entrance.
          Positioned(
            right: rightPadding,
            top: topPadding,
            child: _buildMobileControlRail(),
          ),

        _buildTopHUD(topPadding),
        _buildBottomHUD(),

        // Driver-cluster speedometer during preview/navigation. On mobile it sits
        // ABOVE the bottom info banner (not on top of it) and is a touch smaller.
        if (_isPlayingAnimation)
          Positioned(
            left: 16,
            bottom: isDesktop ? 24 : 132,
            child: ScaleTransition(
              scale: CurvedAnimation(parent: _overlayCtrl, curve: Curves.easeOutBack),
              child: FadeTransition(
                opacity: CurvedAnimation(parent: _overlayCtrl, curve: Curves.easeOut),
                child: _buildSpeedometer(compact: !isDesktop),
              ),
            ),
          ),

        if (isDesktop && (_activeStopHighlight != null || _isTollStop))
          Positioned(
            left: 16,
            top: topPadding + 65,
            child: _buildStopHighlightCard(topPadding),
          ),
      ],
    );
  }

  /// Single, non-overlapping vertical rail of controls for mobile, each sliding
  /// in from the right with a staggered fade for a dynamic entrance.
  Widget _buildMobileControlRail() {
    Widget railItem(int i, Widget child) {
      final double begin = (i * 0.07).clamp(0.0, 0.6);
      final anim = CurvedAnimation(
        parent: _overlayCtrl,
        curve: Interval(begin, (begin + 0.4).clamp(0.0, 1.0), curve: Curves.easeOut),
      );
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(0.7, 0), end: Offset.zero).animate(anim),
        child: FadeTransition(opacity: anim, child: child),
      );
    }

    final items = <Widget>[
      _buildMapDriveCluster(false),
      _navCircle(Icons.directions_car_rounded, () => setState(() => _isCarMode = !_isCarMode), bg: const Color(0xFF10B981)),
      _buildLayersButton(),
      _navCircle(Icons.ios_share_rounded, _shareTrip, bg: const Color(0xCC2E75B6)),
      _navCircle(_saving ? Icons.hourglass_top_rounded : Icons.bookmark_add_rounded,
          _saving ? () {} : _saveTrip, bg: const Color(0xCC2E75B6)),
      _navCircle(_navSoundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          () => setState(() => _navSoundOn = !_navSoundOn)),
      _navCircle(Icons.explore_outlined, _recenterMap),
      _navCircle(Icons.settings_outlined, _showMapStyleSheet),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < items.length; i++) ...[
          if (i != 0) const SizedBox(height: 10),
          railItem(i, items[i]),
        ],
      ],
    );
  }

  /// A single round glass control button (shared by the rails).
  Widget _navCircle(IconData icon, VoidCallback onTap, {Color? bg}) {
    return Material(
      color: bg ?? Colors.black.withOpacity(0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  /// Current display speed in km/h from the active model (real values only).
  int get _displaySpeedKmh {
    if (_isLiveNavigating) return _liveSpeedKmh.round();
    if (_isTollStop || _activeStopHighlight != null) return 0;
    return (_currentSpeedModifier * 80).round();
  }

  /// Driver-cluster style speedometer gauge (reference: instrument cluster).
  Widget _buildSpeedometer({bool compact = false}) {
    final speed = _displaySpeedKmh;
    final double size = compact ? 116 : 150;
    final double numSize = compact ? 34 : 44;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xE61C2233), Color(0xF20B0F1A)],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 22, offset: const Offset(0, 10)),
        ],
      ),
      child: CustomPaint(
        painter: _SpeedGaugePainter(speed: speed, maxSpeed: 120),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: compact ? 6 : 8),
              Text(
                '$speed',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: numSize,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                ),
              ),
              Text('km/h', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: compact ? 10 : 12)),
              SizedBox(height: compact ? 4 : 6),
              Container(
                padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1a73e8).withOpacity(0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('D',
                    style: TextStyle(color: const Color(0xFF60A5FA), fontWeight: FontWeight.bold, fontSize: compact ? 11 : 13, letterSpacing: 2)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Vertical stack of round glass control buttons (reference: right rail).
  Widget _buildNavControlStack() {
    Widget btn(IconData icon, VoidCallback onTap, {Color? bg}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: bg ?? Colors.black.withOpacity(0.45),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        btn(Icons.directions_car_rounded, () => setState(() => _isCarMode = !_isCarMode), bg: const Color(0xFF10B981)),
        // Always-visible Save + Share on the map (also in the side panel).
        btn(Icons.ios_share_rounded, _shareTrip, bg: const Color(0xCC2E75B6)),
        btn(_saving ? Icons.hourglass_top_rounded : Icons.bookmark_add_rounded,
            _saving ? () {} : _saveTrip, bg: const Color(0xCC2E75B6)),
        btn(_navSoundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            () => setState(() => _navSoundOn = !_navSoundOn)),
        btn(Icons.explore_outlined, _recenterMap),
        btn(Icons.settings_outlined, _showMapStyleSheet),
      ],
    );
  }

  void _recenterMap() {
    // Recenter the 2D map on the current position (3D map auto-follows).
    final pos = _animatedVehiclePosition;
    if (pos != null && _mapStyle != MapStyle.satellite3D) {
      try { _mapController.move(pos, 16.5); } catch (_) {}
    }
  }

  /// Small live minimap inset showing the whole route + current position.
  Widget _buildTollAnimation() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        'assets/images/toll_cartoon.png',
        fit: BoxFit.cover,
        width: double.infinity,
        height: 105,
      ),
    );
  }

  Widget _buildFuelAnimation() {
    final double progress = ((105.0 - _pauseTicksRemaining) / 85.0).clamp(0.0, 1.0);
    final bool isFilling = progress > 0.35 && progress < 0.85;
    final int tankPercent = isFilling 
        ? (35 + (progress - 0.35) * 120).round().clamp(35, 100)
        : (progress >= 0.85 ? 100 : 35);
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/images/fuel_cartoon.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          left: 8,
          right: 8,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.65),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Icon(Icons.local_gas_station, color: Colors.orange, size: 14),
                const SizedBox(width: 6),
                Text(
                  "Refueling: $tankPercent%",
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: tankPercent / 100.0,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation(Colors.orange),
                      minHeight: 4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEVAnimation() {
    final double progress = ((105.0 - _pauseTicksRemaining) / 85.0).clamp(0.0, 1.0);
    final bool isPlugged = progress > 0.2;
    final int batteryPercent = isPlugged 
        ? (30 + (progress - 0.2) * 62.5).round().clamp(30, 80)
        : 30;
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/images/ev_cartoon.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          left: 8,
          right: 8,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.65),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Icon(Icons.bolt, color: Colors.cyan, size: 14),
                const SizedBox(width: 6),
                Text(
                  "Charging: $batteryPercent%",
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: batteryPercent / 100.0,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation(Colors.cyan),
                      minHeight: 4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDiningAnimation() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        'assets/images/dining_cartoon.png',
        fit: BoxFit.cover,
        width: double.infinity,
        height: 100,
      ),
    );
  }

  Widget _buildRefreshmentAnimation() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        'assets/images/tea_cartoon.png',
        fit: BoxFit.cover,
        width: double.infinity,
        height: 100,
      ),
    );
  }

  Widget _buildHotelAnimation() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        'assets/images/hotel_cartoon.png',
        fit: BoxFit.cover,
        width: double.infinity,
        height: 100,
      ),
    );
  }

  Widget _buildViewpointAnimation() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        'assets/images/viewpoint_cartoon.png',
        fit: BoxFit.cover,
        width: double.infinity,
        height: 100,
      ),
    );
  }

  Widget _buildSightseeingAnimation() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        'assets/images/attraction_cartoon.png',
        fit: BoxFit.cover,
        width: double.infinity,
        height: 100,
      ),
    );
  }

  Widget _buildTopHUD(double topPadding) {
    if (!_isPlayingAnimation) return const SizedBox.shrink();
    String bannerText = _isPreviewMode
        ? "Previewing route…"
        : (_isLiveNavigating ? "Live navigation • following your GPS" : "Drive straight on highway");
    IconData leadingIcon = _isPreviewMode ? Icons.visibility : Icons.navigation;
    Color iconColor = _isPreviewMode
        ? Colors.tealAccent
        : (_isLiveNavigating ? Colors.greenAccent : Colors.blueAccent);

    if (_isTollStop) {
      bannerText = "🛂 FASTag Toll Plaza: Auto-paying toll...";
      leadingIcon = Icons.payment;
      iconColor = Colors.amber;
    } else if (_activeStopHighlight != null) {
      if (_activeStopHighlight!.name == (widget.end.name ?? "Destination")) {
        bannerText = "🎉 Welcome! Arrived at destination!";
        leadingIcon = Icons.celebration;
        iconColor = Colors.green;
      } else {
        bannerText = "🛑 Stopover: ${_activeStopHighlight!.name}";
        leadingIcon = Icons.place;
        iconColor = Colors.redAccent;
      }
    } else if (_isTurningLeft) {
      bannerText = "↩️ In 150m: Turn left onto next highway";
      leadingIcon = Icons.turn_left;
      iconColor = Colors.orange;
    } else if (_isTurningRight) {
      bannerText = "↪️ In 150m: Turn right onto next highway";
      leadingIcon = Icons.turn_right;
      iconColor = Colors.orange;
    } else if (_currentSpeedModifier < 0.6) {
      bannerText = "⚠️ Sharp Bend: Decelerating...";
      leadingIcon = Icons.warning;
      iconColor = Colors.redAccent;
    }

    return Positioned(
      left: 16,
      top: topPadding,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A).withOpacity(0.9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(leadingIcon, color: iconColor, size: 24),
            const SizedBox(width: 12),
            Text(
              bannerText,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Formats an arrival clock time [minutesFromNow] into the future, e.g. "ETA 3:45 PM".
  String _formatEta(int minutesFromNow) {
    final eta = DateTime.now().add(Duration(minutes: minutesFromNow));
    final h24 = eta.hour;
    final period = h24 >= 12 ? 'PM' : 'AM';
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    final mm = eta.minute.toString().padLeft(2, '0');
    return 'ETA $h12:$mm $period';
  }

  Widget _buildBottomHUD() {
    if (!_isPlayingAnimation) return const SizedBox.shrink();
    // Live navigation uses real GPS-derived values; the simulation uses its
    // internal progress model.
    final int speedKmh = _isLiveNavigating
        ? _liveSpeedKmh.round()
        : (_isTollStop || _activeStopHighlight != null ? 0 : (_currentSpeedModifier * 80).round());
    final String remainingDistanceKm = _isLiveNavigating
        ? _liveRemainingKm.toStringAsFixed(1)
        : ((1.0 - _tripProgressPercent) * 140.0).toStringAsFixed(1);
    final int remainingMinutes = _isLiveNavigating
        ? _liveRemainingMin
        : ((1.0 - _tripProgressPercent) * 110.0).round();
    final String etaText = _isLiveNavigating
        ? _formatEta(remainingMinutes)
        : 'ETA 3:45 PM';

    final bool isDesktop = MediaQuery.of(context).size.width > 900;
    return Positioned(
      left: 16,
      // Desktop keeps a right gap (speedometer sits bottom-left); mobile uses the
      // full width because the speedometer now sits above this banner.
      right: isDesktop ? 80 : 16,
      bottom: 24,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A).withOpacity(0.9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _activeStopHighlight?.name == (widget.end.name ?? "Destination") 
                            ? "Arrived!" 
                            : "$remainingMinutes min left",
                        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "$remainingDistanceKm km • $etaText",
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                    ),
                    child: Text(
                      "$speedKmh km/h",
                      style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _tripProgressPercent,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStopHighlightCard(double topPadding) {
    if (!_isPlayingAnimation) return const SizedBox.shrink();
    if (_activeStopHighlight == null && !_isTollStop) return const SizedBox.shrink();

    final bool isMobile = MediaQuery.of(context).size.width < 1000;

    // 1. Toll plaza gate receipt card
    if (_isTollStop) {
      final double gateProgress = ((60.0 - _pauseTicksRemaining) / 60.0).clamp(0.0, 1.0);
      final String gateStatus = gateProgress < 0.4 ? "Paying Toll... 🪙" : (gateProgress < 0.8 ? "Gate Opening... 🔓" : "Gate Open! Go 🟢");
      
      return Container(
        width: 290,
        padding: isMobile ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6) : const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.amber.withOpacity(0.6), width: 1.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.55),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
              Container(
                padding: EdgeInsets.all(isMobile ? 4 : 10),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.payment, color: Colors.amber, size: isMobile ? 22 : 36),
              ),
              SizedBox(height: isMobile ? 2 : 12),
              Text(
                "FASTag Toll Plaza",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: isMobile ? 15 : 18),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                "National Highway Authority",
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: isMobile ? 9 : 12),
              ),
              SizedBox(height: isMobile ? 4 : 12),
              Container(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 14, vertical: isMobile ? 2 : 8),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Toll Paid:", style: TextStyle(color: Colors.white70, fontSize: isMobile ? 10 : 13)),
                    Text("₹120.00", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: isMobile ? 12 : 15)),
                  ],
                ),
              ),
              if (!isMobile) ...[
                const SizedBox(height: 12),
                const Divider(color: Colors.white12, thickness: 1),
                const SizedBox(height: 8),
                SizedBox(
                  height: 105,
                  child: _buildTollAnimation(),
                ),
              ],
              SizedBox(height: isMobile ? 4 : 6),
              Text(
                gateStatus,
                style: TextStyle(color: Colors.white70, fontSize: isMobile ? 10 : 13, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
    }

    // 2. Normal waypoint / Arrival cards
    final isDest = _activeStopHighlight!.name == (widget.end.name ?? "Destination");
    final category = isDest ? 'arrival' : _determineStopCategory(_activeStopHighlight!.name);

    if (category == 'arrival') {
      final double totalDistance = _currentPlan.distanceKm;
      final int totalDuration = _currentPlan.durationMin;
      final String durationText = totalDuration > 60 
          ? "${(totalDuration ~/ 60)}h ${(totalDuration % 60)}m" 
          : "$totalDuration mins";
      final double tollCost = _currentPlan.toll?.fastagTollCost ?? 240.0;
      final double fuelCost = _currentPlan.toll?.fuelCost ?? 980.0;
      final stopsCount = _currentWaypoints.length;
 
      return Container(
        width: 310,
        padding: EdgeInsets.all(isMobile ? 14 : 20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.green.withOpacity(0.7), width: 2.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 25,
              spreadRadius: 3,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
              Container(
                padding: EdgeInsets.all(isMobile ? 8 : 12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.celebration, color: Colors.green, size: isMobile ? 30 : 40),
              ),
              SizedBox(height: isMobile ? 8 : 12),
              Text(
                "Trip Completed!",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: isMobile ? 17 : 19),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                "Welcome to ${_activeStopHighlight!.name}",
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: isMobile ? 12 : 13),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: isMobile ? 10 : 16),
              const Divider(color: Colors.white24, thickness: 1),
              SizedBox(height: isMobile ? 8 : 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatItem("Distance", "${totalDistance.toStringAsFixed(1)} km", Icons.space_bar),
                  _buildStatItem("Duration", durationText, Icons.timer),
                ],
              ),
              SizedBox(height: isMobile ? 10 : 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatItem("Tolls Cost", "₹${tollCost.toStringAsFixed(0)}", Icons.payment),
                  _buildStatItem("Fuel Cost", "₹${fuelCost.toStringAsFixed(0)}", Icons.local_gas_station),
                ],
              ),
              SizedBox(height: isMobile ? 10 : 16),
              const Divider(color: Colors.white24, thickness: 1),
              SizedBox(height: isMobile ? 8 : 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.place, color: Colors.grey, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    "Stops Visited: $stopsCount stops",
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: isMobile ? 12 : 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        );
    }

    IconData stopIcon = Icons.place;
    Color themeColor = Colors.redAccent;
    String headingText = "Scheduled Stopover";
    String detailsText = "Rest Time: 30 Mins";
    String progressText = "Relaxing... 🚗";
    double progressPercent = 0.0;

    switch (category) {
      case 'arrival':
        stopIcon = Icons.celebration;
        themeColor = Colors.green;
        headingText = "Welcome! Trip Completed";
        detailsText = "Final Destination Reached!";
        progressText = "Enjoy your trip! 🎉";
        progressPercent = 1.0;
        break;
      case 'fuel':
        stopIcon = Icons.local_gas_station;
        themeColor = Colors.orange;
        headingText = "Fuel Station Stop";
        detailsText = "Refueling Vehicle Tank";
        final int elapsed = 100 - _pauseTicksRemaining;
        if (elapsed < 30) {
          progressText = "Parking beside fuel pump... ⛽";
          progressPercent = 0.15;
        } else if (elapsed < 80) {
          final int fillPercent = (40 + (elapsed - 30) * 1.1).round().clamp(40, 95);
          progressText = "Refueling tank: $fillPercent%... ⛽";
          progressPercent = 0.3 + (elapsed - 30) / 100;
        } else {
          progressText = "Refueling complete! 🟢";
          progressPercent = 1.0;
        }
        break;
      case 'ev':
        stopIcon = Icons.bolt;
        themeColor = Colors.cyan;
        headingText = "EV Charging Station";
        detailsText = "Charging Battery Pack";
        final int elapsed = 100 - _pauseTicksRemaining;
        if (elapsed < 25) {
          progressText = "Plugging in charging cable... 🔌";
          progressPercent = 0.1;
        } else if (elapsed < 80) {
          final int chargePercent = (35 + (elapsed - 25) * 0.8).round().clamp(35, 80);
          progressText = "Charging: $chargePercent%... ⚡";
          progressPercent = 0.2 + (elapsed - 25) / 100;
        } else {
          progressText = "Charging done! Disconnecting... 🔌";
          progressPercent = 1.0;
        }
        break;
      case 'restaurant':
        stopIcon = Icons.restaurant;
        themeColor = Colors.brown;
        headingText = "Dining Stopover";
        detailsText = "Rest & Meal Break";
        final int elapsed = 100 - _pauseTicksRemaining;
        if (elapsed < 30) {
          progressText = "Parking vehicle... 🍽️";
        } else if (elapsed < 80) {
          progressText = "Enjoying lunch at restaurant... 🍛🍕";
        } else {
          progressText = "Bill paid. Boarding vehicle... 🚗";
        }
        progressPercent = elapsed / 100.0;
        break;
      case 'tea':
        stopIcon = Icons.coffee;
        themeColor = Colors.orangeAccent;
        headingText = "Tea/Coffee Break";
        detailsText = "Quick Tea & Refreshment";
        final int elapsed = 100 - _pauseTicksRemaining;
        if (elapsed < 30) {
          progressText = "Stopping at cafe... ☕";
        } else if (elapsed < 80) {
          progressText = "Enjoying hot tea & cookies... ☕🍪";
        } else {
          progressText = "Continuing journey... 🚗";
        }
        progressPercent = elapsed / 100.0;
        break;
      case 'viewpoint':
        stopIcon = Icons.photo_camera;
        themeColor = Colors.teal;
        headingText = "Scenic Viewpoint";
        detailsText = "Beautiful Panoramic View";
        final int elapsed = 100 - _pauseTicksRemaining;
        if (elapsed < 30) {
          progressText = "Stopping to enjoy view... 🌄";
        } else if (elapsed < 80) {
          progressText = "Taking photos... 📸⛰️";
        } else {
          progressText = "Resuming route... 🚗";
        }
        progressPercent = elapsed / 100.0;
        break;
      case 'attraction':
        stopIcon = Icons.star;
        themeColor = Colors.amber;
        headingText = "Sightseeing Point";
        detailsText = "Visiting Landmark Attraction";
        final int elapsed = 100 - _pauseTicksRemaining;
        if (elapsed < 30) {
          progressText = "Approaching landmark... 🏛️";
        } else if (elapsed < 80) {
          progressText = "Cinematic landmark orbiting... 🚁";
        } else {
          progressText = "Sightseeing done! Resuming... 🚗";
        }
        progressPercent = elapsed / 100.0;
        break;
      case 'hotel':
        stopIcon = Icons.hotel;
        themeColor = Colors.purple;
        headingText = "Hotel Check-in";
        detailsText = "Checking into your stay";
        final int elapsed = 100 - _pauseTicksRemaining;
        if (elapsed < 30) {
          progressText = "Entering hotel driveway... 🏨";
        } else if (elapsed < 80) {
          progressText = "Unloading luggage & check-in... 🧳";
        } else {
          progressText = "Checked in successfully! 🔑";
        }
        progressPercent = elapsed / 100.0;
        break;
      default:
        stopIcon = Icons.place;
        themeColor = Colors.redAccent;
        headingText = _activeStopHighlight!.name;
        detailsText = "Scheduled Stopover";
        progressText = "Resting... 🚗";
        progressPercent = (100 - _pauseTicksRemaining) / 100.0;
    }

    Widget? cardAnimation;
    if (category == 'fuel') {
      cardAnimation = _buildFuelAnimation();
    } else if (category == 'ev') {
      cardAnimation = _buildEVAnimation();
    } else if (category == 'restaurant') {
      cardAnimation = _buildDiningAnimation();
    } else if (category == 'tea') {
      cardAnimation = _buildRefreshmentAnimation();
    } else if (category == 'hotel') {
      cardAnimation = _buildHotelAnimation();
    } else if (category == 'viewpoint') {
      cardAnimation = _buildViewpointAnimation();
    } else if (category == 'attraction') {
      cardAnimation = _buildSightseeingAnimation();
    }

    return Container(
      width: 290,
      padding: isMobile ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6) : const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: themeColor.withOpacity(0.6), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.55),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            Container(
              padding: EdgeInsets.all(isMobile ? 4 : 10),
              decoration: BoxDecoration(
                color: themeColor.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(stopIcon, color: themeColor, size: isMobile ? 22 : 36),
            ),
            SizedBox(height: isMobile ? 2 : 12),
            Text(
              headingText,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: isMobile ? 14 : 17),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              detailsText,
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: isMobile ? 9 : 12),
              textAlign: TextAlign.center,
            ),
            if (!isMobile) ...[
              const SizedBox(height: 12),
              const Divider(color: Colors.white12, thickness: 1),
              if (cardAnimation != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 100,
                  child: cardAnimation,
                ),
              ],
            ] else ...[
              SizedBox(height: isMobile ? 6 : 12),
            ],
            SizedBox(height: isMobile ? 2 : 8),
            Text(
              progressText,
              style: TextStyle(color: Colors.white70, fontSize: isMobile ? 10 : 13, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: isMobile ? 4 : 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progressPercent,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(themeColor),
                minHeight: isMobile ? 2.5 : 4,
              ),
            ),
          ],
        ),
      );
  }

  String _determineStopCategory(String name) {
    final n = name.toLowerCase();
    if (n.contains('fuel') || n.contains('petrol') || n.contains('gas') || n.contains('shell')) return 'fuel';
    if (n.contains('ev ') || n.contains('charging') || n.contains('charge') || n.contains('station')) return 'ev';
    if (n.contains('restaurant') || n.contains('dhaba') || n.contains('meals') || n.contains('food') || n.contains('dining') || n.contains('veg')) return 'restaurant';
    if (n.contains('tea') || n.contains('coffee') || n.contains('chai') || n.contains('refreshment') || n.contains('break')) return 'tea';
    if (n.contains('hotel') || n.contains('resort') || n.contains('lodge') || n.contains('stay') || n.contains('inn') || n.contains('villa')) return 'hotel';
    if (n.contains('view') || n.contains('valley') || n.contains('peak') || n.contains('hills') || n.contains('viewpoint')) return 'viewpoint';
    if (n.contains('temple') || n.contains('palace') || n.contains('fort') || n.contains('falls') || n.contains('lake') || n.contains('museum') || n.contains('zoo') || n.contains('sightseeing')) return 'attraction';
    return 'other';
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return SizedBox(
      width: 125,
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Map-overlay Preview + Start controls. Collapses to a single Stop control
  /// while an animation is playing. [isDesktop] chooses pill vs circle style.
  Widget _buildMapDriveCluster(bool isDesktop) {
    const darkBg = Color(0xFF1A1A1A);
    if (isDesktop) {
      if (_isPlayingAnimation) {
        return _mapPillButton(
          icon: Icons.stop,
          label: _isPreviewMode ? 'Stop Preview' : 'Stop Trip',
          bg: Colors.red,
          onTap: _stopAnimation,
        );
      }
      return Row(
        children: [
          _mapPillButton(
            icon: Icons.visibility,
            label: 'Preview',
            bg: darkBg,
            onTap: () => _startAnimation(preview: true),
          ),
          const SizedBox(width: 10),
          _mapPillButton(
            icon: Icons.navigation,
            label: 'Start Trip',
            bg: darkBg,
            onTap: _startLiveNavigation,
          ),
        ],
      );
    }
    // Mobile: stacked circular buttons.
    if (_isPlayingAnimation) {
      return _mapCircleButton(icon: Icons.stop, bg: Colors.redAccent, onTap: _stopAnimation);
    }
    return Column(
      children: [
        _mapCircleButton(icon: Icons.visibility, bg: darkBg, onTap: () => _startAnimation(preview: true)),
        const SizedBox(height: 10),
        _mapCircleButton(icon: Icons.navigation, bg: darkBg, onTap: _startLiveNavigation),
      ],
    );
  }

  Widget _mapPillButton({required IconData icon, required String label, required Color bg, required VoidCallback onTap}) {
    return Container(
      decoration: BoxDecoration(
        color: bg.withOpacity(0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mapCircleButton({required IconData icon, required Color bg, required VoidCallback onTap}) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: bg.withOpacity(0.9),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.2),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  String _getVehicleEmoji(String type) {
    switch (type.toLowerCase()) {
      case 'car': return '🚗';
      case 'suv': return '🚙';
      case 'motorcycle': return '🏍️';
      case 'bus': return '🚌';
      case 'rv': return '🚐';
      case 'truck2axle': return '🚚';
      case 'truck3axle': return '🚛';
      default: return '🚗';
    }
  }

  bool _isPointVisited(GeoPoint point) {
    if (!_isPlayingAnimation) return true;
    int closestIdx = 0;
    double minDistance = double.infinity;
    for (int i = 0; i < _currentPlan.coordinates.length; i++) {
      final p = _currentPlan.coordinates[i];
      final dist = (p.lat - point.lat) * (p.lat - point.lat) + (p.lng - point.lng) * (p.lng - point.lng);
      if (dist < minDistance) {
        minDistance = dist;
        closestIdx = i;
      }
    }
    return _animationIndex >= closestIdx;
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
    final curr = (toll?.currency == 'INR' || toll?.currency == null) ? '₹' : toll!.currency;
    final fuelDisplay = toll?.fuelCost != null && toll!.fuelCost! > 0
        ? '$curr ${toll.fuelCost!.toStringAsFixed(0)}'
        : _estimateFuelCost(plan.distanceKm, vehicle, currency);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Stats Row perfectly aligned with the inner content of the card below
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _stat('${plan.distanceKm.toStringAsFixed(0)} km', 'Distance', CrossAxisAlignment.start),
                    _stat('${hours}h ${minutes}m', 'Driving time', CrossAxisAlignment.center),
                    _stat('${plan.estimatedDays} day${plan.estimatedDays > 1 ? 's' : ''}', 'Trip length', CrossAxisAlignment.end),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // ── Fee Card ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Column(
                  children: [
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
          if (plan.weather != null && plan.weather!.points.isNotEmpty) ...[
            const SizedBox(height: 12),
            _WeatherStrip(weather: plan.weather!),
          ],
          if (plan.departureAdvice != null && plan.departureAdvice!.recommendation.isNotEmpty) ...[
            const SizedBox(height: 12),
            _DepartureBanner(advice: plan.departureAdvice!),
          ],
          if (plan.restStops.isNotEmpty) ...[
            const SizedBox(height: 12),
            _RestStopsCard(stops: plan.restStops),
          ],
          if (plan.itinerary.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ItineraryCard(days: plan.itinerary),
          ],
          if (plan.budget != null) ...[
            const SizedBox(height: 12),
            _BudgetCard(budget: plan.budget!),
          ],
          const SizedBox(height: 8),
        ],
      ),
    ),
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
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
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
          // Label and badge — takes remaining space
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.75),
                              fontWeight: FontWeight.w500)),
                    ),
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
          ),
          const SizedBox(width: 8),
          // Price value — always visible on the right
          Text(
            value,
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

  Widget _stat(String value, String label, [CrossAxisAlignment alignment = CrossAxisAlignment.center]) {
    return Column(
      crossAxisAlignment: alignment,
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

/// Multi-day breakdown of the drive, one row per driving day.
class _ItineraryCard extends StatelessWidget {
  final List<DayPlan> days;
  const _ItineraryCard({required this.days});

  String _h(double h) => h % 1 == 0 ? '${h.toInt()}h' : '${h.toStringAsFixed(1)}h';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_month, color: Color(0xFFB39DDB), size: 16),
              const SizedBox(width: 6),
              Text('${days.length}-day itinerary',
                  style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.75), fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          for (final d in days)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFB39DDB).withOpacity(0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('D${d.day}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFB39DDB))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.isFinal
                              ? 'Drive ${d.distanceKm.toStringAsFixed(0)} km → arrive at destination'
                              : 'Drive ${d.distanceKm.toStringAsFixed(0)} km, then overnight stop',
                          style: const TextStyle(fontSize: 12.5, color: Colors.white, fontWeight: FontWeight.w500),
                        ),
                        Text('${_h(d.driveHours)} driving · ${d.fromKm.toStringAsFixed(0)}–${d.toKm.toStringAsFixed(0)} km',
                            style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Best-departure-time advice based on the hourly rain forecast at the start.
class _DepartureBanner extends StatelessWidget {
  final DepartureAdvice advice;
  const _DepartureBanner({required this.advice});

  @override
  Widget build(BuildContext context) {
    final waiting = advice.suggestsWaiting;
    final color = waiting ? const Color(0xFFFFB74D) : const Color(0xFF00E5A0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(waiting ? Icons.schedule : Icons.check_circle, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Best time to leave',
                    style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(advice.recommendation,
                    style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Suggested rest breaks along the route, derived from total driving time.
class _RestStopsCard extends StatelessWidget {
  final List<RestBreak> stops;
  const _RestStopsCard({required this.stops});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_cafe, color: Color(0xFF9AD0EC), size: 16),
              const SizedBox(width: 6),
              Text('Suggested rest breaks',
                  style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.75), fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          for (final s in stops)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF9AD0EC).withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Text('${s.afterHours % 1 == 0 ? s.afterHours.toInt() : s.afterHours}h',
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF9AD0EC))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Break after driving ${s.afterHours % 1 == 0 ? s.afterHours.toInt() : s.afterHours}h',
                        style: TextStyle(fontSize: 12.5, color: Colors.white.withOpacity(0.75))),
                  ),
                  Text('${s.distanceFromStartKm.toStringAsFixed(0)} km',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Horizontal strip of weather readings sampled along the route, with a
/// warning banner when rain/storms are expected on any segment.
class _WeatherStrip extends StatelessWidget {
  final RouteWeather weather;
  const _WeatherStrip({required this.weather});

  static const Map<String, IconData> _icons = {
    'clear': Icons.wb_sunny,
    'partly_cloudy': Icons.wb_cloudy,
    'cloudy': Icons.cloud,
    'fog': Icons.foggy,
    'drizzle': Icons.grain,
    'rain': Icons.umbrella,
    'snow': Icons.ac_unit,
    'thunderstorm': Icons.thunderstorm,
  };

  static const Map<String, Color> _colors = {
    'clear': Color(0xFFFFC93C),
    'partly_cloudy': Color(0xFF9AD0EC),
    'cloudy': Color(0xFFB0BEC5),
    'fog': Color(0xFFB0BEC5),
    'drizzle': Color(0xFF64B5F6),
    'rain': Color(0xFF4FC3F7),
    'snow': Color(0xFFE1F5FE),
    'thunderstorm': Color(0xFF9575CD),
  };

  @override
  Widget build(BuildContext context) {
    final points = weather.points;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.thermostat, color: Color(0xFF4FC3F7), size: 16),
              const SizedBox(width: 6),
              Text('Weather on route',
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.75),
                      fontWeight: FontWeight.w600)),
            ],
          ),
          if (weather.hasAlerts) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF4FC3F7).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFF4FC3F7), size: 14),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text('Rain or storms expected on part of your route',
                        style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.85))),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (int i = 0; i < points.length; i++) _tile(points[i], i, points.length),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(WeatherPoint p, int index, int total) {
    final label = index == 0
        ? 'Start'
        : index == total - 1
            ? 'End'
            : '${p.distanceFromStartKm.toStringAsFixed(0)}km';
    final color = _colors[p.icon] ?? Colors.white70;
    return Expanded(
      child: Column(
        children: [
          Icon(_icons[p.icon] ?? Icons.cloud, color: color, size: 22),
          const SizedBox(height: 4),
          Text(p.tempC != null ? '${p.tempC!.toStringAsFixed(0)}°' : '--',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 2),
          Text(label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.5))),
          if ((p.rainChancePct ?? 0) >= 40)
            Text('${p.rainChancePct}%',
                style: const TextStyle(fontSize: 9, color: Color(0xFF4FC3F7), fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// All-in trip budget card: fuel + tolls + food + stay + buffer, with a total.
class _BudgetCard extends StatelessWidget {
  final TripBudget budget;
  const _BudgetCard({required this.budget});

  String _fmt(int v) {
    // Indian-style grouping (e.g. 1,20,000) kept simple for typical trip sizes.
    final s = v.toString();
    if (s.length <= 3) return s;
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final buf = StringBuffer();
    while (rest.length > 2) {
      buf.write(',${rest.substring(rest.length - 2)}');
      rest = rest.substring(0, rest.length - 2);
    }
    return '$rest$buf,$last3';
  }

  @override
  Widget build(BuildContext context) {
    final rows = <List<dynamic>>[
      ['Fuel', budget.fuel, Icons.local_gas_station, Colors.orangeAccent],
      if (budget.tolls > 0) ['Tolls', budget.tolls, Icons.toll, const Color(0xFFFF6B6B)],
      ['Food (${budget.days}d)', budget.food, Icons.restaurant, const Color(0xFFFFB74D)],
      if (budget.stay > 0)
        ['Stay (${budget.nights} night${budget.nights == 1 ? '' : 's'})', budget.stay, Icons.hotel, const Color(0xFF64B5F6)],
      ['Buffer', budget.buffer, Icons.more_horiz, Colors.white54],
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF00E5A0).withOpacity(0.10), Colors.white.withOpacity(0.03)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00E5A0).withOpacity(0.25)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet, color: Color(0xFF00E5A0), size: 16),
              const SizedBox(width: 6),
              Text('Estimated trip budget',
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.75),
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('₹${_fmt(budget.total)}',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF00E5A0))),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text('≈ ₹${_fmt(budget.perDay)}/day · ${budget.travellers} traveller${budget.travellers == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5))),
          ),
          const Divider(color: Colors.white12, height: 20),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(r[2] as IconData, color: r[3] as Color, size: 15),
                  const SizedBox(width: 8),
                  Text(r[0] as String,
                      style: TextStyle(fontSize: 12.5, color: Colors.white.withOpacity(0.7))),
                  const Spacer(),
                  Text('₹${_fmt(r[1] as int)}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PulsingRing extends StatefulWidget {
  const _PulsingRing();

  @override
  State<_PulsingRing> createState() => _PulsingRingState();
}

class _PulsingRingState extends State<_PulsingRing> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 50 * _controller.value,
          height: 50 * _controller.value,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF2E75B6).withOpacity(1.0 - _controller.value),
            border: Border.all(
              color: const Color(0xFF2E75B6).withOpacity(1.0 - _controller.value),
              width: 2.5,
            ),
          ),
        );
      },
    );
  }
}

class _DrivingWobble extends StatefulWidget {
  final Widget child;
  const _DrivingWobble({required this.child});

  @override
  State<_DrivingWobble> createState() => _DrivingWobbleState();
}

class _DrivingWobbleState extends State<_DrivingWobble> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_SmokeParticle> _particles = [];
  final Random _random = Random();
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..repeat();

    _controller.addListener(() {
      _updateParticles();
    });
  }

  void _updateParticles() {
    _ticks++;
    // Spawn smoke particle
    if (_ticks % 3 == 0) {
      _particles.add(_SmokeParticle(
        x: 10.0,
        y: 8.0,
        vx: 0.8 + _random.nextDouble() * 1.2,
        vy: 0.4 + _random.nextDouble() * 0.8,
        maxRadius: 5.0 + _random.nextDouble() * 5.0,
      ));
    }

    // Update existing particles
    for (int i = _particles.length - 1; i >= 0; i--) {
      final p = _particles[i];
      p.progress += 0.05;
      if (p.progress >= 1.0) {
        _particles.removeAt(i);
      } else {
        p.x += p.vx;
        p.y += p.vy;
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double wobble = sin(_controller.value * 2 * pi) * 0.08;
    final double bounce = sin(_controller.value * 2 * pi * 2).abs() * -4.0;
    
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Smoke Particles
        ..._particles.map((p) {
          final currentSize = 3.0 + (p.maxRadius - 3.0) * p.progress;
          final currentOpacity = (1.0 - p.progress) * 0.6;
          return Positioned(
            left: 25 + p.x - (currentSize / 2),
            top: 25 + p.y - (currentSize / 2),
            child: Container(
              width: currentSize,
              height: currentSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey.withOpacity(currentOpacity),
              ),
            ),
          );
        }),
        // Vehicle Body
        Transform.translate(
          offset: Offset(0, bounce),
          child: Transform.rotate(
            angle: wobble,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

class _SmokeParticle {
  double x, y;
  double vx, vy;
  double maxRadius;
  double progress = 0.0;

  _SmokeParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.maxRadius,
  });
}

class _BlinkingIndicator extends StatefulWidget {
  const _BlinkingIndicator();

  @override
  State<_BlinkingIndicator> createState() => _BlinkingIndicatorState();
}

class _BlinkingIndicatorState extends State<_BlinkingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _blinkController,
      builder: (context, child) {
        return Opacity(
          opacity: _blinkController.value > 0.5 ? 1.0 : 0.0,
          child: Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.amber,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withOpacity(0.8),
                  blurRadius: 3,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Arc speedometer for the driver-cluster overlay: a background track plus a
/// colored progress arc that sweeps with the current speed.
class _SpeedGaugePainter extends CustomPainter {
  final int speed;
  final int maxSpeed;
  _SpeedGaugePainter({required this.speed, required this.maxSpeed});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    const startAngle = 2.356; // 135° (bottom-left)
    const sweep = 4.712;      // 270° total travel
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withOpacity(0.12);
    canvas.drawArc(rect, startAngle, sweep, false, track);

    final frac = (speed / maxSpeed).clamp(0.0, 1.0);
    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        colors: [Color(0xFF60A5FA), Color(0xFF1a73e8)],
      ).createShader(rect);
    canvas.drawArc(rect, startAngle, sweep * frac, false, progress);
  }

  @override
  bool shouldRepaint(covariant _SpeedGaugePainter old) =>
      old.speed != speed || old.maxSpeed != maxSpeed;
}
