import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/trip_models.dart';
import '../models/vehicles_data.dart';
import '../services/api_service.dart';
import '../services/vehicle_database_service.dart';
import '../theme/app_theme.dart';
import '../utils/trip_date_time.dart';
import '../utils/trip_type_utils.dart';
import '../widgets/vehicle_search_sheet.dart';
import 'trip_screen.dart';

/// UNIFIED TRIP BUILDER
/// Replaces separate TripPlannerScreen and SmartItineraryScreen with a single,
/// robust 6-step workflow that shares one authoritative trip engine.
class UnifiedTripBuilderScreen extends StatefulWidget {
  final String initialTripType;
  final String? initialOrigin;
  final String? initialDestination;
  final int? initialDays;
  final String? initialVibe;
  final VehicleModel? initialVehicle;

  const UnifiedTripBuilderScreen({
    super.key,
    this.initialTripType = 'one_way',
    this.initialOrigin,
    this.initialDestination,
    this.initialDays,
    this.initialVibe,
    this.initialVehicle,
  });

  @override
  State<UnifiedTripBuilderScreen> createState() =>
      _UnifiedTripBuilderScreenState();
}

class _UnifiedTripBuilderScreenState extends State<UnifiedTripBuilderScreen>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  int _currentStep = 1; // 1 to 6

  // ── Step 1: Route Controllers ───────────────────────────────────────────
  final TextEditingController _originCtrl = TextEditingController();
  final TextEditingController _destCtrl = TextEditingController();
  final List<TextEditingController> _viaControllers = [];
  final List<GeoPoint?> _viaCoords = [];
  GeoPoint? _originCoord;
  GeoPoint? _destCoord;
  bool _locatingGPS = false;
  Timer? _acDebounce;
  List<Map<String, dynamic>> _originSuggestions = [];
  List<Map<String, dynamic>> _destSuggestions = [];
  int? _activeViaSuggestIndex;
  List<Map<String, dynamic>> _viaSuggestions = [];

  // Recent / popular shortcuts
  final List<String> _popularDestinations = const [
    'Goa',
    'Coorg',
    'Ooty',
    'Mysuru',
    'Manali',
    'Pondicherry',
    'Munnar',
    'Jaipur',
    'Rishikesh'
  ];

  // ── Step 2: Trip Type ───────────────────────────────────────────────────
  // Options: 'one_way', 'round_trip', 'multi_dest', 'vacation'
  late String _tripType = widget.initialTripType;

  // ── Step 3: Date & Duration ─────────────────────────────────────────────
  DateTime _startDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 0);
  int _days = 2;
  int _travellers = 2;

  // ── Step 4: Vehicle ─────────────────────────────────────────────────────
  String _transportMode = 'car'; // 'car', 'bike', 'ev', 'other'
  String _evConnectorType = 'CCS2'; // 'CCS2', 'Type 2', 'GB/T'
  VehicleModel? _selectedVehicle;
  final TextEditingController _vehicleNameCtrl =
      TextEditingController(text: 'Compact Sedan');
  final TextEditingController _fuelTypeCtrl =
      TextEditingController(text: 'petrol');
  final TextEditingController _tankCapacityCtrl =
      TextEditingController(text: '45');
  final TextEditingController _currentFuelCtrl =
      TextEditingController(text: '30');
  final TextEditingController _mileageCtrl = TextEditingController(text: '15');
  final TextEditingController _fuelPriceCtrl =
      TextEditingController(text: '102');
  String _luggageLoad = 'medium'; // 'light', 'medium', 'heavy'

  // ── Step 5: Travel Style ────────────────────────────────────────────────
  final Set<String> _selectedStyles = {'Balanced', 'Scenic'};
  static const List<String> _availableStyles = [
    'Fastest',
    'Balanced',
    'Scenic',
    'Relaxed',
    'Adventure',
    'Family',
    'Food',
    'Nature',
    'Photography',
    'Spiritual',
    'Trekking'
  ];

  // ── Step 6: AI Generation & Validation State ────────────────────────────
  bool _isGenerating = false;
  String? _validationError;
  int _generationStage =
      0; // 0: Route, 1: Destination, 2: Attractions, 3: Optimize, 4: Fuel, 5: Budget
  Timer? _stageTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialOrigin != null && widget.initialOrigin!.isNotEmpty) {
      _originCtrl.text = widget.initialOrigin!;
    }
    if (widget.initialDestination != null &&
        widget.initialDestination!.isNotEmpty) {
      _destCtrl.text = widget.initialDestination!;
    }
    if (widget.initialDays != null && widget.initialDays! > 0) {
      _days = widget.initialDays!;
    }
    if (widget.initialVibe != null && widget.initialVibe!.isNotEmpty) {
      _selectedStyles.add(widget.initialVibe!);
    }
    _initSavedVehicle();
  }

  Future<void> _initSavedVehicle() async {
    try {
      await VehicleDatabaseService.instance.init();
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString('voyplan_last_active_vehicle_id');
      if (savedId != null && savedId.isNotEmpty) {
        final settings =
            VehicleDatabaseService.instance.getVehicleSettings(savedId);
        if (settings != null) {
          setState(() {
            _fuelTypeCtrl.text = settings.fuelType;
            _currentFuelCtrl.text = settings.currentFuel.toStringAsFixed(1);
            _mileageCtrl.text = settings.mileage.toStringAsFixed(1);
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _acDebounce?.cancel();
    _stageTimer?.cancel();
    _originCtrl.dispose();
    _destCtrl.dispose();
    for (final c in _viaControllers) {
      c.dispose();
    }
    _vehicleNameCtrl.dispose();
    _fuelTypeCtrl.dispose();
    _tankCapacityCtrl.dispose();
    _currentFuelCtrl.dispose();
    _mileageCtrl.dispose();
    _fuelPriceCtrl.dispose();
    super.dispose();
  }

  // ── Route Autocomplete & GPS ────────────────────────────────────────────
  void _onSearchChanged(String query, String type, {int? viaIndex}) {
    _acDebounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        if (type == 'origin') _originSuggestions = [];
        if (type == 'dest') _destSuggestions = [];
        if (type == 'via') _viaSuggestions = [];
      });
      return;
    }
    _acDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final list = await _api.autocompletePlaces(query);
        if (!mounted) return;
        setState(() {
          if (type == 'origin') _originSuggestions = list;
          if (type == 'dest') _destSuggestions = list;
          if (type == 'via') {
            _activeViaSuggestIndex = viaIndex;
            _viaSuggestions = list;
          }
        });
      } catch (_) {}
    });
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locatingGPS = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enable location services.')),
          );
        }
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      _originCoord = GeoPoint(
          lat: pos.latitude, lng: pos.longitude, name: 'Current Location');
      _originCtrl.text =
          'My Current Location (${pos.latitude.toStringAsFixed(3)}, ${pos.longitude.toStringAsFixed(3)})';
      setState(() => _originSuggestions = []);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not fetch location: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _locatingGPS = false);
    }
  }

  void _addDestinationStop() {
    setState(() {
      _viaControllers.add(TextEditingController());
      _viaCoords.add(null);
    });
  }

  void _removeDestinationStop(int index) {
    setState(() {
      _viaControllers[index].dispose();
      _viaControllers.removeAt(index);
      _viaCoords.removeAt(index);
    });
  }

  // ── Vehicle Selector & Validation ───────────────────────────────────────
  void _openVehicleSearch() async {
    final vehicle = await VehicleSearchSheet.show(context,
        currentVehicle: _selectedVehicle);
    if (vehicle != null) {
      final isEv = vehicle.fuelType.toLowerCase() == 'ev' ||
          vehicle.batteryCapacityKwh != null;
      setState(() {
        _selectedVehicle = vehicle;
        _vehicleNameCtrl.text = vehicle.name;
        _fuelTypeCtrl.text = vehicle.fuelType.isEmpty
            ? (isEv ? 'ev' : 'petrol')
            : vehicle.fuelType;
        if (isEv) {
          _transportMode = 'ev';
          final batt = vehicle.batteryCapacityKwh ??
              (vehicle.tankCapacity > 0 ? vehicle.tankCapacity : 45.0);
          _tankCapacityCtrl.text = batt.toStringAsFixed(1);
          final eff = (vehicle.evRangeKm != null &&
                  vehicle.batteryCapacityKwh != null &&
                  vehicle.batteryCapacityKwh! > 0)
              ? (vehicle.evRangeKm! / vehicle.batteryCapacityKwh!)
              : (vehicle.mileage > 0 ? vehicle.mileage : 6.8);
          _mileageCtrl.text = eff.toStringAsFixed(1);
          _currentFuelCtrl.text = '85'; // 85% charge default
          _fuelPriceCtrl.text = '18'; // ₹18/kWh
        } else {
          _transportMode =
              vehicle.type.contains('bike') || vehicle.type.contains('motor')
                  ? 'bike'
                  : 'car';
          _tankCapacityCtrl.text = vehicle.tankCapacity.toStringAsFixed(1);
          _mileageCtrl.text = vehicle.mileage.toStringAsFixed(1);
          _fuelPriceCtrl.text = vehicle.fuelType == 'diesel' ? '92' : '102';
        }
      });
      _persistActiveVehicle(vehicle);
    }
  }

  Future<void> _persistActiveVehicle(VehicleModel vehicle) async {
    try {
      final mileage =
          double.tryParse(_mileageCtrl.text.trim()) ?? vehicle.mileage;
      final currentFuel = double.tryParse(_currentFuelCtrl.text.trim()) ?? 20.0;
      await VehicleDatabaseService.instance.saveVehicleSettings(
        vehicleId: vehicle.id,
        currentFuel: currentFuel,
        mileage: mileage > 0 ? mileage : 15.0,
        fuelType: vehicle.fuelType.isEmpty ? 'petrol' : vehicle.fuelType,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('voyplan_last_active_vehicle_id', vehicle.id);
    } catch (_) {}
  }

  // ── Step 6: Validation & AI Planning Engine ──────────────────────────────
  bool _validateInputs() {
    setState(() => _validationError = null);

    final origin = _originCtrl.text.trim();
    if (origin.isEmpty) {
      setState(() => _validationError =
          'Please specify a starting location or use current GPS.');
      _currentStep = 1;
      return false;
    }

    final dest = _destCtrl.text.trim();
    if (dest.isEmpty) {
      setState(
          () => _validationError = 'Please specify your primary destination.');
      _currentStep = 1;
      return false;
    }

    // Step 3 Validation
    if (_days < 1) {
      setState(
          () => _validationError = 'Trip duration must be at least 1 day.');
      _currentStep = 3;
      return false;
    }
    if (_travellers < 1) {
      setState(
          () => _validationError = 'Number of travellers must be at least 1.');
      _currentStep = 3;
      return false;
    }

    // Step 4 Vehicle Validation (PART 16)
    final mileage = double.tryParse(_mileageCtrl.text.trim());
    if (mileage == null || mileage <= 0) {
      setState(() => _validationError =
          'Vehicle mileage must be a positive number greater than 0 km/L.');
      _currentStep = 4;
      return false;
    }

    final tank = double.tryParse(_tankCapacityCtrl.text.trim());
    if (tank == null || tank <= 0) {
      setState(() =>
          _validationError = 'Tank capacity must be greater than 0 Liters.');
      _currentStep = 4;
      return false;
    }

    final currentFuel = double.tryParse(_currentFuelCtrl.text.trim());
    if (currentFuel == null || currentFuel < 0 || currentFuel > tank) {
      setState(() => _validationError =
          'Current fuel must be between 0 and full tank capacity ($tank L).');
      _currentStep = 4;
      return false;
    }

    return true;
  }

  Future<void> _generateTrip() async {
    if (!_validateInputs()) return;

    setState(() {
      _isGenerating = true;
      _generationStage = 0;
    });

    // Animate generation stages smoothly (PART 19: AI progress streaming)
    _stageTimer?.cancel();
    _stageTimer = Timer.periodic(const Duration(milliseconds: 1600), (timer) {
      if (mounted && _generationStage < 5) {
        setState(() => _generationStage++);
      }
    });

    try {
      final origin = _originCtrl.text.trim();
      final dest = _destCtrl.text.trim();
      final mileage = double.tryParse(_mileageCtrl.text.trim()) ?? 15.0;
      final tank = double.tryParse(_tankCapacityCtrl.text.trim()) ?? 45.0;
      final currentFuel = double.tryParse(_currentFuelCtrl.text.trim()) ?? 30.0;

      final waypointsList = <String>[];
      for (final c in _viaControllers) {
        if (c.text.trim().isNotEmpty) waypointsList.add(c.text.trim());
      }

      final mappedTripType = TripTypes.normalize(_tripType);
      final mode = _selectedStyles.contains('Relaxed')
          ? 'relaxed'
          : (_selectedStyles.contains('Fastest') ? 'packed' : 'balanced');

      // Call Authoritative AI & Routing Backend
      final res = await _api.aiSmartItinerary(
        destination: dest,
        startLocation: origin,
        tripType: mappedTripType,
        places: waypointsList,
        startDate:
            '${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}',
        startTime: TripDateTime.to24Hour(_startTime.hour, _startTime.minute),
        durationDays: _days,
        mode: mode,
        preferences: _selectedStyles.join(', '),
        travellers: _travellers,
        vehicleType: _transportMode == 'bike' ? 'bike' : 'car',
        fuelEfficiency: mileage,
        currentFuel: currentFuel,
        tankCapacity: tank,
      );

      _stageTimer?.cancel();

      if (!mounted) return;

      // Extract coordinates from itinerary or geocode fallback
      GeoPoint startPt =
          _originCoord ?? GeoPoint(lat: 12.9716, lng: 77.5946, name: origin);
      GeoPoint endPt =
          _destCoord ?? GeoPoint(lat: 13.6288, lng: 79.4192, name: dest);
      final List<GeoPoint> plannedWaypoints = [];

      for (final d in res.days) {
        for (final b in d.blocks) {
          if (b.lat != null &&
              b.lng != null &&
              (b.lat != 0.0 || b.lng != 0.0)) {
            if (b.type != 'start' && b.type != 'return' && !b.isDestination) {
              plannedWaypoints.add(GeoPoint(
                lat: b.lat!,
                lng: b.lng!,
                name: b.title.isNotEmpty ? b.title : b.place,
              ));
            }
          }
        }
      }

      final vehicle = Vehicle(
        type: _transportMode == 'bike' ? 'motorcycle' : 'car',
        efficiencyKmPerLiter: mileage,
        tankCapacityLiters: tank,
        currentFuelLiters: currentFuel,
        fuelType: _transportMode == 'ev' ? 'ev' : _fuelTypeCtrl.text.trim(),
      );

      final totalKm = res.route?.distanceKm ?? res.totalDistanceKm ?? 150.0;
      final fuelCost = (res.budget?.fuel ?? 1200).toDouble();
      final tollCost = (res.budget?.tolls ?? 150).toDouble();

      final authoritativePlan = res.tripPlan ??
          TripPlan.fromJson({
            'distanceKm': totalKm,
            'distanceMeters': (totalKm * 1000).round(),
            'durationMin': _days * 480,
            'durationSeconds': _days * 480 * 60,
            'coordinates': (res.route?.coordinates ?? [startPt, endPt])
                .map((p) => p.toJson())
                .toList(),
            'estimatedDays': _days,
            'fuel': {
              'estimatedCost': fuelCost,
              'requiredLiters': totalKm / mileage,
              'needsRefuel': false,
              'totalDistanceKm': totalKm,
              'refuelStops': <Map<String, dynamic>>[],
            },
            'fuelEstimate': {
              'requiredLiters': totalKm / mileage,
              'estimatedFuelCost': fuelCost,
              'fuelType': vehicle.fuelType,
              'refuelStopsCount': 0,
              'totalCost': fuelCost,
              'vehicleEfficiency': mileage,
            },
            'toll': {
              'hasTolls': tollCost > 0,
              'fastagTollCost': tollCost,
              'totalTollCost': tollCost,
              'currency': 'INR',
            },
            'budget': res.budget?.toJson() ??
                {
                  'fuel': fuelCost,
                  'tolls': tollCost,
                  'food': 0,
                  'stay': 0,
                  'activities': 0,
                  'total': fuelCost + tollCost,
                },
            'places': <String, dynamic>{},
            'navigationWaypoints':
                plannedWaypoints.map((w) => w.toJson()).toList(),
          });

      final savedItinerary = <Map<String, dynamic>>[];
      for (final d in res.days) {
        for (final b in d.blocks) {
          savedItinerary.add(b.toJson());
        }
      }

      final tripStart = DateTime(
        _startDate.year,
        _startDate.month,
        _startDate.day,
        _startTime.hour,
        _startTime.minute,
      );

      // Transition to Authoritative Trip Screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => TripScreen(
            plan: authoritativePlan,
            startAddress: origin,
            endAddress: dest,
            vehicleType: vehicle.type,
            poiCategories: const [
              'restaurant',
              'attraction',
              'hotel',
              'fuel',
              'ev',
              'viewpoint'
            ],
            start: startPt,
            end: endPt,
            waypoints: plannedWaypoints,
            vehicle: vehicle,
            travellers: _travellers,
            initialTripStart: tripStart,
            savedItinerary: savedItinerary,
          ),
        ),
      );
    } catch (e) {
      _stageTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _validationError =
            'Trip generation error: ${e.toString().replaceAll('ApiException: ', '')}';
      });
    }
  }

  // ── Build Method ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060B14),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth > 900;
            if (isDesktop) {
              return Row(
                children: [
                  Expanded(
                    flex: 65,
                    child: _buildMainWorkspace(),
                  ),
                  Container(width: 1, color: const Color(0xFF242C38)),
                  Expanded(
                    flex: 35,
                    child: _buildRightSummaryPanel(),
                  ),
                ],
              );
            } else {
              return Stack(
                children: [
                  Column(
                    children: [
                      _buildMobileHeader(),
                      _buildStepIndicator(),
                      if (_validationError != null) _errorBanner(),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16)
                              .copyWith(bottom: 120),
                          physics: const BouncingScrollPhysics(),
                          child: _buildCurrentStepContent(),
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _buildMobileBottomSticky(),
                  ),
                  if (_isGenerating) _generationOverlay(),
                ],
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildMainWorkspace() {
    return Stack(
      children: [
        Column(
          children: [
            _buildDesktopHeader(),
            _buildStepIndicator(),
            if (_validationError != null) _errorBanner(),
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 24)
                        .copyWith(bottom: 120),
                physics: const BouncingScrollPhysics(),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: _buildCurrentStepContent(),
                  ),
                ),
              ),
            ),
          ],
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildDesktopBottomSticky(),
        ),
        if (_isGenerating) _generationOverlay(),
      ],
    );
  }

  // ── Headers ─────────────────────────────────────────────────────────────
  Widget _buildMobileHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Plan your trip',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                Text('Smart routes, fuel, stops & AI itinerary',
                    style: TextStyle(
                        color: Voy.brand,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 16),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Plan your trip',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800)),
              SizedBox(height: 4),
              Text('Smart routes, fuel, stops & AI itinerary',
                  style: TextStyle(
                      color: Voy.brand,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Step Indicator ──────────────────────────────────────────────────────
  Widget _buildStepIndicator() {
    final titles = ['Route', 'Vehicle & Fuel', 'Stops & Budget', 'Review'];
    // Map internal _currentStep (1-6) to UI steps (1-4)
    int uiStep = 1;
    if (_currentStep <= 2)
      uiStep = 1; // Route & Dates & Type -> Route
    else if (_currentStep <= 4)
      uiStep = 2; // Vehicle -> Vehicle
    else if (_currentStep == 5)
      uiStep = 3; // Style -> Stops & Budget
    else
      uiStep = 4; // Review -> Review

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      child: Row(
        children: List.generate(titles.length, (i) {
          final stepNum = i + 1;
          final isActive = uiStep == stepNum;
          final isCompleted = uiStep > stepNum;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                // Allow going back, but validate going forward
                if (stepNum < uiStep) {
                  setState(() {
                    if (stepNum == 1) _currentStep = 1;
                    if (stepNum == 2) _currentStep = 4;
                    if (stepNum == 3) _currentStep = 5;
                    if (stepNum == 4) _currentStep = 6;
                  });
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 2,
                          color: i == 0
                              ? Colors.transparent
                              : (isCompleted || isActive
                                  ? Voy.brand
                                  : const Color(0xFF242C38)),
                        ),
                      ),
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCompleted
                              ? Voy.brand
                              : (isActive
                                  ? Voy.brand
                                  : const Color(0xFF101B2B)),
                          border: Border.all(
                              color: isActive || isCompleted
                                  ? Voy.brand
                                  : const Color(0xFF242C38)),
                        ),
                        child: Center(
                          child: isCompleted
                              ? const Icon(Icons.check,
                                  size: 14, color: Color(0xFF04211F))
                              : Text(
                                  '$stepNum',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isActive
                                        ? const Color(0xFF04211F)
                                        : const Color(0xFF8B97A7),
                                  ),
                                ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 2,
                          color: i == titles.length - 1
                              ? Colors.transparent
                              : (isCompleted
                                  ? Voy.brand
                                  : const Color(0xFF242C38)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    titles[i],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive ? Colors.white : const Color(0xFF8B97A7),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _errorBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Colors.redAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _validationError!,
              style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
            onPressed: () => setState(() => _validationError = null),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // ── Routing ──────────────────────────────────────────────────────────────
  Widget _buildCurrentStepContent() {
    if (_currentStep <= 2) {
      return _buildUiStep1Route();
    } else if (_currentStep <= 4) {
      return _buildUiStep2Vehicle();
    } else if (_currentStep == 5) {
      return _buildUiStep3Stops();
    } else {
      return _buildUiStep4Review();
    }
  }

  // ── UI STEP 1: ROUTE & TYPE & DATE ──────────────────────────────────────
  Widget _buildUiStep1Route() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top 2 cards for Trip Type (Strictly One Way and Vacation)
        Row(
          children: [
            Expanded(
                child: _tripTypeCard('one_way', 'ONE WAY',
                    'Direct route & stops corridor', Icons.trending_flat_rounded)),
            const SizedBox(width: 14),
            Expanded(
                child: _tripTypeCard('vacation', 'VACATION',
                    'Multi-day itinerary & stay', Icons.beach_access_rounded)),
          ],
        ),
        const SizedBox(height: 32),

        const Text('Route & Destination',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Where are you going?',
            style: TextStyle(color: Voy.brand, fontSize: 14)),
        const SizedBox(height: 16),

        _premiumCard(
          child: Column(
            children: [
              _locationField('FROM', _originCtrl, 'origin',
                  Icons.my_location_rounded, _originSuggestions,
                  isOrigin: true),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(child: Divider(color: Color(0xFF242C38))),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Icon(Icons.swap_vert_rounded,
                          color: Color(0xFF8B97A7), size: 20),
                    ),
                    Expanded(child: Divider(color: Color(0xFF242C38))),
                  ],
                ),
              ),
              _locationField('TO', _destCtrl, 'dest', Icons.place_rounded,
                  _destSuggestions),
            ],
          ),
        ),

        if (_tripType == 'multi_dest' || _tripType == 'vacation') ...[
          const SizedBox(height: 16),
          ...List.generate(_viaControllers.length, (idx) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _premiumCard(
                child: _locationField(
                    'STOP ${idx + 1}',
                    _viaControllers[idx],
                    'via',
                    Icons.add_location_alt_rounded,
                    _activeViaSuggestIndex == idx ? _viaSuggestions : [],
                    viaIndex: idx,
                    onRemove: () => _removeDestinationStop(idx)),
              ),
            );
          }),
          TextButton.icon(
            onPressed: _addDestinationStop,
            icon:
                const Icon(Icons.add_circle_outline_rounded, color: Voy.brand),
            label: const Text('Add Stop',
                style:
                    TextStyle(color: Voy.brand, fontWeight: FontWeight.w700)),
          ),
        ],

        const SizedBox(height: 32),
        const Text('Travelers & Dates',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        _premiumCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TRAVELERS',
                        style: TextStyle(
                            color: Color(0xFF8B97A7),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1)),
                    const SizedBox(height: 8),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _travellers,
                        dropdownColor: const Color(0xFF161B22),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600),
                        isExpanded: true,
                        items: List.generate(
                            20,
                            (i) => DropdownMenuItem(
                                value: i + 1,
                                child: Text(
                                    '${i + 1} Traveler${i == 0 ? '' : 's'}'))),
                        onChanged: (v) => setState(() => _travellers = v ?? 1),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                  width: 1,
                  height: 50,
                  color: const Color(0xFF242C38),
                  margin: const EdgeInsets.symmetric(horizontal: 16)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        _tripType == 'vacation'
                            ? 'START DATE'
                            : 'TRAVEL DATE',
                        style: const TextStyle(
                            color: Color(0xFF8B97A7),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1)),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _startDate,
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) setState(() => _startDate = picked);
                      },
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded,
                              color: Voy.brand, size: 18),
                          const SizedBox(width: 8),
                          Text(
                              '${_startDate.day} ${_getMonth(_startDate.month)} ${_startDate.year}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        if (_tripType == 'vacation') ...[
          const SizedBox(height: 12),
          _premiumCard(
            child: Row(
              children: [
                const Text('TRIP DURATION',
                    style: TextStyle(
                        color: Color(0xFF8B97A7),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.remove, color: Colors.white),
                    onPressed:
                        _days > 1 ? () => setState(() => _days--) : null),
                Text('$_days Days',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                IconButton(
                    icon: const Icon(Icons.add, color: Colors.white),
                    onPressed:
                        _days < 30 ? () => setState(() => _days++) : null),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _tripTypeCard(String id, String title, String desc, IconData icon) {
    final isSelected = _tripType == id;
    return InkWell(
      onTap: () => setState(() => _tripType = id),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? Voy.brand.withValues(alpha: 0.1)
              : const Color(0xFF0D1624),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isSelected ? Voy.brand : const Color(0xFF242C38),
              width: isSelected ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon,
                    color: isSelected ? Voy.brand : const Color(0xFF8B97A7),
                    size: 28),
                if (isSelected)
                  const Icon(Icons.check_circle_rounded,
                      color: Voy.brand, size: 20),
              ],
            ),
            const SizedBox(height: 16),
            Text(title,
                style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF8B97A7),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5)),
            const SizedBox(height: 4),
            Text(desc,
                style: const TextStyle(
                    color: Color(0xFF8B97A7), fontSize: 11, height: 1.4)),
          ],
        ),
      ),
    );
  }

  Widget _locationField(String label, TextEditingController ctrl, String type,
      IconData icon, List<Map<String, dynamic>> suggestions,
      {bool isOrigin = false, int? viaIndex, VoidCallback? onRemove}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF8B97A7),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
            const Spacer(),
            if (isOrigin)
              InkWell(
                onTap: _locatingGPS ? null : _useCurrentLocation,
                child: Row(
                  children: [
                    _locatingGPS
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Voy.brand))
                        : const Icon(Icons.my_location_rounded,
                            color: Voy.brand, size: 14),
                    const SizedBox(width: 4),
                    const Text('Use Current Location',
                        style: TextStyle(
                            color: Voy.brand,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            if (onRemove != null)
              InkWell(
                onTap: onRemove,
                child: const Icon(Icons.close_rounded,
                    color: Colors.redAccent, size: 16),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'Search city, place or landmark',
            hintStyle: const TextStyle(
                color: Color(0xFF4A5568),
                fontSize: 16,
                fontWeight: FontWeight.w400),
            prefixIcon: Icon(icon, color: const Color(0xFF8B97A7), size: 22),
            suffixIcon:
                const Icon(Icons.map_rounded, color: Voy.brand, size: 20),
            filled: true,
            fillColor: Colors.transparent,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
          onChanged: (val) => _onSearchChanged(val, type, viaIndex: viaIndex),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF242C38)),
            ),
            child: Column(
              children: suggestions
                  .take(4)
                  .map((s) => ListTile(
                        leading: const Icon(Icons.location_on_outlined,
                            color: Voy.brand, size: 20),
                        title: Text(s['place_name'] ?? s['name'] ?? '',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13)),
                        onTap: () {
                          setState(() {
                            ctrl.text = s['place_name'] ?? s['name'] ?? '';
                            if (s['center'] != null) {
                              final pt = GeoPoint(
                                  lat: s['center'][1],
                                  lng: s['center'][0],
                                  name: ctrl.text);
                              if (type == 'origin')
                                _originCoord = pt;
                              else if (type == 'dest')
                                _destCoord = pt;
                              else if (viaIndex != null)
                                _viaCoords[viaIndex] = pt;
                            }
                            if (type == 'origin')
                              _originSuggestions = [];
                            else if (type == 'dest')
                              _destSuggestions = [];
                            else if (type == 'via') _viaSuggestions = [];
                          });
                        },
                      ))
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }

  // ── UI STEP 2: VEHICLE & FUEL ───────────────────────────────────────────
  Widget _buildUiStep2Vehicle() {
    final mileage = double.tryParse(_mileageCtrl.text) ?? 15.0;
    final tank = double.tryParse(_tankCapacityCtrl.text) ?? 45.0;
    final currentFuel = double.tryParse(_currentFuelCtrl.text) ?? 20.0;
    final range = (currentFuel * mileage).toStringAsFixed(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Vehicle & Fuel',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('How are you travelling?',
            style: TextStyle(color: Voy.brand, fontSize: 14)),
        const SizedBox(height: 16),
        _premiumCard(
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                        _transportMode == 'bike'
                            ? Icons.motorcycle_rounded
                            : Icons.directions_car_rounded,
                        color: Voy.brand,
                        size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            _vehicleNameCtrl.text.isEmpty
                                ? 'Select Vehicle'
                                : _vehicleNameCtrl.text,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                            '${_fuelTypeCtrl.text.toUpperCase()} • ${tank}L Tank • ${mileage}km/L',
                            style: const TextStyle(
                                color: Color(0xFF8B97A7), fontSize: 12)),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _openVehicleSearch,
                    child: const Text('Change',
                        style: TextStyle(
                            color: Voy.brand, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(color: Color(0xFF242C38)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('CURRENT FUEL',
                      style: TextStyle(
                          color: Color(0xFF8B97A7),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1)),
                  Text(
                      '${currentFuel.toStringAsFixed(1)} L / ${tank.toStringAsFixed(1)} L',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 16),
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: Voy.brand,
                  inactiveTrackColor: const Color(0xFF242C38),
                  thumbColor: Colors.white,
                  overlayColor: Voy.brand.withValues(alpha: 0.2),
                  trackHeight: 6,
                ),
                child: Slider(
                  value: currentFuel,
                  min: 0,
                  max: tank,
                  onChanged: (val) => setState(
                      () => _currentFuelCtrl.text = val.toStringAsFixed(1)),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Voy.brand.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Voy.brand.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.route_rounded, color: Voy.brand, size: 24),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ESTIMATED RANGE',
                            style: TextStyle(
                                color: Voy.brand,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                        Text('$range km',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── UI STEP 3: STOPS & BUDGET ───────────────────────────────────────────
  Widget _buildUiStep3Stops() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Smart Route Preferences',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Let AI optimize your journey',
            style: TextStyle(color: Voy.brand, fontSize: 14)),
        const SizedBox(height: 16),
        _smartToggleCard('FASTEST ROUTE', 'Best time & distance', 'Fastest',
            Icons.speed_rounded),
        const SizedBox(height: 12),
        _smartToggleCard('SCENIC ROUTE', 'More scenic views', 'Scenic',
            Icons.landscape_rounded),
        const SizedBox(height: 12),
        _smartToggleCard('RELAXED PACE', 'More stops, less driving fatigue',
            'Relaxed', Icons.coffee_rounded),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF22C7C0), Color(0xFF8F81F2)]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome_rounded,
                      color: Colors.white, size: 28),
                  SizedBox(width: 12),
                  Text('AI Trip Optimization',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                  'Get the best route, fuel stops, toll estimates and a personalized itinerary with AI.',
                  style: TextStyle(
                      color: Colors.white, fontSize: 14, height: 1.4)),
              const SizedBox(height: 20),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12)),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text('Smart fuel stops included',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _smartToggleCard(
      String title, String desc, String styleKey, IconData icon) {
    final isSelected = _selectedStyles.contains(styleKey);
    return InkWell(
      onTap: () {
        setState(() {
          if (isSelected)
            _selectedStyles.remove(styleKey);
          else
            _selectedStyles.add(styleKey);
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? Voy.brand.withValues(alpha: 0.1)
              : const Color(0xFF0D1624),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isSelected ? Voy.brand : const Color(0xFF242C38),
              width: isSelected ? 2 : 1),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: isSelected ? Voy.brand : const Color(0xFF8B97A7),
                size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF8B97A7),
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(desc,
                      style: const TextStyle(
                          color: Color(0xFF8B97A7), fontSize: 12)),
                ],
              ),
            ),
            Switch(
              value: isSelected,
              onChanged: (val) {
                setState(() {
                  if (val)
                    _selectedStyles.add(styleKey);
                  else
                    _selectedStyles.remove(styleKey);
                });
              },
              activeColor: Voy.brand,
            ),
          ],
        ),
      ),
    );
  }

  // ── UI STEP 4: REVIEW ───────────────────────────────────────────────────
  Widget _buildUiStep4Review() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Review your journey',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        _premiumCard(
          child: Column(
            children: [
              _reviewRow('ROUTE',
                  '${_originCtrl.text.split(',').first} → ${_destCtrl.text.split(',').first}'),
              const Divider(color: Color(0xFF242C38)),
              _reviewRow(
                  'TRIP TYPE', _tripType.replaceAll('_', ' ').toUpperCase()),
              const Divider(color: Color(0xFF242C38)),
              _reviewRow('TRAVELERS', '$_travellers'),
              const Divider(color: Color(0xFF242C38)),
              _reviewRow('DATE',
                  '${_startDate.day} ${_getMonth(_startDate.month)} ${_startDate.year}'),
              const Divider(color: Color(0xFF242C38)),
              _reviewRow('VEHICLE', _vehicleNameCtrl.text),
              const Divider(color: Color(0xFF242C38)),
              _reviewRow('AI ITINERARY', 'Enabled', valueColor: Voy.brand),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text('RECOMMENDED FIRST STOP',
            style: TextStyle(
                color: Color(0xFF8B97A7),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF242C38)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Voy.brand.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.local_gas_station_rounded, color: Voy.brand),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hassan Fuel Station',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    SizedBox(height: 4),
                    Text('~120 km from Start • ₹102.86/L',
                        style: TextStyle(
                            color: Color(0xFF8B97A7), fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  color: Color(0xFF8B97A7), size: 16),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _generateTrip,
          style: ElevatedButton.styleFrom(
            backgroundColor: Voy.brand,
            foregroundColor: const Color(0xFF04211F),
            padding: const EdgeInsets.symmetric(vertical: 20),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Create Trip & Start Planning →',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ],
    );
  }

  // ── Right Panel (Desktop) ───────────────────────────────────────────────
  Widget _buildRightSummaryPanel() {
    return Container(
      color: const Color(0xFF0D1624),
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Trip Summary',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),

          // Map Placeholder
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF242C38)),
              image: const DecorationImage(
                image: AssetImage(
                    'assets/images/map_placeholder.png'), // Assume we have a placeholder or use a real map widget here later
                fit: BoxFit.cover,
                opacity: 0.3,
              ),
            ),
            child: const Center(
              child: Text('Map View\n(Calculating...)',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Color(0xFF8B97A7), fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(child: _metricCard('DISTANCE', '--- km')),
              const SizedBox(width: 12),
              Expanded(child: _metricCard('DRIVE TIME', '--h --m')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _metricCard('EST. FUEL', '₹---')),
              const SizedBox(width: 12),
              Expanded(child: _metricCard('TOLLS', '₹---')),
            ],
          ),
          
          const SizedBox(height: 24),
          const Text('RECOMMENDED FIRST STOP',
              style: TextStyle(
                  color: Color(0xFF8B97A7),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF242C38)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Voy.brand.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.local_gas_station_rounded, color: Voy.brand),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hassan Fuel Station',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      SizedBox(height: 4),
                      Text('~120 km from Start • ₹102.86/L',
                          style: TextStyle(
                              color: Color(0xFF8B97A7), fontSize: 13)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded,
                    color: Color(0xFF8B97A7), size: 16),
              ],
            ),
          ),

          const Spacer(),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Voy.violet.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Voy.violet.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: Voy.violet, size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('AI will optimize your trip',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                      SizedBox(height: 4),
                      Text(
                          '✓ Best route  ✓ Smart fuel stops\n✓ Toll estimates  ✓ Itinerary',
                          style: TextStyle(
                              color: Color(0xFF8B97A7), fontSize: 12)),
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

  Widget _metricCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF242C38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF8B97A7),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // ── Bottom Stickies ─────────────────────────────────────────────────────
  Widget _buildMobileBottomSticky() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1624),
        border: const Border(top: BorderSide(color: Color(0xFF242C38))),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, -5))
        ],
      ),
      child: Row(
        children: [
          if (_currentStep > 2)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () {
                  setState(() {
                    if (_currentStep == 4)
                      _currentStep = 1; // From Vehicle to Route
                    else if (_currentStep == 5)
                      _currentStep = 4; // From Stops to Vehicle
                    else if (_currentStep == 6)
                      _currentStep = 5; // From Review to Stops
                  });
                },
                style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF161B22)),
              ),
            ),
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                if (_currentStep <= 2) {
                  if (_originCtrl.text.trim().isEmpty ||
                      _destCtrl.text.trim().isEmpty) {
                    setState(() => _validationError =
                        'Please specify both origin and destination.');
                    return;
                  }
                  setState(() {
                    _validationError = null;
                    _currentStep = 4;
                  });
                } else if (_currentStep <= 4) {
                  setState(() {
                    _validationError = null;
                    _currentStep = 5;
                  });
                } else if (_currentStep == 5) {
                  setState(() {
                    _validationError = null;
                    _currentStep = 6;
                  });
                } else {
                  _generateTrip();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Voy.brand,
                foregroundColor: const Color(0xFF04211F),
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_currentStep == 6 ? 'Generate Trip' : 'Continue',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopBottomSticky() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF060B14),
        border: Border(top: BorderSide(color: Color(0xFF242C38))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_currentStep > 2)
            TextButton(
              onPressed: () {
                setState(() {
                  if (_currentStep == 4)
                    _currentStep = 1;
                  else if (_currentStep == 5)
                    _currentStep = 4;
                  else if (_currentStep == 6) _currentStep = 5;
                });
              },
              child: const Text('← Back',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
          const SizedBox(width: 24),
          ElevatedButton(
            onPressed: () {
              if (_currentStep <= 2) {
                if (_originCtrl.text.trim().isEmpty ||
                    _destCtrl.text.trim().isEmpty) {
                  setState(() => _validationError =
                      'Please specify both origin and destination.');
                  return;
                }
                setState(() {
                  _validationError = null;
                  _currentStep = 4;
                });
              } else if (_currentStep <= 4) {
                setState(() {
                  _validationError = null;
                  _currentStep = 5;
                });
              } else if (_currentStep == 5) {
                setState(() {
                  _validationError = null;
                  _currentStep = 6;
                });
              } else {
                _generateTrip();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Voy.brand,
              foregroundColor: const Color(0xFF04211F),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_currentStep == 6 ? 'Generate Trip' : 'Continue →',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────
  Widget _premiumCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1624),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF242C38)),
      ),
      child: child,
    );
  }

  String _getMonth(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return months[month - 1];
  }

  // ── Progress Overlay ──────────────────────────────────────────
  Widget _generationOverlay() {
    final stages = [
      'Route calculated',
      'Destination analysed',
      'Attractions found',
      'Optimizing itinerary',
      'Fuel safety planning',
      'Budget calculation',
    ];

    return Container(
      color: Colors.black.withValues(alpha: 0.75),
      child: Center(
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 44, height: 44, child: CircularProgressIndicator(color: Voy.brand, strokeWidth: 3)),
              const SizedBox(height: 18),
              const Text('Crafting Your Perfect Trip', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              ...List.generate(stages.length, (idx) {
                final isPassed = _generationStage > idx;
                final isCurrent = _generationStage == idx;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        isPassed ? Icons.check_circle_rounded : (isCurrent ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded),
                        size: 16,
                        color: isPassed ? Colors.green : (isCurrent ? Voy.brand : const Color(0xFF8B97A7).withValues(alpha: 0.5)),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        stages[idx],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                          color: isPassed ? Colors.white : (isCurrent ? Voy.brand : const Color(0xFF8B97A7)),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reviewRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: Color(0xFF8B97A7), fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: valueColor ?? Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

}
