import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../models/trip_models.dart';
import '../models/vehicles_data.dart';
import '../utils/landing_redirect.dart';
import '../services/api_service.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'trip_screen.dart';
import 'trip_workspace_screen.dart';
import 'itinerary_screen.dart';
import 'saved_trips_screen.dart';
import '../widgets/app_design.dart';
import '../widgets/globe_preview.dart';
import 'map_location_picker_screen.dart';

class TripPlannerScreen extends StatefulWidget {
  /// Pre-selects the route type ('oneway' or 'roundtrip'), e.g. when chosen on
  /// the home dashboard before opening the planner.
  final String initialTripType;

  /// Optional pre-filled destination (e.g. a trailhead chosen in trek discovery).
  /// When set, the last stop's text and resolved coordinates are seeded so the
  /// user only needs to enter a starting point.
  final GeoPoint? initialDestination;
  final String? initialDestinationLabel;

  /// Optional pre-selected trip options handed in from another flow (e.g. the
  /// trek planner), so "plan trip to trailhead" arrives fully configured.
  final String? initialVehicleId;
  final int? initialTravellers;
  final double? initialCurrentFuelLiters;
  final List<String>? initialPOIs;

  const TripPlannerScreen({
    super.key,
    this.initialTripType = 'oneway',
    this.initialDestination,
    this.initialDestinationLabel,
    this.initialVehicleId,
    this.initialTravellers,
    this.initialCurrentFuelLiters,
    this.initialPOIs,
  });

  @override
  State<TripPlannerScreen> createState() => _TripPlannerScreenState();
}

class _TripPlannerScreenState extends State<TripPlannerScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _api = ApiService();
  late final AnimationController _bgController;

  final List<TextEditingController> _stopControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  // Pre-resolved coordinates for stops added from POI list (keyed by controller hashCode)
  final Map<int, GeoPoint> _resolvedStopCoords = {};
  final Map<int, bool> _loadingLocationForIndex = {};

  final _efficiencyController = TextEditingController();
  final _tankController = TextEditingController();
  final _currentFuelController = TextEditingController(text: '30');

  VehicleModel? _selectedVehicle;
  int _travellers = 1;
  // Trip type: 'oneway' (A → B) or 'roundtrip' (A → B → A, i.e. a vacation).
  late String _tripType = widget.initialTripType;
  final Set<String> _selectedPOIs = {'restaurant', 'attraction'};
  List<String> _appliedPOIs = ['restaurant', 'attraction'];
  bool _loading = false;
  String? _error;

  // Manual place search + popular-stop suggestions (Places to Visit card).
  final _placeSearchController = TextEditingController();
  bool _searchingPlace = false;
  bool _suggestingPopular = false;
  // Live autocomplete for the place-search box.
  List<Map<String, dynamic>> _placeSuggestions = [];
  Timer? _placeSearchDebounce;
  
  TripPlan? _currentPlan;
  GeoPoint? _currentStart;
  GeoPoint? _currentEnd;
  List<GeoPoint>? _currentWaypoints;
  Vehicle? _currentVehicle;

  // Temp plan from "Find Places" — does NOT trigger trip screen switch
  TripPlan? _tempPlan;
  GeoPoint? _tempStart;
  GeoPoint? _tempEnd;
  List<GeoPoint>? _tempWaypoints;

  // Start location the preview globe should fly to (web only).
  GeoPoint? _startFocusPoint;

  // Mapbox Search autocomplete: suggestions per stop index + debounce timer.
  final Map<int, List<Map<String, dynamic>>> _suggestions = {};
  int? _activeSuggestIndex;
  Timer? _suggestDebounce;
  static const String _mapboxToken = AppConfig.mapboxToken;
  Vehicle? _tempVehicle;
  
  Map<String, List<PlaceOfInterest>> _pois = {};
  bool _loadingPOIs = false;
  bool _hasSearchedPOIs = false;
  String? _userName;
  final Map<String, String> _resolvedAddresses = {};
  final Set<String> _requestedAddresses = {};

  final ScrollController _formScrollController = ScrollController();
  final MapController _mapController = MapController();
  
  final String _bgUrl = 'https://images.unsplash.com/photo-1518509562904-e7ef99cdcc86?q=80&w=2000&auto=format&fit=crop';

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 34),
    )..repeat(reverse: true);
    // Honour a vehicle handed in from another flow, else default to a car.
    _selectedVehicle = predefinedVehicles.firstWhere(
      (v) => v.id == widget.initialVehicleId,
      orElse: () => predefinedVehicles.firstWhere((v) => v.type == 'car'),
    );
    _updateVehicleFields();
    // Apply pre-selected options AFTER _updateVehicleFields (which sets fuel).
    if (widget.initialTravellers != null) _travellers = widget.initialTravellers!;
    if (widget.initialCurrentFuelLiters != null) {
      _currentFuelController.text = _formatNum(widget.initialCurrentFuelLiters!);
    }
    if (widget.initialPOIs != null) {
      _selectedPOIs
        ..clear()
        ..addAll(widget.initialPOIs!);
      _appliedPOIs = List.from(widget.initialPOIs!);
    }
    _recordUserSession();

    // Seed a destination handed in from trek discovery ("plan around this trail").
    if (widget.initialDestination != null) {
      final dest = widget.initialDestination!;
      final label = widget.initialDestinationLabel ?? dest.name ?? 'Trailhead';
      _stopControllers.last.text = label;
      _resolvedStopCoords[_stopControllers.last.hashCode] = dest;
    }

    // Automated test route search for headless integration testing
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final uri = Uri.base;
        if (uri.toString().contains('test_route=true')) {
          _runTestRoute();
        }
        // Open a trip shared via a "?trip=" link.
        final tripParam = uri.queryParameters['trip'];
        if (tripParam != null && tripParam.isNotEmpty) {
          _openSharedTrip(tripParam);
        }
      });
    }
  }

  /// Decodes a shared-trip payload from the URL and plans it directly from the
  /// embedded coordinates (no geocoding needed), then opens the trip screen.
  Future<void> _openSharedTrip(String encoded) async {
    try {
      final jsonStr = utf8.decode(base64Url.decode(base64Url.normalize(encoded)));
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      GeoPoint pt(List<dynamic> a, [String? name]) =>
          GeoPoint(lat: (a[0] as num).toDouble(), lng: (a[1] as num).toDouble(), name: name);

      final start = pt(data['s'] as List, data['sa'] as String?);
      final end = pt(data['e'] as List, data['ea'] as String?);
      final waypoints = ((data['w'] as List?) ?? []).map((w) => pt(w as List)).toList();
      final v = data['v'] as Map<String, dynamic>;
      final vehicle = Vehicle(
        type: v['t'] as String? ?? 'car',
        efficiencyKmPerLiter: (v['e'] as num?)?.toDouble() ?? 15,
        tankCapacityLiters: (v['tk'] as num?)?.toDouble() ?? 40,
        currentFuelLiters: (v['cf'] as num?)?.toDouble() ?? 30,
      );

      setState(() => _loading = true);
      final plan = await _api.planTrip(start: start, end: end, waypoints: waypoints, vehicle: vehicle);
      if (!mounted) return;
      // Same trip summary (tolls, fuel, times) shown after DONE. Skipped for the
      // headless preview test hook so it can drive straight into the trip.
      if (!(kIsWeb && Uri.base.toString().contains('test_preview=true'))) {
        await _showTripSummaryDialog(plan, vehicle);
        if (!mounted) return;
      }
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TripScreen(
          plan: plan,
          startAddress: data['sa'] as String? ?? 'Start',
          endAddress: data['ea'] as String? ?? 'Destination',
          vehicleType: vehicle.type,
          poiCategories: const [],
          start: start,
          end: end,
          waypoints: waypoints,
          vehicle: vehicle,
          modelSubtype: data['sub'] as String?,
        ),
      ));
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open shared trip: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runTestRoute() async {
    print("RUNNING AUTOMATED TEST ROUTE SEARCH...");
    _stopControllers[0].text = "Bangalore";
    _stopControllers[1].text = "Mysore";
    
    // Seed pre-resolved coordinate values to bypass geocoding lookup
    _resolvedStopCoords[_stopControllers[0].hashCode] = const GeoPoint(lat: 12.9716, lng: 77.5946, name: "Bangalore");
    _resolvedStopCoords[_stopControllers[1].hashCode] = const GeoPoint(lat: 12.2958, lng: 76.6394, name: "Mysore");
    
    setState(() {
      _selectedVehicle = predefinedVehicles.firstWhere((v) => v.type == 'car');
      _efficiencyController.text = "22";
      _tankController.text = "37";
      _currentFuelController.text = "30";
      _selectedPOIs.clear();
      _selectedPOIs.addAll(['restaurant', 'attraction']);
    });
    
    await Future.delayed(const Duration(milliseconds: 500));
    await _findPlacesBeforeTrip();
  }

  String _getDeviceAccessInfo() {
    if (kIsWeb) return 'Web Browser';
    try {
      if (Platform.isAndroid) return 'Android Device';
      if (Platform.isIOS) return 'iOS Device';
      if (Platform.isMacOS) return 'macOS App';
      if (Platform.isWindows) return 'Windows App';
      if (Platform.isLinux) return 'Linux App';
      return 'Mobile App';
    } catch (_) {
      return 'Unknown Device';
    }
  }

  Future<void> _recordUserSession() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // Check if user_details already exists for this user
      final response = await Supabase.instance.client
          .from('user_details')
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (response == null) {
        final name = user.userMetadata?['full_name'] ?? user.userMetadata?['name'] ?? 'Traveler';
        final email = user.email ?? '';
        final phone = user.phone ?? '';
        final deviceAccess = _getDeviceAccessInfo();
        
        await Supabase.instance.client.from('user_details').insert({
          'user_id': user.id,
          'name': name,
          'phone': phone,
          'email': email,
          'password_hash': 'OAuth / Google',
          'location': 'Not Provided',
          'device_access': deviceAccess,
        });
      }
    } catch (e) {
      debugPrint('Failed to record user details: $e');
    }
  }

  void _updateVehicleFields() {
    if (_selectedVehicle != null) {
      final tank = _selectedVehicle!.tankCapacity;
      _efficiencyController.text = _formatNum(_selectedVehicle!.mileage);
      _tankController.text = _formatNum(tank);
      // Keep "current fuel" valid: never more than the (possibly smaller) tank.
      // Default to a full tank; if the user had already entered a smaller amount
      // that still fits, keep it.
      final existing = double.tryParse(_currentFuelController.text);
      final current = (existing != null && existing > 0 && existing <= tank) ? existing : tank;
      _currentFuelController.text = _formatNum(current);
    }
  }

  /// Formats a spec number without a trailing ".0" (e.g. 15.0 -> "15", 22.3 -> "22.3").
  String _formatNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  Future<void> _planTrip() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedVehicle == null) {
      setState(() => _error = 'Please select a vehicle');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Reuse already-computed plan from "Find Places" if available
      final TripPlan plan;
      final GeoPoint start;
      final GeoPoint end;
      final List<GeoPoint> waypoints;
      final Vehicle vehicle;

      if (_tempPlan != null && _tempStart != null && _tempEnd != null &&
          _tempWaypoints != null && _tempVehicle != null) {
        plan = _tempPlan!;
        start = _tempStart!;
        end = _tempEnd!;
        waypoints = _tempWaypoints!;
        vehicle = _tempVehicle!;
      } else {
        final List<GeoPoint> geocodedStops = [];
        for (final controller in _stopControllers) {
          final address = controller.text.trim();
          if (address.isNotEmpty) {
            final resolved = _resolvedStopCoords[controller.hashCode];
            final isMatch = resolved != null &&
                resolved.name != null &&
                (resolved.name!.toLowerCase().contains(address.toLowerCase()) ||
                 address.toLowerCase().contains(resolved.name!.toLowerCase()));
            if (resolved != null && isMatch) {
              geocodedStops.add(resolved);
            } else {
              final point = await _api.geocode(address);
              geocodedStops.add(point);
              _resolvedStopCoords[controller.hashCode] = point;
            }
          }
        }

        if (geocodedStops.length < 2) {
          throw Exception("Need at least a starting point and destination");
        }

        if (_tripType == 'roundtrip') {
          // Vacation / round trip: go to the destination (and any stops) then
          // return to the starting point, so distance/fuel/budget cover both legs.
          start = geocodedStops.first;
          end = geocodedStops.first;
          waypoints = geocodedStops.sublist(1);
        } else {
          start = geocodedStops.first;
          end = geocodedStops.last;
          waypoints = geocodedStops.sublist(1, geocodedStops.length - 1);
        }

        vehicle = Vehicle(
          type: _selectedVehicle!.type,
          efficiencyKmPerLiter: double.parse(_efficiencyController.text),
          tankCapacityLiters: double.parse(_tankController.text),
          currentFuelLiters: double.parse(_currentFuelController.text),
        );

        plan = await _api.planTrip(
          start: start,
          end: end,
          waypoints: waypoints,
          vehicle: vehicle,
          travellers: _travellers,
        );
      }

      if (!mounted) return;

      // Round trip (vacation) → go straight to the day-by-day Plan workspace,
      // skipping the summary popup.
      if (_tripType == 'roundtrip') {
        final startAddr = _stopControllers.first.text.trim();
        final endAddr = _stopControllers.last.text.trim();
        final tripKey = [
          start.lat.toStringAsFixed(3), start.lng.toStringAsFixed(3),
          end.lat.toStringAsFixed(3), end.lng.toStringAsFixed(3),
          vehicle.type,
        ].join('_').replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '');
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TripWorkspaceScreen(
            tripKey: tripKey,
            tripName: '$startAddr → $endAddr (round trip)',
            plan: plan,
            start: start,
            end: end,
            waypoints: waypoints,
            vehicle: vehicle,
            startAddress: startAddr,
            endAddress: endAddr,
            tripStart: DateTime.now(),
            travellers: _travellers,
            currency: plan.budget?.currency ?? 'INR',
            initialTabIndex: 1, // Plan tab
          ),
        ));
        return;
      }

      // Trip summary (toll details, fuel price, times) right after DONE, so the
      // user reviews the estimate before the drive.
      await _showTripSummaryDialog(plan, vehicle);
      if (!mounted) return;

      if (MediaQuery.of(context).size.width > 900) {
        setState(() {
          _currentPlan = plan;
          _appliedPOIs = _selectedPOIs.toList();
          _currentStart = start;
          _currentEnd = end;
          _currentWaypoints = waypoints;
          _currentVehicle = vehicle;
          // Clear temp plan once committed
          _tempPlan = null;
          _tempStart = null;
          _tempEnd = null;
          _tempWaypoints = null;
          _tempVehicle = null;
        });
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TripScreen(
              plan: plan,
              startAddress: _stopControllers.first.text.trim(),
              endAddress: _stopControllers.last.text.trim(),
              vehicleType: _selectedVehicle!.type,
              poiCategories: _selectedPOIs.toList(),
              start: start,
              end: end,
              waypoints: waypoints,
              vehicle: vehicle,
              initialPois: _pois.isNotEmpty ? _pois : null,
              modelSubtype: model3DKey(_selectedVehicle!),
              travellers: _travellers,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Plans the trip (reusing a "Find Places" preview if present) and opens the
  /// AI Itinerary directly, so the itinerary can be set up from the planner.
  Future<void> _planAndOpenItinerary() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedVehicle == null) {
      setState(() => _error = 'Please select a vehicle');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final TripPlan plan;
      final GeoPoint start;
      final GeoPoint end;
      final List<GeoPoint> waypoints;
      final Vehicle vehicle;

      if (_tempPlan != null && _tempStart != null && _tempEnd != null &&
          _tempWaypoints != null && _tempVehicle != null) {
        plan = _tempPlan!;
        start = _tempStart!;
        end = _tempEnd!;
        waypoints = _tempWaypoints!;
        vehicle = _tempVehicle!;
      } else {
        final List<GeoPoint> geocodedStops = [];
        for (final controller in _stopControllers) {
          final address = controller.text.trim();
          if (address.isNotEmpty) {
            final resolved = _resolvedStopCoords[controller.hashCode];
            final isMatch = resolved != null &&
                resolved.name != null &&
                (resolved.name!.toLowerCase().contains(address.toLowerCase()) ||
                    address.toLowerCase().contains(resolved.name!.toLowerCase()));
            if (resolved != null && isMatch) {
              geocodedStops.add(resolved);
            } else {
              final point = await _api.geocode(address);
              geocodedStops.add(point);
              _resolvedStopCoords[controller.hashCode] = point;
            }
          }
        }
        if (geocodedStops.length < 2) {
          throw Exception("Need at least a starting point and destination");
        }
        if (_tripType == 'roundtrip') {
          start = geocodedStops.first;
          end = geocodedStops.first;
          waypoints = geocodedStops.sublist(1);
        } else {
          start = geocodedStops.first;
          end = geocodedStops.last;
          waypoints = geocodedStops.sublist(1, geocodedStops.length - 1);
        }
        vehicle = Vehicle(
          type: _selectedVehicle!.type,
          efficiencyKmPerLiter: double.parse(_efficiencyController.text),
          tankCapacityLiters: double.parse(_tankController.text),
          currentFuelLiters: double.parse(_currentFuelController.text),
        );
        plan = await _api.planTrip(
          start: start,
          end: end,
          waypoints: waypoints,
          vehicle: vehicle,
          travellers: _travellers,
        );
      }

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ItineraryScreen(
            plan: plan,
            startAddress: _stopControllers.first.text.trim(),
            endAddress: _stopControllers.last.text.trim(),
            start: start,
            end: end,
            waypoints: waypoints,
            vehicleType: vehicle.type,
            vehicle: vehicle,
            travellers: _travellers,
            tripStart: DateTime.now(),
          ),
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Trip summary shown after DONE: toll details, fuel price, and times.
  Future<void> _showTripSummaryDialog(TripPlan plan, Vehicle vehicle) async {
    final toll = plan.toll;
    final double fastag = toll?.fastagTollCost ?? 0;
    final double cash = toll?.cashTollCost ?? 0;
    final double? minT = toll?.minTollCost;
    final double? maxT = toll?.maxTollCost;
    final double litres = vehicle.efficiencyKmPerLiter > 0
        ? plan.distanceKm / vehicle.efficiencyKmPerLiter
        : 0;
    // Fall back to litres x current pump price when the plan omits a fuel cost,
    // so the estimate is always meaningful (matches the trip screen's figure).
    const double defaultPumpPrice = 102.0; // ₹/L (petrol, India)
    double fuelCost = toll?.fuelCost ?? 0;
    if (fuelCost <= 0) fuelCost = litres * defaultPumpPrice;
    final double pricePerL = litres > 0 ? fuelCost / litres : defaultPumpPrice;

    final now = DateTime.now();
    final eta = now.add(Duration(minutes: plan.durationMin));
    final String durText = plan.durationMin >= 60
        ? '${plan.durationMin ~/ 60}h ${plan.durationMin % 60}m'
        : '${plan.durationMin} min';
    String clock(DateTime t) {
      final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
      final m = t.minute.toString().padLeft(2, '0');
      return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
    }

    Widget sectionTitle(IconData icon, String label) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Icon(icon, color: AppColors.accentLight, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3)),
          ]),
        );
    Widget row(String k, String v, {Color? valueColor, bool strong = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(k, style: TextStyle(color: Colors.white.withOpacity(0.62), fontSize: 13)),
              Text(v,
                  style: TextStyle(
                      color: valueColor ?? Colors.white,
                      fontSize: strong ? 15 : 13.5,
                      fontWeight: strong ? FontWeight.bold : FontWeight.w600)),
            ],
          ),
        );
    Widget card(Widget child) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: child,
        );

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF12161F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(ctx).padding.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text('Trip Summary',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text('${plan.distanceKm.toStringAsFixed(1)} km route',
                  style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 13)),
              const SizedBox(height: 18),

              // Times
              card(Column(children: [
                sectionTitle(Icons.schedule, 'Times'),
                row('Driving time', durText),
                row('Departure', clock(now)),
                row('Arrival (ETA)', clock(eta), valueColor: Colors.greenAccent, strong: true),
              ])),

              // Toll details
              card(Column(children: [
                sectionTitle(Icons.receipt_long, 'Toll Details'),
                row('FASTag toll', '₹${fastag.toStringAsFixed(0)}'),
                row('Cash toll', '₹${cash.toStringAsFixed(0)}'),
                if (minT != null && maxT != null)
                  row('Estimated range', '₹${minT.toStringAsFixed(0)} – ₹${maxT.toStringAsFixed(0)}'),
                const Divider(color: Colors.white12, height: 18),
                row('You pay (FASTag)', '₹${fastag.toStringAsFixed(0)}',
                    valueColor: AppColors.accentLight, strong: true),
              ])),

              // Fuel
              card(Column(children: [
                sectionTitle(Icons.local_gas_station, 'Fuel'),
                row('Fuel needed', '${litres.toStringAsFixed(1)} L'),
                row('Price / litre (est.)', '₹${pricePerL.toStringAsFixed(1)}'),
                row('Mileage', '${vehicle.efficiencyKmPerLiter.toStringAsFixed(0)} km/L'),
                const Divider(color: Colors.white12, height: 18),
                row('Fuel cost', '₹${fuelCost.toStringAsFixed(0)}',
                    valueColor: Colors.orangeAccent, strong: true),
              ])),

              const SizedBox(height: 4),
              AccentButton(
                onPressed: () => Navigator.of(ctx).pop(),
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: const Text('Start Trip',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _findPlacesBeforeTrip({List<String>? categories}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedVehicle == null) {
      setState(() => _error = 'Please select a vehicle');
      return;
    }
    final cats = (categories == null || categories.isEmpty)
        ? _selectedPOIs.toList()
        : categories;

    setState(() {
      _loadingPOIs = true;
      _error = null;
    });

    try {
      final List<GeoPoint> geocodedStops = [];
      for (final controller in _stopControllers) {
        final address = controller.text.trim();
        if (address.isNotEmpty) {
          final resolved = _resolvedStopCoords[controller.hashCode];
          final isMatch = resolved != null &&
              resolved.name != null &&
              (resolved.name!.toLowerCase().contains(address.toLowerCase()) ||
               address.toLowerCase().contains(resolved.name!.toLowerCase()));
          if (resolved != null && isMatch) {
            geocodedStops.add(resolved);
          } else {
            final point = await _api.geocode(address);
            geocodedStops.add(point);
            _resolvedStopCoords[controller.hashCode] = point; // Cache it!
          }
        }
      }

      if (geocodedStops.length < 2) {
        throw Exception("Need at least a starting point and destination");
      }

      final bool round = _tripType == 'roundtrip';
      final start = geocodedStops.first;
      final end = round ? geocodedStops.first : geocodedStops.last;
      final waypoints = round
          ? geocodedStops.sublist(1)
          : geocodedStops.sublist(1, geocodedStops.length - 1);

      final vehicle = Vehicle(
        type: _selectedVehicle!.type,
        efficiencyKmPerLiter: double.parse(_efficiencyController.text),
        tankCapacityLiters: double.parse(_tankController.text),
        currentFuelLiters: double.parse(_currentFuelController.text),
      );

      final tempPlan = await _api.planTrip(
        start: start,
        end: end,
        waypoints: waypoints,
        vehicle: vehicle,
        travellers: _travellers,
      );

      final fetchedPois = await _api.fetchPOIs(
        routeCoordinates: tempPlan.coordinates,
        categories: cats,
      );

      if (mounted) {
        setState(() {
          _pois = fetchedPois;
          _appliedPOIs = cats;
          _hasSearchedPOIs = true;
          // Save as TEMP plan — does NOT switch the right panel to TripScreen
          _tempPlan = tempPlan;
          _tempStart = start;
          _tempEnd = end;
          _tempWaypoints = waypoints;
          _tempVehicle = vehicle;
          _loadingPOIs = false;
        });

        // Center map camera on the route bounds
        if (tempPlan.coordinates.isNotEmpty) {
          final routePoints = tempPlan.coordinates.map((c) => c.toLatLng()).toList();
          final lats = routePoints.map((p) => p.latitude).toList();
          final lngs = routePoints.map((p) => p.longitude).toList();
          final midLat = lats.reduce((a, b) => a + b) / lats.length;
          final midLng = lngs.reduce((a, b) => a + b) / lngs.length;
          final mapCenter = LatLng(midLat, midLng);

          final latSpan = lats.reduce((a, b) => a > b ? a : b) - lats.reduce((a, b) => a < b ? a : b);
          final lngSpan = lngs.reduce((a, b) => a > b ? a : b) - lngs.reduce((a, b) => a < b ? a : b);
          final span = latSpan > lngSpan ? latSpan : lngSpan;
          final mapZoom = span < 0.5 ? 12.0 : span < 2 ? 9.0 : span < 5 ? 7.0 : span < 10 ? 5.5 : 4.5;

          try {
            _mapController.move(mapCenter, mapZoom);
          } catch (e) {
            print("MapController not ready yet: $e");
          }
        }

        // Auto scroll to reveal search results after layout settles
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _formScrollController.hasClients) {
            _formScrollController.animateTo(
              _formScrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to find places: $e';
          _loadingPOIs = false;
        });
      }
    }
  }

  void _confirmAddPOIFromPlanner(PlaceOfInterest place) {
    final newWaypoint = GeoPoint(lat: place.lat, lng: place.lng, name: place.name);

    // Get the currently resolved coordinates in order of the active controllers
    final List<GeoPoint> resolvedNodes = [];
    final List<TextEditingController> activeControllers = [];
    for (final controller in _stopControllers) {
      final coord = _resolvedStopCoords[controller.hashCode];
      if (coord != null && controller.text.trim().isNotEmpty) {
        resolvedNodes.add(coord);
        activeControllers.add(controller);
      }
    }

    if (resolvedNodes.length >= 2) {
      // Find the best insertion index among the resolved nodes
      int bestIndex = 0;
      double minDetour = double.infinity;

      double _dist(GeoPoint p1, GeoPoint p2) {
        final dx = p1.lng - p2.lng;
        final dy = p1.lat - p2.lat;
        return sqrt(dx * dx + dy * dy);
      }

      for (int i = 0; i < resolvedNodes.length - 1; i++) {
        final p1 = resolvedNodes[i];
        final p2 = resolvedNodes[i + 1];
        final detour = _dist(p1, newWaypoint) + _dist(newWaypoint, p2) - _dist(p1, p2);
        if (detour < minDetour) {
          minDetour = detour;
          bestIndex = i;
        }
      }

      // Insert the new controller right after the controller corresponding to resolvedNodes[bestIndex]
      final targetController = activeControllers[bestIndex];
      final insertIndex = _stopControllers.indexOf(targetController) + 1;

      setState(() {
        final newController = TextEditingController(text: place.name);
        _resolvedStopCoords[newController.hashCode] = newWaypoint;
        _stopControllers.insert(insertIndex, newController);
      });

      // Offset the scroll position by 76.0 (approx height of a stop input) so the POI card doesn't jump
      Future.delayed(const Duration(milliseconds: 50), () {
        if (_formScrollController.hasClients) {
          _formScrollController.animateTo(
            _formScrollController.offset + 76.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      });
    } else {
      setState(() {
        final newController = TextEditingController(text: place.name);
        _resolvedStopCoords[newController.hashCode] = newWaypoint;
        _stopControllers.insert(_stopControllers.length - 1, newController);
      });
    }

    // Show confirmation without triggering a form rebuild that causes scroll jump
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✓ Added "${place.name}" as a stop'),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF2E75B6),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _addStop() {
    setState(() {
      _stopControllers.insert(_stopControllers.length - 1, TextEditingController());
    });
  }

  void _removeStop(int index) {
    if (_stopControllers.length <= 2) return;
    setState(() {
      final controller = _stopControllers.removeAt(index);
      _resolvedStopCoords.remove(controller.hashCode);
      controller.dispose();
    });
  }

  Future<Position> _determinePosition() async {
    // On native platforms, verify the location service + permission up front so
    // we can give a specific, actionable error instead of a raw exception.
    if (!kIsWeb) {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'Location services are turned off. Enable them in your device settings and try again.';
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw 'Location permission was denied. Please allow it to use your current location.';
      }
      if (permission == LocationPermission.deniedForever) {
        throw 'Location permission is permanently denied. Enable it for this app in Settings.';
      }
    }

    // Accuracy ladder: prefer a precise fix, then degrade. When the OS/browser
    // location works, high accuracy gives the user's real spot; if it can't
    // resolve (no GPS + service issues), we fall to low, then to the IP guess
    // below. Each attempt is time-boxed so a stuck request doesn't hang the UI.
    for (final accuracy in const [LocationAccuracy.high, LocationAccuracy.low]) {
      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: accuracy,
          timeLimit: const Duration(seconds: 15),
        );
      } catch (_) {
        // try the next (less demanding) accuracy
      }
    }

    // Native only: a cached fix beats nothing (web plugin doesn't support it).
    if (!kIsWeb) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) return last;
      } catch (_) {/* fall through to the friendly error */}
    }

    // Last resort: approximate (city-level) location from the client's IP. This
    // works even when the browser's geolocation backend is blocked/unavailable
    // (VPN, corporate network, or macOS Location Services off for the browser).
    final ipPos = await _ipApproxPosition();
    if (ipPos != null) return ipPos;

    throw "Couldn't get your location. Make sure location is enabled and allowed for this site, then try again — or pick the spot on the map.";
  }

  /// Approximate location from the caller's IP address (city-level). Tries a
  /// couple of free, CORS-enabled providers; returns null if none respond.
  Future<Position?> _ipApproxPosition() async {
    for (final url in const ['https://ipwho.is/', 'https://ipapi.co/json/']) {
      try {
        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) continue;
        final m = jsonDecode(res.body) as Map<String, dynamic>;
        final lat = (m['latitude'] as num?)?.toDouble();
        final lng = (m['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        return Position(
          latitude: lat,
          longitude: lng,
          timestamp: DateTime.now(),
          accuracy: 5000, // ~city-level
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
      } catch (_) {
        // try the next provider
      }
    }
    return null;
  }

  /// Mapbox Search autocomplete for a stop field. Debounced; results show as a
  /// suggestion list under the field.
  void _onStopQueryChanged(int index, String query) {
    _suggestDebounce?.cancel();
    final q = query.trim();
    if (q.length < 3) {
      setState(() {
        _suggestions.remove(index);
        _activeSuggestIndex = null;
      });
      return;
    }
    _suggestDebounce = Timer(const Duration(milliseconds: 320), () async {
      try {
        final uri = Uri.parse(
          'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(q)}.json',
        ).replace(queryParameters: {
          'autocomplete': 'true',
          'limit': '5',
          'country': 'in',
          'language': 'en',
          'access_token': _mapboxToken,
        });
        final res = await http.get(uri).timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) return;
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final feats = (body['features'] as List?) ?? [];
        final list = feats.map((f) {
          final c = (f['center'] as List);
          return {
            'name': f['place_name'] as String? ?? '',
            'lng': (c[0] as num).toDouble(),
            'lat': (c[1] as num).toDouble(),
          };
        }).toList();
        if (!mounted) return;
        setState(() {
          _suggestions[index] = list;
          _activeSuggestIndex = index;
        });
      } catch (_) {/* ignore transient search errors */}
    });
  }

  void _selectSuggestion(int index, Map<String, dynamic> s) {
    final controller = _stopControllers[index];
    final pt = GeoPoint(
      lat: s['lat'] as double,
      lng: s['lng'] as double,
      name: s['name'] as String,
    );
    setState(() {
      controller.text = s['name'] as String;
      _resolvedStopCoords[controller.hashCode] = pt;
      if (index == 0) _startFocusPoint = pt;
      _suggestions.remove(index);
      _activeSuggestIndex = null;
    });
    FocusScope.of(context).unfocus();
  }

  Widget _buildSuggestions(int index) {
    final list = _suggestions[index];
    if (list == null || list.isEmpty || _activeSuggestIndex != index) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4, left: 32),
      decoration: BoxDecoration(
        color: const Color(0xFF13233B).withOpacity(0.96),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        children: [
          for (final s in list)
            InkWell(
              onTap: () => _selectSuggestion(index, s),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                child: Row(
                  children: [
                    const Icon(Icons.place_outlined, color: Color(0xFF60A5FA), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s['name'] as String,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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

  Future<void> _useCurrentLocation(int index) async {
    setState(() => _loadingLocationForIndex[index] = true);
    try {
      final position = await _determinePosition();
      final address = await _api.reverseGeocode(position.latitude, position.longitude);
      
      if (!mounted) return;
      
      final displayName = address ?? '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
      final controller = _stopControllers[index];
      
      setState(() {
        controller.text = displayName;
        final pt = GeoPoint(
          lat: position.latitude,
          lng: position.longitude,
          name: displayName,
        );
        _resolvedStopCoords[controller.hashCode] = pt;
        if (index == 0) _startFocusPoint = pt;
      });

      // A coarse accuracy means we fell back to IP-based lookup (city-level),
      // which is only a rough guess — be honest about it and nudge the user to
      // refine, instead of claiming it's their precise current location.
      final isApprox = position.accuracy >= 3000;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isApprox
              ? '≈ Approximate location ($displayName). Your device wouldn\'t share a precise fix — refine it on the map or type an address.'
              : '✓ Updated to current location: $displayName'),
          backgroundColor: isApprox ? const Color(0xFFB45309) : const Color(0xFF2E75B6),
          duration: Duration(seconds: isApprox ? 6 : 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loadingLocationForIndex[index] = false);
      }
    }
  }

  Future<void> _pickOnMap(int index) async {
    LatLng? initialCenter;
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        initialCenter = LatLng(pos.latitude, pos.longitude);
      }
    } catch (_) {}
    
    final controller = _stopControllers[index];
    final existingPoint = _resolvedStopCoords[controller.hashCode];
    if (existingPoint != null) {
      initialCenter = LatLng(existingPoint.lat, existingPoint.lng);
    }

    if (!mounted) return;

    final GeoPoint? selectedPoint = await Navigator.of(context).push<GeoPoint>(
      MaterialPageRoute(
        builder: (_) => MapLocationPickerScreen(
          initialCenter: initialCenter,
          label: index == 0 ? 'Starting point' : (index == _stopControllers.length - 1 ? 'Destination' : 'Stop $index'),
        ),
      ),
    );

    if (selectedPoint != null && mounted) {
      setState(() {
        controller.text = selectedPoint.name ?? '${selectedPoint.lat.toStringAsFixed(4)}, ${selectedPoint.lng.toStringAsFixed(4)}';
        _resolvedStopCoords[controller.hashCode] = selectedPoint;
        if (index == 0) _startFocusPoint = selectedPoint;
      });
    }
  }

  @override
  void dispose() {
    for (var c in _stopControllers) {
      c.dispose();
    }
    _efficiencyController.dispose();
    _tankController.dispose();
    _currentFuelController.dispose();
    _placeSearchController.dispose();
    _placeSearchDebounce?.cancel();
    _formScrollController.dispose();
    _bgController.dispose();
    _suggestDebounce?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    User? user;
    try {
      user = Supabase.instance.client.auth.currentUser;
    } catch (_) {}
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: isDesktop
          ? null
          : AppBar(
              title: const Text('Trip Planner', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
              flexibleSpace: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.6),
                      Colors.black.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
      drawer: _buildDrawer(user),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 900) {
            // Desktop: full-bleed map with a floating glass control panel.
            return Stack(
              children: [
                // 1. Map fills the entire screen edge-to-edge.
                Positioned.fill(
                  child: _currentPlan == null ? _buildDefaultMap() : _buildTripScreen(),
                ),
                // The planning panel is only shown while planning. Once a trip
                // is active the navigation view takes the whole screen so its
                // own controls aren't overlapped.
                if (_currentPlan == null) ...[
                  // 2. Left-edge scrim so the floating panel stays legible.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.black.withOpacity(0.55),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.42],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 3. Floating glass control panel.
                  Positioned(
                    top: 0,
                    left: 0,
                    bottom: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: SizedBox(
                          width: 430,
                          child: RevealIn(
                            offsetX: -32,
                            offsetY: 0,
                            child: _buildFloatingPanel(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ] else
                  // Active trip: a compact "back to planner" button.
                  Positioned(
                    top: 0,
                    left: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Material(
                          color: Colors.black.withOpacity(0.45),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => setState(() => _currentPlan = null),
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Icon(Icons.arrow_back, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          } else {
            // Mobile: cinematic background with the form centered on top.
            return Stack(
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _bgController,
                    builder: (context, child) {
                      final t = Curves.easeInOut.transform(_bgController.value);
                      return Transform.scale(
                        scale: 1.04 + 0.035 * t,
                        alignment: Alignment(-0.3 + 0.6 * t, -0.2 + 0.4 * t),
                        child: child,
                      );
                    },
                    child: Image.network(_bgUrl, fit: BoxFit.cover),
                  ),
                ),
                Positioned.fill(
                  child: Container(color: Colors.black.withOpacity(0.5)),
                ),
                SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: _buildForm(),
                    ),
                  ),
                ),
              ],
            );
          }
        },
      ),
    );
  }

  /// Desktop floating control panel: a fixed header (menu + title) atop a
  /// scrollable form body, wrapped in the frosted-glass surface.
  Widget _buildFloatingPanel() {
    return _buildGlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Row(
              children: [
                Builder(
                  builder: (context) => InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Scaffold.of(context).openDrawer(),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.15)),
                      ),
                      child: const Icon(Icons.menu, color: Colors.white, size: 22),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Trip Planner',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.1),
                    ),
                    Text(
                      'Plan your perfect road trip',
                      style: TextStyle(
                          fontSize: 13, color: Colors.white.withOpacity(0.6)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(color: Colors.white.withOpacity(0.10), height: 1),
          // Scrollable body
          Expanded(child: _buildForm(embedded: true)),
        ],
      ),
    );
  }

  Widget _buildForm({bool embedded = false}) {
    final isDesktop = MediaQuery.of(context).size.width > 900;
    return SingleChildScrollView(
      controller: _formScrollController,
      padding: EdgeInsets.only(
        left: embedded ? 20.0 : 24.0,
        right: embedded ? 20.0 : 24.0,
        bottom: embedded ? 28.0 : 24.0,
        top: embedded ? 20.0 : (isDesktop ? 24.0 : kToolbarHeight + 24.0),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isDesktop && !embedded) ...[
              Builder(
                builder: (context) => Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.menu, color: Colors.white),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                      tooltip: 'Open Menu',
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Trip Planner',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
            RevealIn(delay: const Duration(milliseconds: 40), child: _buildRouteCard()),
            const SizedBox(height: 24),
            RevealIn(delay: const Duration(milliseconds: 100), child: _buildVehicleCard()),
            const SizedBox(height: 24),
            RevealIn(delay: const Duration(milliseconds: 160), child: _buildPOICard()),
            const SizedBox(height: 32),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red[300]!),
                  ),
                  child: Text(_error!, style: const TextStyle(color: Colors.white)),
                ),
              ),
              
            RevealIn(
              delay: const Duration(milliseconds: 220),
              child: AccentButton(
                onPressed: _loading ? null : _planTrip,
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: _loading
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.auto_awesome_rounded, size: 20),
                          SizedBox(width: 10),
                          Text('Plan my trip', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultMap() {
    // When a temp plan exists (after Find Places), show route preview
    final hasRoute = _tempPlan != null && _tempPlan!.coordinates.isNotEmpty;

    // Web + idle (no route preview yet): show the 3D globe in space. It flies
    // down to the start location once the user picks one.
    if (kIsWeb && !hasRoute) {
      return Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: const Color(0xFF080A18),
        appBar: AppBar(
          title: const Text('Trip Map',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          backgroundColor: Colors.black.withOpacity(0.25),
          elevation: 0,
        ),
        body: GlobePreview(focusPoint: _startFocusPoint),
      );
    }
    final routePoints = hasRoute
        ? _tempPlan!.coordinates.map((c) => c.toLatLng()).toList()
        : <LatLng>[];

    // Compute map center and zoom from route bounding box
    LatLng mapCenter = const LatLng(20.5937, 78.9629);
    double mapZoom = 4.5;
    if (hasRoute && routePoints.length >= 2) {
      final lats = routePoints.map((p) => p.latitude).toList();
      final lngs = routePoints.map((p) => p.longitude).toList();
      final midLat = (lats.reduce((a, b) => a + b)) / lats.length;
      final midLng = (lngs.reduce((a, b) => a + b)) / lngs.length;
      mapCenter = LatLng(midLat, midLng);
      final latSpan = lats.reduce((a, b) => a > b ? a : b) - lats.reduce((a, b) => a < b ? a : b);
      final lngSpan = lngs.reduce((a, b) => a > b ? a : b) - lngs.reduce((a, b) => a < b ? a : b);
      final span = latSpan > lngSpan ? latSpan : lngSpan;
      mapZoom = span < 0.5 ? 12.0 : span < 2 ? 9.0 : span < 5 ? 7.0 : span < 10 ? 5.5 : 4.5;
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(hasRoute ? 'Route Preview' : 'Trip Map',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.black.withOpacity(0.4),
        elevation: 0,
      ),
      body: FlutterMap(
        key: const ValueKey('default_trip_map'),
        mapController: _mapController,
        options: MapOptions(
          initialCenter: mapCenter,
          initialZoom: mapZoom,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.travel_app',
          ),
          if (hasRoute) ...([
            PolylineLayer(
              polylines: [
                Polyline(
                  points: routePoints,
                  strokeWidth: 5.0,
                  color: const Color(0xFF6C63FF),
                  borderStrokeWidth: 2.0,
                  borderColor: Colors.white.withOpacity(0.5),
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: _tempStart != null ? LatLng(_tempStart!.lat, _tempStart!.lng) : routePoints.first,
                  width: 36,
                  height: 36,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF4CAF50),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 6)],
                    ),
                    child: const Icon(Icons.trip_origin, color: Colors.white, size: 20),
                  ),
                ),
                if (_tempWaypoints != null)
                  ..._tempWaypoints!.map((wp) => Marker(
                    point: LatLng(wp.lat, wp.lng),
                    width: 36,
                    height: 36,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFF2E75B6),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 6)],
                      ),
                      child: const Icon(Icons.location_on, color: Colors.white, size: 20),
                    ),
                  )),
                Marker(
                  point: _tempEnd != null ? LatLng(_tempEnd!.lat, _tempEnd!.lng) : routePoints.last,
                  width: 36,
                  height: 36,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFE53935),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 6)],
                    ),
                    child: const Icon(Icons.flag, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ]),
          RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
        ],
      ),
    );
  }

  Widget _buildTripScreen() {
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: TripScreen(
        plan: _currentPlan!,
        startAddress: _stopControllers.first.text.trim(),
        endAddress: _stopControllers.last.text.trim(),
        vehicleType: _selectedVehicle!.type,
        poiCategories: _appliedPOIs,
        start: _currentStart!,
        end: _currentEnd!,
        waypoints: _currentWaypoints!,
        vehicle: _currentVehicle!,
        initialPois: _pois.isNotEmpty ? _pois : null,
        isEmbedded: true,
        modelSubtype: model3DKey(_selectedVehicle!),
        travellers: _travellers,
      ),
    );
  }

  Widget _buildDrawer(User? user) {
    final initials = (_userName != null && _userName!.isNotEmpty) 
        ? _userName!.substring(0, 1).toUpperCase() 
        : (user?.email != null && user!.email!.isNotEmpty)
            ? user.email!.substring(0, 1).toUpperCase()
            : 'T';

    return Drawer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1E293B), // Slate Dark
              Color(0xFF0F172A), // Deep Obsidian
            ],
          ),
        ),
        child: Column(
          children: [
            // Custom Premium Header
            Container(
              padding: const EdgeInsets.only(top: 80, bottom: 32, left: 24, right: 24),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
              ),
              child: Row(
                children: [
                  // Circular Avatar with outer gradient ring
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF2E75B6), Color(0xFF60A5FA)],
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 32,
                      backgroundColor: const Color(0xFF0F172A),
                      child: Text(
                        initials,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _userName ?? 'Traveler',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user?.email ?? 'Not logged in',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Drawer Options
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.white.withOpacity(0.03),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      leading: const Icon(Icons.map_outlined, color: Color(0xFF60A5FA), size: 24),
                      title: const Text(
                        'Saved Trips',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: Colors.white30, size: 20),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedTripsScreen()));
                      },
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // Log Out Button at Bottom
            Padding(
              padding: const EdgeInsets.all(24),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
                  color: Colors.redAccent.withOpacity(0.05),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  leading: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 22),
                  title: const Text(
                    'Log out',
                    style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  onTap: () async {
                    await Supabase.instance.client.auth.signOut();
                    // Return to the landing page (which hosts login) on web.
                    redirectToLanding();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: AppColors.accentGradient,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withOpacity(0.45),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Text(
          title,
          style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ],
    );
  }

  Widget _buildGlassCard({required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(24.0)}) {
    return GlassCard(padding: padding, child: child);
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    Color? iconColor,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    Widget? suffixIcon,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14),
        floatingLabelStyle: const TextStyle(color: Color(0xFF2E75B6), fontWeight: FontWeight.bold),
        prefixIcon: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Icon(icon, color: iconColor ?? Colors.white.withOpacity(0.6), size: 22),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 40),
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF2E75B6), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 2),
        ),
      ),
    );
  }

  Widget _buildRouteCard() {
    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(Icons.route, 'Your Route'),
          const SizedBox(height: 24),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _stopControllers.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex -= 1;
                final item = _stopControllers.removeAt(oldIndex);
                _stopControllers.insert(newIndex, item);
              });
            },
            itemBuilder: (context, index) {
              final isStart = index == 0;
              final isEnd = index == _stopControllers.length - 1;
              String label = isStart ? 'Starting point' : (isEnd ? 'Destination' : 'Stop ${index}');
              IconData icon = isStart ? Icons.trip_origin : (isEnd ? Icons.location_on : Icons.adjust);
              Color iconColor = isStart ? Colors.greenAccent : (isEnd ? Colors.redAccent : Colors.orangeAccent);

              return Container(
                key: ValueKey(_stopControllers[index]),
                margin: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                Row(
                  children: [
                    Icon(Icons.drag_indicator, color: Colors.white.withOpacity(0.5)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildTextField(
                        controller: _stopControllers[index],
                        label: label,
                        icon: icon,
                        iconColor: iconColor,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                        onChanged: (v) => _onStopQueryChanged(index, v),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _loadingLocationForIndex[index] == true
                                ? const Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    ),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.my_location, color: Colors.greenAccent, size: 20),
                                    onPressed: () => _useCurrentLocation(index),
                                    tooltip: 'Use current location',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                            IconButton(
                              icon: const Icon(Icons.map, color: Colors.blueAccent, size: 20),
                              onPressed: () => _pickOnMap(index),
                              tooltip: 'Pick on map',
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!isStart && !isEnd)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                        onPressed: () => _removeStop(index),
                      )
                    else
                      const SizedBox(width: 48), // Padding equivalent to icon button
                  ],
                ),
                _buildSuggestions(index),
                  ],
                ),
              );
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _addStop,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Add Stop'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              if (_stopControllers.length >= 4) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _optimizeRoute,
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                  label: const Text('Optimize'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF60A5FA),
                    side: const BorderSide(color: Color(0xFF60A5FA)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Reorders the intermediate stops for the shortest overall path using a
  /// nearest-neighbour heuristic (start and destination stay fixed). Requires
  /// every stop to have resolved coordinates.
  void _optimizeRoute() {
    if (_stopControllers.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Add at least two stops between start and destination to optimise.')));
      return;
    }
    final startCoord = _resolvedStopCoords[_stopControllers.first.hashCode];
    final middle = _stopControllers.sublist(1, _stopControllers.length - 1);
    if (startCoord == null || middle.any((c) => _resolvedStopCoords[c.hashCode] == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Resolve every stop first (pick from the suggestions), then optimise.')));
      return;
    }

    const distance = Distance();
    final ordered = <TextEditingController>[];
    final remaining = [...middle];
    var current = LatLng(startCoord.lat, startCoord.lng);
    while (remaining.isNotEmpty) {
      remaining.sort((a, b) {
        final ca = _resolvedStopCoords[a.hashCode]!;
        final cb = _resolvedStopCoords[b.hashCode]!;
        return distance(current, LatLng(ca.lat, ca.lng))
            .compareTo(distance(current, LatLng(cb.lat, cb.lng)));
      });
      final next = remaining.removeAt(0);
      ordered.add(next);
      final c = _resolvedStopCoords[next.hashCode]!;
      current = LatLng(c.lat, c.lng);
    }

    setState(() {
      final reordered = [_stopControllers.first, ...ordered, _stopControllers.last];
      _stopControllers
        ..clear()
        ..addAll(reordered);
      _suggestions.clear();
      _activeSuggestIndex = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Stops reordered for the shortest path ✓')));
  }

  Widget _buildVehicleCard() {
    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(Icons.directions_car, 'Vehicle Details'),
          const SizedBox(height: 24),
          DropdownButtonFormField<VehicleModel>(
            value: _selectedVehicle,
            isExpanded: true,
            dropdownColor: const Color(0xFF1A1A1A),
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              labelText: 'Select Vehicle',
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
              filled: true,
              fillColor: Colors.black.withOpacity(0.2),
              prefixIcon: Icon(Icons.commute, color: Colors.white.withOpacity(0.7)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withOpacity(0.2))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.white)),
            ),
            items: predefinedVehicles.map((v) {
              return DropdownMenuItem(
                value: v,
                child: Text(v.name),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedVehicle = value;
                _updateVehicleFields();
              });
            },
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _specField(
                  controller: _efficiencyController,
                  label: 'Efficiency',
                  unit: 'km/l',
                  icon: Icons.speed_rounded,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _specField(
                  controller: _tankController,
                  label: 'Tank',
                  unit: 'L',
                  icon: Icons.local_gas_station_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _specField(
            controller: _currentFuelController,
            label: 'Current fuel in tank',
            unit: 'L',
            icon: Icons.water_drop_rounded,
            validator: _currentFuelValidator,
          ),
          const SizedBox(height: 18),
          _buildTravellersRow(),
        ],
      ),
    );
  }

  /// Compact numeric field for vehicle specs. The label sits ABOVE the field
  /// (as a caption) so it can never be clipped or truncated the way a floating
  /// InputDecoration label is in a narrow column; the unit shows as a suffix.
  Widget _specField({
    required TextEditingController controller,
    required String label,
    required String unit,
    required IconData icon,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: Colors.white.withOpacity(0.55)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: validator ?? _numberValidator,
          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            suffixText: unit,
            suffixStyle: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 13, fontWeight: FontWeight.w600),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF2E75B6), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.redAccent, width: 2),
            ),
            errorStyle: const TextStyle(fontSize: 11, height: 0.9),
          ),
        ),
      ],
    );
  }

  Widget _buildTravellersRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.groups, color: Colors.white.withOpacity(0.7)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Travellers',
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
                const SizedBox(height: 2),
                Text('For the trip budget estimate',
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
              ],
            ),
          ),
          _stepBtn(Icons.remove, _travellers > 1
              ? () => setState(() => _travellers--)
              : null),
          Container(
            width: 34,
            alignment: Alignment.center,
            child: Text('$_travellers',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          _stepBtn(Icons.add, _travellers < 12
              ? () => setState(() => _travellers++)
              : null),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap) {
    return Material(
      color: onTap == null ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 20, color: onTap == null ? Colors.white24 : Colors.white),
        ),
      ),
    );
  }

  String? _numberValidator(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final n = double.tryParse(v);
    if (n == null || n <= 0) return 'Enter a valid number';
    return null;
  }

  /// Current fuel must be a valid number and not exceed the tank capacity.
  String? _currentFuelValidator(String? v) {
    final base = _numberValidator(v);
    if (base != null) return base;
    final fuel = double.parse(v!);
    final tank = double.tryParse(_tankController.text);
    if (tank != null && fuel > tank) return 'Max ${_formatNum(tank)} L';
    return null;
  }

  final List<Map<String, dynamic>> _poiOptions = [
    {'id': 'fuel', 'label': 'Fuel Stations', 'icon': Icons.local_gas_station},
    {'id': 'charging', 'label': 'EV Charging', 'icon': Icons.ev_station},
    {'id': 'hotel', 'label': 'Hotels', 'icon': Icons.hotel},
    {'id': 'restaurant', 'label': 'Restaurants', 'icon': Icons.restaurant},
    {'id': 'attraction', 'label': 'Attractions', 'icon': Icons.photo_camera},
    {'id': 'hills', 'label': 'Hills', 'icon': Icons.landscape},
    {'id': 'temple', 'label': 'Temples', 'icon': Icons.account_balance},
    {'id': 'lake', 'label': 'Lakes', 'icon': Icons.water},
    {'id': 'river', 'label': 'Rivers', 'icon': Icons.waves},
    {'id': 'viewpoint', 'label': 'Viewpoints', 'icon': Icons.visibility},
  ];

  /// Manual search: geocode a typed place name and add it to the route as a stop.
  Future<void> _addManualPlace() async {
    final q = _placeSearchController.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _searchingPlace = true);
    try {
      final pt = await _api.geocode(q);
      final place = PlaceOfInterest(
        id: DateTime.now().millisecondsSinceEpoch,
        name: pt.name ?? q,
        lat: pt.lat,
        lng: pt.lng,
        address: pt.name,
      );
      _confirmAddPOIFromPlanner(place); // inserts as a stop on the route
      _placeSearchController.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Couldn\'t find "$q". Try a more specific name.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _searchingPlace = false);
    }
  }

  /// Recommends popular sightseeing stops near the route (attractions, viewpoints,
  /// temples, hills, lakes) by reusing the route + POI pipeline.
  Future<void> _suggestPopularStops() async {
    setState(() => _suggestingPopular = true);
    try {
      await _findPlacesBeforeTrip(
        categories: const ['attraction', 'viewpoint', 'temple', 'hills', 'lake', 'river'],
      );
    } finally {
      if (mounted) setState(() => _suggestingPopular = false);
    }
  }

  /// Live autocomplete for the place-search box (reuses the Mapbox geocoder).
  void _onPlaceSearchChanged(String query) {
    _placeSearchDebounce?.cancel();
    final q = query.trim();
    if (q.length < 3) {
      setState(() => _placeSuggestions = []);
      return;
    }
    _placeSearchDebounce = Timer(const Duration(milliseconds: 320), () async {
      try {
        final uri = Uri.parse(
          'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(q)}.json',
        ).replace(queryParameters: {
          'autocomplete': 'true',
          'limit': '6',
          'country': 'in',
          'language': 'en',
          'access_token': _mapboxToken,
        });
        final res = await http.get(uri).timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) return;
        final feats = ((jsonDecode(res.body) as Map<String, dynamic>)['features'] as List?) ?? [];
        final list = feats.map((f) {
          final c = f['center'] as List;
          return {
            'name': f['place_name'] as String? ?? '',
            'lng': (c[0] as num).toDouble(),
            'lat': (c[1] as num).toDouble(),
          };
        }).toList();
        if (mounted) setState(() => _placeSuggestions = list);
      } catch (_) {/* ignore transient search errors */}
    });
  }

  void _selectPlaceSuggestion(Map<String, dynamic> s) {
    final place = PlaceOfInterest(
      id: DateTime.now().millisecondsSinceEpoch,
      name: s['name'] as String,
      lat: s['lat'] as double,
      lng: s['lng'] as double,
      address: s['name'] as String,
    );
    _confirmAddPOIFromPlanner(place);
    setState(() => _placeSuggestions = []);
    _placeSearchController.clear();
    FocusScope.of(context).unfocus();
  }

  /// Geocodes an AI-suggested place name and adds it to the route.
  Future<bool> _addAiPlace(String name, String area) async {
    final query = area.isNotEmpty ? '$name, $area' : name;
    try {
      final pt = await _api.geocode(query);
      _confirmAddPOIFromPlanner(PlaceOfInterest(
        id: DateTime.now().millisecondsSinceEpoch,
        name: name,
        lat: pt.lat,
        lng: pt.lng,
        address: pt.name,
      ));
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Couldn\'t locate "$name" on the map.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
      return false;
    }
  }

  /// AI Assistant sheet — Gemini-powered stop recommendations, natural-language
  /// place search, and a trip assistant / itinerary writer.
  void _showAiAssistant() {
    final searchCtl = TextEditingController();
    final askCtl = TextEditingController();
    final start = _stopControllers.first.text.trim();
    final end = _stopControllers.last.text.trim();
    int tab = 0; // 0 = Discover, 1 = Ask
    bool busy = false;
    String? error;
    List<Map<String, String>> places = [];
    final Set<String> added = {};
    String answer = '';

    const accent = Color(0xFF60A5FA);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF13233B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            Future<void> run(Future<void> Function() fn) async {
              setSheet(() { busy = true; error = null; });
              try {
                await fn();
              } catch (e) {
                error = e.toString().replaceFirst('ApiException: ', '');
              } finally {
                if (context.mounted) setSheet(() => busy = false);
              }
            }

            Widget seg(String label, IconData icon, int i) => Expanded(
                  child: GestureDetector(
                    onTap: () => setSheet(() => tab = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: tab == i ? accent : Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(icon, size: 16, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                      ]),
                    ),
                  ),
                );

            Widget placeCard(Map<String, String> p) {
              final key = '${p['name']}|${p['area']}';
              final isAdded = added.contains(key);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p['name'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                          if ((p['area'] ?? '').isNotEmpty)
                            Text(p['area']!, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                          if ((p['why'] ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(p['why']!, style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12.5)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    isAdded
                        ? const Icon(Icons.check_circle, color: Colors.greenAccent, size: 26)
                        : IconButton(
                            icon: const Icon(Icons.add_circle, color: accent),
                            tooltip: 'Add to route',
                            onPressed: () async {
                              final ok = await _addAiPlace(p['name'] ?? '', p['area'] ?? '');
                              if (ok) setSheet(() => added.add(key));
                            },
                          ),
                  ],
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.only(left: 18, right: 18, top: 14, bottom: 14 + MediaQuery.of(sheetCtx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 14),
                  Row(children: [
                    const Icon(Icons.auto_awesome, color: accent, size: 20),
                    const SizedBox(width: 8),
                    const Text('AI Assistant', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    const Text('Gemini', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [seg('Discover places', Icons.explore, 0), const SizedBox(width: 8), seg('Ask', Icons.chat_bubble_outline, 1)]),
                  const SizedBox(height: 16),

                  if (tab == 0) ...[
                    ElevatedButton.icon(
                      onPressed: (busy || start.isEmpty || end.isEmpty)
                          ? null
                          : () => run(() async {
                                places = await _api.aiRecommendStops(start: start, end: end);
                              }),
                      icon: const Icon(Icons.route, size: 18),
                      label: Text(start.isEmpty || end.isEmpty ? 'Enter start & destination first' : 'Recommend stops on my route'),
                      style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)),
                    ),
                    const SizedBox(height: 10),
                    _aiInputRow(searchCtl, 'e.g. waterfalls near Chikmagalur', busy, () {
                      final q = searchCtl.text.trim();
                      if (q.isEmpty) return;
                      run(() async {
                        places = await _api.aiSearchPlaces(query: q, near: start.isNotEmpty ? start : null);
                      });
                    }),
                  ] else ...[
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      _aiChip('Plan my itinerary', busy, () => run(() async {
                            answer = await _api.aiAsk(
                              question: 'Write a day-by-day itinerary for this road trip.',
                              context: {'from': start, 'to': end, 'vehicle': _selectedVehicle?.name, 'travellers': _travellers},
                            );
                          })),
                      _aiChip('Best time to leave?', busy, () => run(() async {
                            answer = await _api.aiAsk(question: 'What is the best time to start this drive and why?', context: {'from': start, 'to': end});
                          })),
                    ]),
                    const SizedBox(height: 10),
                    _aiInputRow(askCtl, 'Ask anything about your trip…', busy, () {
                      final q = askCtl.text.trim();
                      if (q.isEmpty) return;
                      run(() async {
                        answer = await _api.aiAsk(question: q, context: {'from': start, 'to': end, 'vehicle': _selectedVehicle?.name, 'travellers': _travellers});
                      });
                    }),
                  ],

                  const SizedBox(height: 14),
                  if (busy)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator(color: accent)))
                  else if (error != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.red.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                      child: Text(error!, style: const TextStyle(color: Color(0xFFFFB4A8), fontSize: 13)),
                    )
                  else
                    Flexible(
                      child: SingleChildScrollView(
                        child: tab == 0
                            ? Column(children: places.map(placeCard).toList())
                            : (answer.isEmpty
                                ? Text('Ask a question or tap a suggestion above.', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13))
                                : SelectableText(answer, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5))),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      searchCtl.dispose();
      askCtl.dispose();
    });
  }

  Widget _aiInputRow(TextEditingController ctl, String hint, bool busy, VoidCallback onSend) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(children: [
        const SizedBox(width: 14),
        Expanded(
          child: TextField(
            controller: ctl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: hint,
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 13),
            ),
          ),
        ),
        IconButton(icon: const Icon(Icons.send, color: Color(0xFF60A5FA)), onPressed: busy ? null : onSend),
      ]),
    );
  }

  Widget _aiChip(String label, bool busy, VoidCallback onTap) {
    return ActionChip(
      label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
      backgroundColor: Colors.white.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white.withOpacity(0.15))),
      onPressed: busy ? null : onTap,
    );
  }

  Widget _buildPlaceSearchField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(Icons.search, color: Colors.white.withOpacity(0.6), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _placeSearchController,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  textInputAction: TextInputAction.search,
                  onChanged: _onPlaceSearchChanged,
                  onSubmitted: (_) => _addManualPlace(),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Search a place to add…',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
                  ),
                ),
              ),
              _searchingPlace
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                    )
                  : IconButton(
                      icon: const Icon(Icons.add_circle, color: Color(0xFF2E75B6)),
                      tooltip: 'Add this place',
                      onPressed: _addManualPlace,
                    ),
            ],
          ),
        ),
        if (_placeSuggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF13233B).withOpacity(0.96),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: Column(
              children: [
                for (final s in _placeSuggestions)
                  InkWell(
                    onTap: () => _selectPlaceSuggestion(s),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      child: Row(
                        children: [
                          const Icon(Icons.place_outlined, color: Color(0xFF60A5FA), size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              s['name'] as String,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.add, color: Colors.white38, size: 18),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPOICard() {
    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(Icons.place, 'Places to Visit'),
          const SizedBox(height: 20),
          // Manual search — type any place name and add it to the route.
          _buildPlaceSearchField(),
          const SizedBox(height: 20),
          Text('Or pick categories to find along your route',
              style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12.5)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12.0,
            runSpacing: 12.0,
            children: _poiOptions.map((option) {
              final isSelected = _selectedPOIs.contains(option['id']);
              return FilterChip(
                label: Text(option['label']),
                avatar: Icon(option['icon'], size: 18, color: isSelected ? Colors.white : Colors.white70),
                selected: isSelected,
                selectedColor: const Color(0xFF2E75B6),
                checkmarkColor: Colors.white,
                backgroundColor: Colors.black.withOpacity(0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: isSelected ? const Color(0xFF2E75B6) : Colors.white.withOpacity(0.2)),
                ),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedPOIs.add(option['id']);
                    } else {
                      _selectedPOIs.remove(option['id']);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _loadingPOIs ? null : () => _findPlacesBeforeTrip(),
                  icon: (_loadingPOIs && !_suggestingPopular)
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.search, size: 20),
                  label: Text((_loadingPOIs && !_suggestingPopular) ? 'Searching…' : 'Find Places'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E75B6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loadingPOIs ? null : _suggestPopularStops,
                  icon: _suggestingPopular
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.auto_awesome, size: 20),
                  label: Text(_suggestingPopular ? 'Finding…' : 'Popular stops'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withOpacity(0.35)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showAiAssistant,
              icon: const Icon(Icons.auto_awesome, size: 18, color: Color(0xFF60A5FA)),
              label: const Text('AI Assistant', style: TextStyle(color: Color(0xFF60A5FA))),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF60A5FA)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          // Itinerary is only meaningful for round trips; hide it for one-way trips.
          if (_tripType == 'roundtrip') ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _planAndOpenItinerary,
                icon: _loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8F81F2)))
                    : const Icon(Icons.event_note_rounded, size: 18, color: Color(0xFF8F81F2)),
                label: const Text('Itinerary', style: TextStyle(color: Color(0xFF8F81F2))),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF8F81F2)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
          if (_hasSearchedPOIs) ...[
            const SizedBox(height: 24),
            if (_loadingPOIs && _pois.isEmpty)
              const Center(child: CircularProgressIndicator())
            else if (_pois.values.any((l) => l.isNotEmpty))
              Stack(
                alignment: Alignment.center,
                children: [
                  _buildPOIList(),
                  if (_loadingPOIs)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withOpacity(0.5),
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.white.withOpacity(0.6), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No places found near this route for those categories. Try different categories, or search a place by name above.',
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildPOIList() {
    final allPois = <MapEntry<String, PlaceOfInterest>>[];
    _pois.forEach((category, places) {
      for (final p in places) {
        allPois.add(MapEntry(category, p));
      }
    });

    if (allPois.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: ListView.builder(
        key: const PageStorageKey('poi_list_scroll_key'),
        shrinkWrap: true,
        padding: const EdgeInsets.all(8),
        itemCount: allPois.length,
        itemBuilder: (context, index) {
          final poi = allPois[index];
          final category = poi.key;
          final place = poi.value;
          final option = _poiOptions.firstWhere((o) => o['id'] == category, orElse: () => _poiOptions.first);

          final cleanName = place.name.toLowerCase().startsWith('unnamed')
              ? (category == 'fuel'
                  ? 'Petrol Bunk'
                  : category == 'hotel'
                      ? 'Hotel / Stay'
                      : category == 'restaurant'
                          ? 'Restaurant / Cafe'
                          : category == 'attraction'
                              ? 'Tourist Attraction'
                              : category == 'temple'
                                  ? 'Temple / Worship'
                                  : category == 'viewpoint'
                                      ? 'Scenic Viewpoint'
                                      : '${category[0].toUpperCase()}${category.substring(1)}')
              : place.name;

          return ListTile(
            leading: Icon(option['icon'], color: Colors.white70),
            title: Text(cleanName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                );
              },
            ),
            trailing: IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Color(0xFF2E75B6)),
              onPressed: () => _confirmAddPOIFromPlanner(place),
            ),
          );
        },
      ),
    );
  }
}
