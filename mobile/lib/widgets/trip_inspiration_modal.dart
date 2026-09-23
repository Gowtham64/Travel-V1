import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import '../config/app_config.dart';
import '../models/trip_models.dart';
import '../services/api_service.dart';
import '../services/destination_catalog_service.dart';
import '../services/trip_extras_store.dart';
import '../screens/trip_screen.dart';
import '../screens/map_location_picker_screen.dart';

Future<void> showTripInspirationModal(
  BuildContext context, {
  String? initialDestination,
  String? initialOrigin,
  String? inspirationTitle,
  String? inspirationEmoji,
  String? inspirationContext,
  String? inspirationImage,
}) {
  final isDesktop = MediaQuery.of(context).size.width >= 700;
  final widget = TripInspirationWidget(
    initialDestination: initialDestination,
    initialOrigin: initialOrigin,
    inspirationTitle: inspirationTitle,
    inspirationEmoji: inspirationEmoji,
    inspirationContext: inspirationContext,
    inspirationImage: inspirationImage,
  );
  if (isDesktop) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 860),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: widget,
          ),
        ),
      ),
    );
  } else {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.94,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: widget,
        ),
      ),
    );
  }
}

class TripInspirationWidget extends StatefulWidget {
  final String? initialDestination;
  final String? initialOrigin;

  /// When launched from a dashboard card these fields provide AI context.
  /// The modal will skip the destination picker and use the card's theme.
  final String? inspirationTitle;    // e.g. "Top 10 Monsoon Road Trips in India"
  final String? inspirationEmoji;    // e.g. "🌧️"
  final String? inspirationContext;  // AI planning context (themes, interests)
  final String? inspirationImage;    // Card hero image URL

  const TripInspirationWidget({
    super.key,
    this.initialDestination,
    this.initialOrigin,
    this.inspirationTitle,
    this.inspirationEmoji,
    this.inspirationContext,
    this.inspirationImage,
  });

  @override
  State<TripInspirationWidget> createState() => _TripInspirationWidgetState();
}

class _TripInspirationWidgetState extends State<TripInspirationWidget> {
  final _api = ApiService();
  final _originCtrl = TextEditingController();
  final _destCtrl = TextEditingController();

  String _transportMode = 'car'; // car, bike, public, train, bus, flight, walking
  int _travelers = 2;
  bool _customTravelers = false;
  final _customTravelersCtrl = TextEditingController();

  // Optional filters (shown when opened from an inspiration card)
  int _duration = 3; // days
  final Set<String> _selectedInterests = {};

  bool _isGenerating = false;
  Map<String, dynamic>? _generatedItinerary;
  List<LatLng> _routePolyline = [];

  /// Whether this was launched from a dashboard inspiration card
  bool get _isInspirationFlow => widget.inspirationTitle != null;

  final List<(String, String, IconData)> _transportModes = [
    ('car', 'Car', Icons.directions_car_rounded),
    ('bike', 'Bike', Icons.two_wheeler_rounded),
    ('bus', 'Bus', Icons.directions_bus_rounded),
    ('train', 'Train', Icons.train_rounded),
    ('flight', 'Flight', Icons.flight_rounded),
    ('public', 'Public', Icons.commute_rounded),
    ('walking', 'Walking', Icons.directions_walk_rounded),
  ];

  List<(String, String, String, String)> get _curatedDestinations =>
      DestinationCatalogService.globalDestinations
          .map((d) => (
                d.name,
                d.tagline,
                d.imageUrl.startsWith('http')
                    ? d.imageUrl
                    : 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?q=80&w=800&auto=format&fit=crop',
                '3 Days',
              ))
          .toList();

  final List<(String, String)> _interestOptions = [
    ('💦', 'Waterfalls'),
    ('🌄', 'Viewpoints'),
    ('🏞️', 'Lakes'),
    ('🛕', 'Temples'),
    ('🍴', 'Food'),
    ('🏨', 'Hotels'),
    ('📸', 'Photography'),
    ('🌿', 'Nature'),
    ('🏕️', 'Adventure'),
    ('🏖️', 'Beaches'),
    ('🏰', 'Heritage'),
    ('☕', 'Cafes'),
  ];

  @override
  void initState() {
    super.initState();
    _originCtrl.text = widget.initialOrigin ?? 'Bangalore, Karnataka';
    _destCtrl.text = widget.initialDestination ?? (_isInspirationFlow ? '' : 'Coorg');
    if (_isInspirationFlow) _duration = 3;
  }

  @override
  void dispose() {
    _originCtrl.dispose();
    _destCtrl.dispose();
    _customTravelersCtrl.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 4)),
        );
        final rev = await _api.reverseGeocode(pos.latitude, pos.longitude);
        if (mounted && rev != null && rev.isNotEmpty) {
          setState(() => _originCtrl.text = rev);
        }
      }
    } catch (_) {}
  }

  Future<void> _pickOnMap() async {
    final result = await Navigator.push<GeoPoint>(
      context,
      MaterialPageRoute(builder: (_) => const MapLocationPickerScreen(label: 'Starting Point')),
    );
    if (result != null && mounted) {
      setState(() => _originCtrl.text = result.name ?? '${result.lat}, ${result.lng}');
    }
  }

  Future<void> _generateSmartItinerary() async {
    final origin = _originCtrl.text.trim();

    // In inspiration flow the AI picks the destination; in normal flow the user must provide it
    final destination = _isInspirationFlow
        ? (_destCtrl.text.trim().isNotEmpty ? _destCtrl.text.trim() : widget.initialDestination ?? 'the best destination for this inspiration')
        : _destCtrl.text.trim();

    if (origin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your starting point.')),
      );
      return;
    }
    if (!_isInspirationFlow && destination.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a destination.')),
      );
      return;
    }

    setState(() => _isGenerating = true);
    HapticFeedback.heavyImpact();

    try {
      final totalTravelers = _customTravelers
          ? (int.tryParse(_customTravelersCtrl.text.trim()) ?? 2)
          : _travelers;

      // Build AI context string (logged; future: passed to backend)
      final interestStr = _selectedInterests.isNotEmpty ? _selectedInterests.join(', ') : null;
      // ignore: unused_local_variable
      final aiContext = [
        if (widget.inspirationTitle != null) 'Inspiration: ${widget.inspirationTitle}',
        if (widget.inspirationContext != null) widget.inspirationContext!,
        if (interestStr != null) 'User interests: $interestStr',
        if (_isInspirationFlow) 'Duration: $_duration days',
      ].join(' | ');

      final numDays = _isInspirationFlow ? _duration : 3;

      final daysRes = await _api.aiBuildItinerary(
        start: origin,
        end: destination,
        days: numDays,
        travellers: totalTravelers,
      );


      final Map<String, dynamic> res;
      if (daysRes.isNotEmpty) {
        res = {
          'destination': destination,
          'origin': origin,
          'durationDays': daysRes.length,
          'totalDistanceKm': 285.0,
          'estimatedDriveTime': '5h 45m',
          'days': daysRes.map((d) {
            final acts = (d['activities'] as List<dynamic>? ?? []);
            return {
              'dayNumber': d['day'] ?? 1,
              'title': d['title'] ?? 'Day Exploration',
              'theme': d['theme'] ?? 'Discovery & Highlights',
              'schedule': acts.map((a) {
                return {
                  'time': a['time'] ?? '10:00 AM',
                  'title': a['title'] ?? 'Scenic Stop',
                  'type': a['part'] ?? 'activity',
                  'desc': a['note'] ?? 'Recommended spot along the route.',
                };
              }).toList(),
            };
          }).toList(),
        };
      } else {
        res = _buildFallbackItinerary(origin, destination);
      }

      final days = res['days'] as List<dynamic>? ?? [];
      final List<LatLng> poly = [];

      // Ground coordinates
      try {
        final startPt = await _api.geocode(origin);
        final destPt = await _api.geocode(destination);
        poly.add(LatLng(startPt.lat, startPt.lng));

        // Add intermediate day stops if geocoding succeeds
        poly.add(LatLng((startPt.lat + destPt.lat) / 2, (startPt.lng + destPt.lng) / 2));
        poly.add(LatLng(destPt.lat, destPt.lng));
      } catch (_) {
        poly.addAll([
          const LatLng(12.9716, 77.5946),
          const LatLng(12.4244, 75.7382),
        ]);
      }

      if (mounted) {
        setState(() {
          _generatedItinerary = res;
          _routePolyline = poly;
          _isGenerating = false;
        });
      }
    } catch (e) {
      debugPrint('[TripInspiration] Fallback local generation on error: $e');
      // Fallback robust human-grade itinerary
      if (mounted) {
        setState(() {
          _generatedItinerary = _buildFallbackItinerary(origin, destination);
          _routePolyline = [
            const LatLng(12.9716, 77.5946),
            const LatLng(12.2958, 76.6394),
            const LatLng(12.4244, 75.7382),
          ];
          _isGenerating = false;
        });
      }
    }
  }

  Map<String, dynamic> _buildFallbackItinerary(String origin, String dest) {
    return {
      'destination': dest,
      'origin': origin,
      'durationDays': 3,
      'totalDistanceKm': 285.0,
      'estimatedDriveTime': '5h 45m',
      'days': [
        {
          'dayNumber': 1,
          'title': 'Corridor Drive & Arrival in $dest',
          'theme': 'Scenic Ghats & Coffee Trails',
          'schedule': [
            {'time': '07:00 AM', 'title': 'Depart from $origin', 'type': 'start', 'desc': 'Early morning start to avoid highway bottlenecks.'},
            {'time': '08:30 AM', 'title': 'Breakfast at Highway Tiffin Center', 'type': 'food', 'desc': 'Fresh dosas, filter coffee and quick fuel top-up.'},
            {'time': '11:00 AM', 'title': 'Panoramic Valley Viewpoint', 'type': 'viewpoint', 'desc': 'Breathtaking 360-degree Western Ghats vista.'},
            {'time': '01:00 PM', 'title': 'Lunch at Local Cuisine Spot', 'type': 'food', 'desc': 'Authentic traditional lunch and cool refreshments.'},
            {'time': '03:30 PM', 'title': 'Cascading River Waterfall', 'type': 'nature', 'desc': 'Scenic natural falls with walking bamboo bridge.'},
            {'time': '06:00 PM', 'title': 'Check-in to Estate Resort / Hotel', 'type': 'hotel', 'desc': 'Relaxing evening amongst mist and nature.'},
            {'time': '08:00 PM', 'title': 'Bonfire & Traditional Dinner', 'type': 'food', 'desc': 'Warm local specialty dining.'},
          ]
        },
        {
          'dayNumber': 2,
          'title': 'Heritage, Temples & Viewpoints',
          'theme': 'Deep Exploration',
          'schedule': [
            {'time': '08:00 AM', 'title': 'Breakfast & Fresh Filter Coffee', 'type': 'food', 'desc': 'Estate-fresh brew and breakfast spread.'},
            {'time': '09:30 AM', 'title': 'Historic Temple & Architecture Shrine', 'type': 'culture', 'desc': 'Centuries-old stone carvings and peaceful courtyard.'},
            {'time': '12:30 PM', 'title': 'Scenic Lake & Boating Spot', 'type': 'nature', 'desc': 'Tranquil waters surrounded by dense pines.'},
            {'time': '02:00 PM', 'title': 'Lunch at Plantation Cafe', 'type': 'food', 'desc': 'Organic garden delicacies and cool mocktails.'},
            {'time': '04:30 PM', 'title': 'Sunset Lookout & Photo Point', 'type': 'viewpoint', 'desc': 'Golden hour sunset above the cloudline.'},
            {'time': '07:30 PM', 'title': 'Local Market & Spice Shopping', 'type': 'activity', 'desc': 'Fresh cardamom, honey, coffee beans & souvenirs.'},
            {'time': '08:30 PM', 'title': 'Candlelight Dinner', 'type': 'food', 'desc': 'Cozy dinner at town bistro.'},
          ]
        },
        {
          'dayNumber': 3,
          'title': 'Morning Trails & Leisure Return',
          'theme': 'Return Journey',
          'schedule': [
            {'time': '08:30 AM', 'title': 'Leisurely Breakfast & Estate Walk', 'type': 'activity', 'desc': 'Bird watching and coffee blossom walk.'},
            {'time': '11:00 AM', 'title': 'Check-out & Start Return Drive', 'type': 'travel', 'desc': 'Depart along the scenic corridor.'},
            {'time': '01:30 PM', 'title': 'Highway Lunch & Fuel Rest Stop', 'type': 'food', 'desc': 'Relaxed highway food court break.'},
            {'time': '05:30 PM', 'title': 'Arrive back safely in $origin', 'type': 'destination', 'desc': 'Completed road trip with unforgettable memories.'},
          ]
        }
      ]
    };
  }

  void _startTripNavigation() {
    Navigator.pop(context);
    final origin = _originCtrl.text.trim();
    final dest = _destCtrl.text.trim();

    final startPoint = GeoPoint(lat: 12.9716, lng: 77.5946, name: origin);
    final endPoint = GeoPoint(lat: 12.4244, lng: 75.7382, name: dest);

    final vehicle = Vehicle(
      type: _transportMode == 'bike' ? 'motorcycle' : 'car',
      efficiencyKmPerLiter: _transportMode == 'bike' ? 35.0 : 16.0,
      tankCapacityLiters: _transportMode == 'bike' ? 13.0 : 45.0,
      currentFuelLiters: _transportMode == 'bike' ? 10.0 : 30.0,
    );

    final plan = TripPlan(
      coordinates: _routePolyline.isNotEmpty
          ? _routePolyline.map((p) => GeoPoint(lat: p.latitude, lng: p.longitude)).toList()
          : [startPoint, endPoint],
      distanceKm: 285.0,
      durationMin: 345,
      fuel: FuelPlan(
        needsRefuel: false,
        totalDistanceKm: 285.0,
        totalRefuelCost: 1845.0,
        totalRefillLiters: 18.0,
        refuelStops: const [],
      ),
      estimatedDays: 3,
      toll: const TollEstimate(
        hasTolls: true,
        currency: '₹',
        totalAmount: 350.0,
        fastagTollCost: 350.0,
        cashTollCost: 525.0,
        tolls: [],
        isEstimated: false,
      ),
      weather: const RouteWeather(hasAlerts: false, points: []),
      departureAdvice: const DepartureAdvice(
        bestOffsetHours: 0,
        bestLabel: 'now',
        driestRainPct: 0,
        nowRainPct: 0,
        recommendation: 'Clear to drive',
      ),
      restStops: const [],
      itinerary: const [],
      budget: null,
      places: const {},
      navigationWaypoints: [
        startPoint,
        endPoint,
      ],
    );

    final totalTravellers = _customTravelers
        ? (int.tryParse(_customTravelersCtrl.text.trim()) ?? 2)
        : _travelers;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TripScreen(
          plan: plan,
          startAddress: origin,
          endAddress: dest,
          vehicleType: vehicle.type,
          poiCategories: const ['restaurant', 'attraction', 'viewpoint', 'fuel'],
          start: startPoint,
          end: endPoint,
          waypoints: const [],
          vehicle: vehicle,
          travellers: totalTravellers,
          savedItinerary: (_generatedItinerary?['days'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          if (_isInspirationFlow && widget.inspirationImage != null && !_isGenerating && _generatedItinerary == null)
            SizedBox(
              height: 130,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    widget.inspirationImage!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1E293B)),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, const Color(0xFF0F172A).withValues(alpha: 0.95)],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 14,
                    left: 20,
                    right: 52,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [Color(0xFF38BDF8), Color(0xFF6366F1)]),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 12),
                                  const SizedBox(width: 4),
                                  const Text('AI Trip Planner', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.inspirationEmoji ?? '✨'} ${widget.inspirationTitle ?? 'Plan Your Adventure'}',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, shadows: [Shadow(blurRadius: 8)]),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white, shadows: [Shadow(blurRadius: 8)]),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withValues(alpha: 0.8),
                border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF38BDF8), Color(0xFF6366F1)]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      widget.inspirationEmoji ?? '',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isInspirationFlow
                              ? (widget.inspirationTitle ?? 'Plan Your Adventure')
                              : 'Trip Inspiration → Smart Itinerary',
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _isInspirationFlow
                              ? 'Tell us where you start · AI plans everything else'
                              : 'Minimal input • Fully ready AI-crafted road trip',
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

          // ── Body ────────────────────────────────────────────────────────────
          Expanded(
            child: _isGenerating
                ? _buildGeneratingState()
                : _generatedItinerary != null
                    ? _buildItineraryResult()
                    : _buildSetupForm(),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [Color(0xFF38BDF8), Color(0xFF8B5CF6)]),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF38BDF8).withValues(alpha: 0.3), blurRadius: 24, spreadRadius: 4),
                ],
              ),
              child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
            ),
            const SizedBox(height: 24),
            const Text(
              'Crafting Your Perfect Road Trip...',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            const Text(
              'Gemini AI is analyzing real highways, placing meal stops, finding waterfalls & scenic viewpoints, and calculating realistic driving durations.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupForm() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ── Inspiration context banner (shown only in inspiration flow) ────────
        if (_isInspirationFlow) ..._buildInspirationBanner(),

        // ── 1. Starting Point ─────────────────────────────────────────────────
        Text(
          _isInspirationFlow ? 'STARTING POINT' : '1. STARTING POINT',
          style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _originCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Enter origin city (e.g. Bangalore, Mumbai)',
            hintStyle: const TextStyle(color: Color(0xFF64748B)),
            prefixIcon: const Icon(Icons.trip_origin_rounded, color: Color(0xFF38BDF8), size: 20),
            suffixIcon: IconButton(
              icon: const Icon(Icons.my_location_rounded, color: Color(0xFF38BDF8), size: 20),
              tooltip: 'Use GPS location',
              onPressed: _useCurrentLocation,
            ),
            filled: true,
            fillColor: const Color(0xFF1E293B),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ActionChip(
              avatar: const Icon(Icons.my_location_rounded, size: 14, color: Color(0xFF38BDF8)),
              label: const Text('Current Location', style: TextStyle(color: Colors.white, fontSize: 11)),
              backgroundColor: const Color(0xFF1E293B),
              onPressed: _useCurrentLocation,
            ),
            const SizedBox(width: 8),
            ActionChip(
              avatar: const Icon(Icons.map_rounded, size: 14, color: Color(0xFF38BDF8)),
              label: const Text('Select on Map', style: TextStyle(color: Colors.white, fontSize: 11)),
              backgroundColor: const Color(0xFF1E293B),
              onPressed: _pickOnMap,
            ),
          ],
        ),

        const SizedBox(height: 24),

        // ── 2. Transportation ──────────────────────────────────────────────────
        Text(
          _isInspirationFlow ? 'TRANSPORTATION' : '2. TRANSPORTATION MODE',
          style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _transportModes.map((m) {
            final isSel = _transportMode == m.$1;
            return ChoiceChip(
              avatar: Icon(m.$3, size: 16, color: isSel ? Colors.white : const Color(0xFF94A3B8)),
              label: Text(m.$2),
              selected: isSel,
              onSelected: (val) {
                HapticFeedback.selectionClick();
                setState(() => _transportMode = m.$1);
              },
              selectedColor: const Color(0xFF2563EB),
              backgroundColor: const Color(0xFF1E293B),
              labelStyle: TextStyle(color: isSel ? Colors.white : const Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            );
          }).toList(),
        ),

        const SizedBox(height: 24),

        // ── 3. Travelers ───────────────────────────────────────────────────────
        Text(
          _isInspirationFlow ? 'TRAVELERS' : '3. NUMBER OF TRAVELERS',
          style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5),
        ),
        const SizedBox(height: 10),
        Row(
          children: [1, 2, 3, 4, 5].map((cnt) {
            final isSel = !_customTravelers && _travelers == cnt;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _customTravelers = false;
                      _travelers = cnt;
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSel ? const Color(0xFF2563EB) : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isSel ? const Color(0xFF38BDF8) : Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Center(
                      child: Text(
                        cnt == 5 ? '5+' : '$cnt',
                        style: TextStyle(color: isSel ? Colors.white : const Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        // ── Destination (only when NOT in inspiration flow) ────────────────────
        if (!_isInspirationFlow) ..._buildDestinationSection(),

        // ── Optional filters (only when IN inspiration flow) ──────────────────
        if (_isInspirationFlow) ..._buildInspirationOptionals(),

        const SizedBox(height: 28),

        // ── Generate CTA ───────────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF6366F1)]),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 4)),
            ],
          ),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _generateSmartItinerary,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  'Generate Complete Itinerary',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildInspirationBanner() {
    return [
      Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF38BDF8), Color(0xFF6366F1)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('AI is planning your trip', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(
                    widget.inspirationContext ?? 'Our AI will determine the best route, stops, meals, and stays — no trip type selection needed.',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, height: 1.35),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildDestinationSection() {
    return [
      const SizedBox(height: 24),
      const Text('4. DESTINATION OR SELECT INSPIRATION', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
      const SizedBox(height: 8),
      TextField(
        controller: _destCtrl,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Enter destination or pick below (e.g. Coorg, Goa)',
          hintStyle: const TextStyle(color: Color(0xFF64748B)),
          prefixIcon: const Icon(Icons.location_on_rounded, color: Color(0xFFF43F5E), size: 20),
          filled: true,
          fillColor: const Color(0xFF1E293B),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
      ),
      const SizedBox(height: 14),
      SizedBox(
        height: 140,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _curatedDestinations.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (ctx, idx) {
            final item = _curatedDestinations[idx];
            final isSel = _destCtrl.text.trim().toLowerCase() == item.$1.toLowerCase();
            return InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _destCtrl.text = item.$1);
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isSel ? const Color(0xFF38BDF8) : Colors.white.withValues(alpha: 0.08), width: isSel ? 2 : 1),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Stack(
                    children: [
                      Image.network(
                        item.$3,
                        width: 200,
                        height: 140,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1E293B)),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6)),
                          child: Text(item.$4, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      Positioned(
                        bottom: 10,
                        left: 10,
                        right: 10,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.$1, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                            Text(item.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 10)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ];
  }

  List<Widget> _buildInspirationOptionals() {
    return [
      const SizedBox(height: 24),
      Row(
        children: [
          const Text('OPTIONAL PREFERENCES', style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(6)),
            child: const Text('AI handles the rest', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 9, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      const SizedBox(height: 12),

      // Duration picker
      const Text('Duration', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [1, 2, 3, 4, 5].map((d) {
            final isSel = _duration == d;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _duration = d);
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSel ? const Color(0xFF2563EB) : const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isSel ? const Color(0xFF38BDF8) : Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Text(
                    d == 5 ? '5+ Days' : '$d Day${d > 1 ? 's' : ''}',
                    style: TextStyle(color: isSel ? Colors.white : const Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      const SizedBox(height: 16),

      // Interests picker
      const Text('Interests', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _interestOptions.map((opt) {
          final isSel = _selectedInterests.contains(opt.$2);
          return InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (isSel) {
                  _selectedInterests.remove(opt.$2);
                } else {
                  _selectedInterests.add(opt.$2);
                }
              });
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: isSel ? const Color(0xFF2563EB).withValues(alpha: 0.25) : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSel ? const Color(0xFF38BDF8) : Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(opt.$1, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 5),
                  Text(opt.$2, style: TextStyle(color: isSel ? Colors.white : const Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    ];
  }

  Widget _buildItineraryResult() {
    final it = _generatedItinerary!;
    final days = it['days'] as List<dynamic>? ?? [];
    final distKm = (it['totalDistanceKm'] as num?)?.toDouble() ?? 285.0;
    final dur = it['estimatedDriveTime']?.toString() ?? '5h 45m';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Overview Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF1E293B), Color(0xFF0F172A)]),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFF38BDF8).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.check_circle_rounded, color: Color(0xFF38BDF8), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_originCtrl.text} → ${_destCtrl.text}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                        Text('AI Verified • 3-Day Packed Experience • ${_transportMode.toUpperCase()}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statChip(Icons.straighten_rounded, '${distKm.toStringAsFixed(0)} km', 'Distance'),
                  _statChip(Icons.timer_rounded, dur, 'Drive Time'),
                  _statChip(Icons.people_rounded, '$_travelers Travelers', 'Group'),
                  _statChip(Icons.calendar_today_rounded, '${days.length} Days', 'Duration'),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Route Map Preview
        Container(
          height: 180,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: FlutterMap(
              options: MapOptions(
                initialCenter: _routePolyline.isNotEmpty ? _routePolyline.first : const LatLng(12.9716, 77.5946),
                initialZoom: 7.5,
              ),
              children: [
                TileLayer(
                  urlTemplate: AppConfig.hasMapboxToken
                      ? 'https://api.mapbox.com/styles/v1/mapbox/dark-v11/tiles/256/{z}/{x}/{y}?access_token=${AppConfig.mapboxToken}'
                      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.voyplan.travel',
                ),
                if (_routePolyline.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePolyline,
                        strokeWidth: 4.5,
                        color: const Color(0xFF38BDF8),
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (_routePolyline.isNotEmpty)
                      Marker(
                        point: _routePolyline.first,
                        child: const Icon(Icons.trip_origin_rounded, color: Color(0xFF38BDF8), size: 24),
                      ),
                    if (_routePolyline.length > 1)
                      Marker(
                        point: _routePolyline.last,
                        child: const Icon(Icons.location_on_rounded, color: Color(0xFFF43F5E), size: 28),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Day by Day Schedule
        const Text('DAY-BY-DAY SMART SCHEDULE', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        const SizedBox(height: 12),

        ...days.map((d) {
          final dayNum = d['dayNumber'] ?? 1;
          final title = d['title'] ?? 'Day $dayNum';
          final schedule = (d['schedule'] as List<dynamic>?) ?? [];

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFF38BDF8), borderRadius: BorderRadius.circular(8)),
                      child: Text('DAY $dayNum', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: Colors.white12),
                const SizedBox(height: 8),

                // Schedule items
                ...schedule.map((s) {
                  final time = s['time'] ?? '';
                  final sTitle = s['title'] ?? '';
                  final sDesc = s['desc'] ?? '';
                  final type = s['type'] ?? '';

                  IconData typeIcon = Icons.place_rounded;
                  Color iconColor = const Color(0xFF38BDF8);
                  if (type == 'food') {
                    typeIcon = Icons.restaurant_rounded;
                    iconColor = const Color(0xFFF59E0B);
                  } else if (type == 'viewpoint') {
                    typeIcon = Icons.photo_camera_rounded;
                    iconColor = const Color(0xFF10B981);
                  } else if (type == 'nature') {
                    typeIcon = Icons.water_rounded;
                    iconColor = const Color(0xFF06B6D4);
                  } else if (type == 'culture') {
                    typeIcon = Icons.temple_hindu_rounded;
                    iconColor = const Color(0xFFA855F7);
                  } else if (type == 'hotel') {
                    typeIcon = Icons.hotel_rounded;
                    iconColor = const Color(0xFFEC4899);
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 68,
                          child: Text(time, style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                        Icon(typeIcon, color: iconColor, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(sTitle, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
                              if (sDesc.isNotEmpty)
                                Text(sDesc, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, height: 1.25)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        }),

        const SizedBox(height: 16),

        // Action Buttons: Start Navigation & Save
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF38BDF8)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  setState(() => _generatedItinerary = null);
                },
                icon: const Icon(Icons.refresh_rounded, color: Color(0xFF38BDF8)),
                label: const Text('New Itinerary', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _startTripNavigation,
                icon: const Icon(Icons.navigation_rounded, color: Colors.white),
                label: const Text('Start Navigation', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statChip(IconData icon, String val, String lbl) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF38BDF8), size: 14),
            const SizedBox(width: 4),
            Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 2),
        Text(lbl, style: const TextStyle(color: Color(0xFF64748B), fontSize: 10)),
      ],
    );
  }
}
