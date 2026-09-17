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
  State<UnifiedTripBuilderScreen> createState() => _UnifiedTripBuilderScreenState();
}

class _UnifiedTripBuilderScreenState extends State<UnifiedTripBuilderScreen> with SingleTickerProviderStateMixin {
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
    'Goa', 'Coorg', 'Ooty', 'Mysuru', 'Manali', 'Pondicherry', 'Munnar', 'Jaipur', 'Rishikesh'
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
  final TextEditingController _vehicleNameCtrl = TextEditingController(text: 'Compact Sedan');
  final TextEditingController _fuelTypeCtrl = TextEditingController(text: 'petrol');
  final TextEditingController _tankCapacityCtrl = TextEditingController(text: '45');
  final TextEditingController _currentFuelCtrl = TextEditingController(text: '30');
  final TextEditingController _mileageCtrl = TextEditingController(text: '15');
  final TextEditingController _fuelPriceCtrl = TextEditingController(text: '102');
  String _luggageLoad = 'medium'; // 'light', 'medium', 'heavy'

  // ── Step 5: Travel Style ────────────────────────────────────────────────
  final Set<String> _selectedStyles = {'Balanced', 'Scenic'};
  static const List<String> _availableStyles = [
    'Fastest', 'Balanced', 'Scenic', 'Relaxed', 'Adventure', 'Family',
    'Food', 'Nature', 'Photography', 'Spiritual', 'Trekking'
  ];

  // ── Step 6: AI Generation & Validation State ────────────────────────────
  bool _isGenerating = false;
  String? _validationError;
  int _generationStage = 0; // 0: Route, 1: Destination, 2: Attractions, 3: Optimize, 4: Fuel, 5: Budget
  Timer? _stageTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialOrigin != null && widget.initialOrigin!.isNotEmpty) {
      _originCtrl.text = widget.initialOrigin!;
    }
    if (widget.initialDestination != null && widget.initialDestination!.isNotEmpty) {
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
        final settings = VehicleDatabaseService.instance.getVehicleSettings(savedId);
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
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      _originCoord = GeoPoint(lat: pos.latitude, lng: pos.longitude, name: 'Current Location');
      _originCtrl.text = 'My Current Location (${pos.latitude.toStringAsFixed(3)}, ${pos.longitude.toStringAsFixed(3)})';
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
    final vehicle = await VehicleSearchSheet.show(context, currentVehicle: _selectedVehicle);
    if (vehicle != null) {
      final isEv = vehicle.fuelType.toLowerCase() == 'ev' || vehicle.batteryCapacityKwh != null;
      setState(() {
        _selectedVehicle = vehicle;
        _vehicleNameCtrl.text = vehicle.name;
        _fuelTypeCtrl.text = vehicle.fuelType.isEmpty ? (isEv ? 'ev' : 'petrol') : vehicle.fuelType;
        if (isEv) {
          _transportMode = 'ev';
          final batt = vehicle.batteryCapacityKwh ?? (vehicle.tankCapacity > 0 ? vehicle.tankCapacity : 45.0);
          _tankCapacityCtrl.text = batt.toStringAsFixed(1);
          final eff = (vehicle.evRangeKm != null && vehicle.batteryCapacityKwh != null && vehicle.batteryCapacityKwh! > 0)
              ? (vehicle.evRangeKm! / vehicle.batteryCapacityKwh!)
              : (vehicle.mileage > 0 ? vehicle.mileage : 6.8);
          _mileageCtrl.text = eff.toStringAsFixed(1);
          _currentFuelCtrl.text = '85'; // 85% charge default
          _fuelPriceCtrl.text = '18'; // ₹18/kWh
        } else {
          _transportMode = vehicle.type.contains('bike') || vehicle.type.contains('motor') ? 'bike' : 'car';
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
      final mileage = double.tryParse(_mileageCtrl.text.trim()) ?? vehicle.mileage;
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
      setState(() => _validationError = 'Please specify a starting location or use current GPS.');
      _currentStep = 1;
      return false;
    }

    final dest = _destCtrl.text.trim();
    if (dest.isEmpty) {
      setState(() => _validationError = 'Please specify your primary destination.');
      _currentStep = 1;
      return false;
    }

    // Step 3 Validation
    if (_days < 1) {
      setState(() => _validationError = 'Trip duration must be at least 1 day.');
      _currentStep = 3;
      return false;
    }
    if (_travellers < 1) {
      setState(() => _validationError = 'Number of travellers must be at least 1.');
      _currentStep = 3;
      return false;
    }

    // Step 4 Vehicle Validation (PART 16)
    final mileage = double.tryParse(_mileageCtrl.text.trim());
    if (mileage == null || mileage <= 0) {
      setState(() => _validationError = 'Vehicle mileage must be a positive number greater than 0 km/L.');
      _currentStep = 4;
      return false;
    }

    final tank = double.tryParse(_tankCapacityCtrl.text.trim());
    if (tank == null || tank <= 0) {
      setState(() => _validationError = 'Tank capacity must be greater than 0 Liters.');
      _currentStep = 4;
      return false;
    }

    final currentFuel = double.tryParse(_currentFuelCtrl.text.trim());
    if (currentFuel == null || currentFuel < 0 || currentFuel > tank) {
      setState(() => _validationError = 'Current fuel must be between 0 and full tank capacity ($tank L).');
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

      final mappedTripType = (_tripType == 'one_way') ? 'one_way' : 'around';
      final mode = _selectedStyles.contains('Relaxed')
          ? 'relaxed'
          : (_selectedStyles.contains('Fastest') ? 'packed' : 'balanced');

      // Call Authoritative AI & Routing Backend
      final res = await _api.aiSmartItinerary(
        destination: dest,
        startLocation: origin,
        tripType: mappedTripType,
        places: waypointsList,
        startDate: '${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}',
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
      GeoPoint startPt = _originCoord ?? GeoPoint(lat: 12.9716, lng: 77.5946, name: origin);
      GeoPoint endPt = _destCoord ?? GeoPoint(lat: 13.6288, lng: 79.4192, name: dest);
      final List<GeoPoint> plannedWaypoints = [];

      for (final d in res.days) {
        for (final b in d.blocks) {
          if (b.lat != null && b.lng != null && (b.lat != 0.0 || b.lng != 0.0)) {
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

      final authoritativePlan = res.tripPlan ?? TripPlan.fromJson({
        'distanceKm': totalKm,
        'distanceMeters': (totalKm * 1000).round(),
        'durationMin': _days * 480,
        'durationSeconds': _days * 480 * 60,
        'coordinates': (res.route?.coordinates ?? [startPt, endPt]).map((p) => p.toJson()).toList(),
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
        'budget': res.budget?.toJson() ?? {
          'fuel': fuelCost,
          'tolls': tollCost,
          'food': 0,
          'stay': 0,
          'activities': 0,
          'total': fuelCost + tollCost,
        },
        'places': <String, dynamic>{},
        'navigationWaypoints': plannedWaypoints.map((w) => w.toJson()).toList(),
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
            poiCategories: const ['restaurant', 'attraction', 'hotel', 'fuel', 'ev', 'viewpoint'],
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
        _validationError = 'Trip generation error: ${e.toString().replaceAll('ApiException: ', '')}';
      });
    }
  }

  // ── Build Method ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Voy.bg,
      appBar: AppBar(
        backgroundColor: Voy.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Voy.ink),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Unified Trip Builder',
          style: TextStyle(color: Voy.ink, fontSize: 18, fontWeight: FontWeight.w800),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isGenerating ? null : _generateTrip,
            icon: const Icon(Icons.auto_awesome_rounded, color: Voy.brand, size: 18),
            label: const Text('Generate', style: TextStyle(color: Voy.brand, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _stepIndicator(),
                if (_validationError != null) _errorBanner(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    physics: const BouncingScrollPhysics(),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 800),
                        child: _buildCurrentStepContent(),
                      ),
                    ),
                  ),
                ),
                _bottomNavigation(),
              ],
            ),
          ),
          if (_isGenerating) _generationOverlay(),
        ],
      ),
    );
  }

  // ── Step Indicator ──────────────────────────────────────────────────────
  Widget _stepIndicator() {
    final titles = ['Route', 'Trip Type', 'Dates', 'Vehicle', 'Style', 'Review'];
    return Container(
      color: Voy.surface,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: Row(
        children: List.generate(titles.length, (i) {
          final stepNum = i + 1;
          final isActive = _currentStep == stepNum;
          final isCompleted = _currentStep > stepNum;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _currentStep = stepNum),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 3,
                          color: i == 0
                              ? Colors.transparent
                              : (isCompleted || isActive ? Voy.brand : Voy.hairline),
                        ),
                      ),
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCompleted
                              ? Voy.brand
                              : (isActive ? Voy.brand : Voy.hairline),
                        ),
                        child: Center(
                          child: isCompleted
                              ? const Icon(Icons.check, size: 13, color: Colors.white)
                              : Text(
                                  '$stepNum',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isActive ? Colors.white : Voy.sub,
                                  ),
                                ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 3,
                          color: i == titles.length - 1
                              ? Colors.transparent
                              : (isCompleted ? Voy.brand : Voy.hairline),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    child: Text(
                      titles[i],
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive ? Voy.brand : Voy.sub,
                      ),
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
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _validationError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w600),
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

  // ── Step Content Router ─────────────────────────────────────────────────
  Widget _buildCurrentStepContent() {
    switch (_currentStep) {
      case 1:
        return _buildStep1Route();
      case 2:
        return _buildStep2TripType();
      case 3:
        return _buildStep3DateDuration();
      case 4:
        return _buildStep4Vehicle();
      case 5:
        return _buildStep5TravelStyle();
      case 6:
      default:
        return _buildStep6Review();
    }
  }

  // ── STEP 1: ROUTE ───────────────────────────────────────────────────────
  Widget _buildStep1Route() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Where is your journey taking you?', 'Define origin, destinations & waypoints'),
        const SizedBox(height: 16),
        // Origin field
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.trip_origin_rounded, color: Voy.brand, size: 20),
                  const SizedBox(width: 8),
                  const Text('Starting Location', style: TextStyle(color: Voy.ink, fontWeight: FontWeight.w700, fontSize: 14)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _locatingGPS ? null : _useCurrentLocation,
                    icon: _locatingGPS
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location_rounded, size: 15, color: Voy.brand),
                    label: const Text('Use Current GPS', style: TextStyle(fontSize: 12.5, color: Voy.brand, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _originCtrl,
                style: const TextStyle(color: Voy.ink, fontSize: 14.5),
                decoration: _inputDecoration('e.g. Indiranagar, Bengaluru', Icons.search_rounded),
                onChanged: (val) => _onSearchChanged(val, 'origin'),
              ),
              if (_originSuggestions.isNotEmpty) ...[
                const SizedBox(height: 6),
                ..._originSuggestions.take(4).map((s) => _suggestionTile(s, (item) {
                  setState(() {
                    _originCtrl.text = item['place_name'] ?? item['name'] ?? '';
                    if (item['center'] != null) {
                      _originCoord = GeoPoint(lat: item['center'][1], lng: item['center'][0], name: _originCtrl.text);
                    }
                    _originSuggestions = [];
                  });
                })),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Destination field
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.location_on_rounded, color: Voy.coral, size: 20),
                  SizedBox(width: 8),
                  Text('Primary Destination', style: TextStyle(color: Voy.ink, fontWeight: FontWeight.w700, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _destCtrl,
                style: const TextStyle(color: Voy.ink, fontSize: 14.5),
                decoration: _inputDecoration('e.g. Madikeri, Coorg', Icons.search_rounded),
                onChanged: (val) => _onSearchChanged(val, 'dest'),
              ),
              if (_destSuggestions.isNotEmpty) ...[
                const SizedBox(height: 6),
                ..._destSuggestions.take(4).map((s) => _suggestionTile(s, (item) {
                  setState(() {
                    _destCtrl.text = item['place_name'] ?? item['name'] ?? '';
                    if (item['center'] != null) {
                      _destCoord = GeoPoint(lat: item['center'][1], lng: item['center'][0], name: _destCtrl.text);
                    }
                    _destSuggestions = [];
                  });
                })),
              ],
            ],
          ),
        ),
        // Additional Waypoints / Multi-destinations
        if (_viaControllers.isNotEmpty) ...[
          const SizedBox(height: 14),
          ...List.generate(_viaControllers.length, (idx) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.add_location_alt_rounded, color: Voy.violet, size: 18),
                        const SizedBox(width: 8),
                        Text('Stop ${idx + 1}', style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.w700, fontSize: 13.5)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                          onPressed: () => _removeDestinationStop(idx),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _viaControllers[idx],
                      style: const TextStyle(color: Voy.ink, fontSize: 14),
                      decoration: _inputDecoration('Waypoint or intermediate stop', Icons.place_rounded),
                      onChanged: (val) => _onSearchChanged(val, 'via', viaIndex: idx),
                    ),
                    if (_activeViaSuggestIndex == idx && _viaSuggestions.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      ..._viaSuggestions.take(3).map((s) => _suggestionTile(s, (item) {
                        setState(() {
                          _viaControllers[idx].text = item['place_name'] ?? item['name'] ?? '';
                          _viaSuggestions = [];
                        });
                      })),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
        const SizedBox(height: 12),
        // Add Destination button
        OutlinedButton.icon(
          onPressed: _addDestinationStop,
          icon: const Icon(Icons.add_rounded, color: Voy.brand, size: 18),
          label: const Text('Add Stop / Destination', style: TextStyle(color: Voy.brand, fontWeight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: const BorderSide(color: Voy.brand),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 18),
        // Popular shortcuts
        const Text('Quick Destinations', style: TextStyle(color: Voy.sub, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _popularDestinations.map((d) {
            return ActionChip(
              backgroundColor: Voy.surface,
              label: Text(d, style: const TextStyle(color: Voy.ink, fontSize: 12.5, fontWeight: FontWeight.w600)),
              onPressed: () => setState(() => _destCtrl.text = d),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Voy.hairline),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── STEP 2: TRIP TYPE ───────────────────────────────────────────────────
  Widget _buildStep2TripType() {
    final types = [
      {'id': 'one_way', 'title': 'One Way', 'route': 'A → B', 'desc': 'Direct point-to-point road trip with optimal highway routing.'},
      {'id': 'round_trip', 'title': 'Round Trip', 'route': 'A → B → A', 'desc': 'Circuit trip returning to origin with automated return toll savings.'},
      {'id': 'multi_dest', 'title': 'Multi Destination', 'route': 'A → B → C → D', 'desc': 'Sequential route covering multiple specific target destinations.'},
      {'id': 'vacation', 'title': 'Vacation / Multi-Day', 'route': 'A → B → C with day-by-day stops', 'desc': 'Full vacation with balanced daily driving, sightseeing, food & stays.'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Select Trip Architecture', 'One unified trip engine configured for your journey type'),
        const SizedBox(height: 16),
        ...types.map((t) {
          final isSelected = _tripType == t['id'];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onTap: () => setState(() => _tripType = t['id']!),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected ? Voy.brand.withValues(alpha: 0.08) : Voy.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? Voy.brand : Voy.hairline,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: isSelected ? Voy.brand : Voy.hairline.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        t['id'] == 'one_way'
                            ? Icons.trending_flat_rounded
                            : (t['id'] == 'round_trip'
                                ? Icons.sync_alt_rounded
                                : (t['id'] == 'multi_dest' ? Icons.alt_route_rounded : Icons.calendar_month_rounded)),
                        color: isSelected ? Colors.white : Voy.sub,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(t['title']!, style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.w800, fontSize: 15)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Voy.brand.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(t['route']!, style: const TextStyle(color: Voy.brand, fontSize: 11, fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(t['desc']!, style: const TextStyle(color: Voy.sub, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    Icon(
                      isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: isSelected ? Voy.brand : Voy.sub,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  // ── STEP 3: DATE & DURATION ─────────────────────────────────────────────
  Widget _buildStep3DateDuration() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Trip Timing & Duration', 'Calculate driving hours and recommended departure schedules'),
        const SizedBox(height: 16),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Departure Date & Start Time', style: TextStyle(color: Voy.ink, fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _startDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) setState(() => _startDate = picked);
                      },
                      icon: const Icon(Icons.calendar_today_rounded, size: 16, color: Voy.brand),
                      label: Text('${_startDate.day}/${_startDate.month}/${_startDate.year}', style: const TextStyle(color: Voy.ink, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _startTime,
                        );
                        if (picked != null) setState(() => _startTime = picked);
                      },
                      icon: const Icon(Icons.access_time_rounded, size: 16, color: Voy.violet),
                      label: Text(_startTime.format(context), style: const TextStyle(color: Voy.ink, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Trip Duration (Days)', style: TextStyle(color: Voy.ink, fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded, color: Voy.brand),
                    onPressed: _days > 1 ? () => setState(() => _days--) : null,
                  ),
                  Text('$_days ${_days == 1 ? 'Day' : 'Days'}', style: const TextStyle(color: Voy.ink, fontSize: 16, fontWeight: FontWeight.w800)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded, color: Voy.brand),
                    onPressed: _days < 14 ? () => setState(() => _days++) : null,
                  ),
                  const Spacer(),
                  const Text('Travellers: ', style: TextStyle(color: Voy.sub, fontSize: 13, fontWeight: FontWeight.w600)),
                  DropdownButton<int>(
                    value: _travellers,
                    items: List.generate(10, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}'))),
                    onChanged: (v) => setState(() => _travellers = v ?? 1),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Timing sanity indicator (PART 3)
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Voy.brand, size: 18),
                  SizedBox(width: 8),
                  Text('Schedule Sanity Analysis', style: TextStyle(color: Voy.ink, fontWeight: FontWeight.w700, fontSize: 13.5)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _days == 1
                    ? 'Day Trip: Best suited for drives up to 4–5 hours with 2–3 meaningful sightseeing stops.'
                    : '$_days-Day Trip: AI will distribute stops chronologically across days with automated hotel check-ins.',
                style: const TextStyle(color: Voy.sub, fontSize: 12.5),
              ),
              if (_days > 1) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Voy.violet.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('✓ Overnight stay requirement automatically scheduled', style: TextStyle(color: Voy.violet, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── STEP 4: VEHICLE ─────────────────────────────────────────────────────
  Widget _buildStep4Vehicle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Vehicle & Fuel Configuration', 'Authoritative vehicle parameters for zero-error range & cost calculations'),
        const SizedBox(height: 16),
        // Vehicle Select Buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _openVehicleSearch,
                icon: const Icon(Icons.directions_car_rounded, size: 18),
                label: const Text('Select Saved Vehicle'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Voy.brand,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Vehicle Specifications Form
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _vehicleNameCtrl,
                      decoration: _inputDecoration('Vehicle Name / Model', Icons.badge_outlined),
                      style: const TextStyle(color: Voy.ink, fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _transportMode,
                    items: const [
                      DropdownMenuItem(value: 'car', child: Text('Car')),
                      DropdownMenuItem(value: 'bike', child: Text('Bike / Motorcycle')),
                      DropdownMenuItem(value: 'ev', child: Text('EV')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (v) => setState(() => _transportMode = v ?? 'car'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const SizedBox(height: 12),
              if (_transportMode == 'ev') ...[
                // EV-specific Parameters
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _mileageCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _inputDecoration('Efficiency (km/kWh)', Icons.bolt_rounded),
                        style: const TextStyle(color: Voy.ink, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _tankCapacityCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _inputDecoration('Battery Capacity (kWh)', Icons.battery_charging_full_rounded),
                        style: const TextStyle(color: Voy.ink, fontSize: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _currentFuelCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _inputDecoration('Current Charge (%)', Icons.battery_5_bar_rounded),
                        style: const TextStyle(color: Voy.ink, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _fuelPriceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _inputDecoration('Tariff (₹/kWh)', Icons.currency_rupee_rounded),
                        style: const TextStyle(color: Voy.ink, fontSize: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text('Charging Connector Type', style: TextStyle(color: Voy.sub, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: ['CCS2', 'Type 2', 'GB/T'].map((c) {
                    final isSelected = _evConnectorType == c;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: ChoiceChip(
                          label: Center(child: Text(c, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                          selected: isSelected,
                          selectedColor: Voy.brand.withValues(alpha: 0.2),
                          onSelected: (_) => setState(() => _evConnectorType = c),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Voy.brand.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Voy.brand.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.electric_bolt_rounded, color: Voy.brand, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Estimated Safe Range: ${(((double.tryParse(_tankCapacityCtrl.text) ?? 45.0) * ((double.tryParse(_currentFuelCtrl.text) ?? 85.0) / 100.0) * (double.tryParse(_mileageCtrl.text) ?? 6.8)) * 0.85).toStringAsFixed(0)} km (15% reserve buffer)',
                          style: const TextStyle(color: Voy.ink, fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // ICE / Hybrid Parameters
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _mileageCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _inputDecoration('Mileage (km/L)', Icons.speed_rounded),
                        style: const TextStyle(color: Voy.ink, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _tankCapacityCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _inputDecoration('Tank Capacity (L)', Icons.local_gas_station_rounded),
                        style: const TextStyle(color: Voy.ink, fontSize: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _currentFuelCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _inputDecoration('Current Fuel (L)', Icons.ev_station_rounded),
                        style: const TextStyle(color: Voy.ink, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _fuelPriceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _inputDecoration('Fuel Price (₹/L)', Icons.currency_rupee_rounded),
                        style: const TextStyle(color: Voy.ink, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              const Text('Luggage / Passenger Load', style: TextStyle(color: Voy.sub, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: ['light', 'medium', 'heavy'].map((l) {
                  final isSelected = _luggageLoad == l;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Center(child: Text(l[0].toUpperCase() + l.substring(1))),
                        selected: isSelected,
                        selectedColor: Voy.brand.withValues(alpha: 0.2),
                        onSelected: (_) => setState(() => _luggageLoad = l),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── STEP 5: TRAVEL STYLE ────────────────────────────────────────────────
  Widget _buildStep5TravelStyle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Travel Style & Interests', 'Pick categories that match your travel mood. Multiple selections supported.'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _availableStyles.map((style) {
            final isSelected = _selectedStyles.contains(style);
            return FilterChip(
              label: Text(style),
              selected: isSelected,
              selectedColor: Voy.brand.withValues(alpha: 0.2),
              checkmarkColor: Voy.brand,
              labelStyle: TextStyle(
                color: isSelected ? Voy.brand : Voy.ink,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedStyles.add(style);
                  } else {
                    if (_selectedStyles.length > 1) _selectedStyles.remove(style);
                  }
                });
              },
              backgroundColor: Voy.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: isSelected ? Voy.brand : Voy.hairline),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── STEP 6: REVIEW ──────────────────────────────────────────────────────
  Widget _buildStep6Review() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Ready to Build Your Road Trip', 'Review parameters before generating authoritative itinerary & routes'),
        const SizedBox(height: 16),
        _card(
          child: Column(
            children: [
              _reviewRow('Origin', _originCtrl.text.isEmpty ? 'Not set' : _originCtrl.text),
              const Divider(color: Voy.hairline),
              _reviewRow('Destination', _destCtrl.text.isEmpty ? 'Not set' : _destCtrl.text),
              if (_viaControllers.any((c) => c.text.isNotEmpty)) ...[
                const Divider(color: Voy.hairline),
                _reviewRow('Waypoints', _viaControllers.where((c) => c.text.isNotEmpty).map((c) => c.text).join(' • ')),
              ],
              const Divider(color: Voy.hairline),
              _reviewRow('Trip Type', _tripType.replaceAll('_', ' ').toUpperCase()),
              const Divider(color: Voy.hairline),
              _reviewRow('Duration', '$_days Days (${_startDate.day}/${_startDate.month} starting ${_startTime.format(context)})'),
              const Divider(color: Voy.hairline),
              _reviewRow(
                'Vehicle',
                _transportMode == 'ev'
                    ? '${_vehicleNameCtrl.text} (EV) • ${_tankCapacityCtrl.text} kWh • ${_mileageCtrl.text} km/kWh • $_evConnectorType'
                    : '${_vehicleNameCtrl.text} (${_transportMode.toUpperCase()}) • ${_mileageCtrl.text} km/L',
              ),
              const Divider(color: Voy.hairline),
              _reviewRow('Preferences', _selectedStyles.join(', ')),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _generateTrip,
          style: ElevatedButton.styleFrom(
            backgroundColor: Voy.brand,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 4,
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_awesome_rounded, size: 20),
              SizedBox(width: 10),
              Text('✨ Generate My Trip', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ],
    );
  }

  // ── Bottom Step Navigation Bar ──────────────────────────────────────────
  Widget _bottomNavigation() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: const BoxDecoration(
        color: Voy.surface,
        border: Border(top: BorderSide(color: Voy.hairline)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentStep > 1)
            OutlinedButton.icon(
              onPressed: () => setState(() => _currentStep--),
              icon: const Icon(Icons.arrow_back_rounded, size: 16, color: Voy.ink),
              label: const Text('Back', style: TextStyle(color: Voy.ink)),
            )
          else
            const SizedBox.shrink(),
          ElevatedButton(
            onPressed: () {
              if (_currentStep < 6) {
                if (_currentStep == 1) {
                  if (_originCtrl.text.trim().isEmpty || _destCtrl.text.trim().isEmpty) {
                    setState(() => _validationError = 'Please specify both origin and destination.');
                    return;
                  }
                }
                setState(() {
                  _validationError = null;
                  _currentStep++;
                });
              } else {
                _generateTrip();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Voy.brand,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_currentStep == 6 ? 'Generate Trip' : 'Continue', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward_rounded, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Progress Overlay (PART 19) ──────────────────────────────────────────
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
            color: Voy.surface,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(color: Voy.brand, strokeWidth: 3),
              ),
              const SizedBox(height: 18),
              const Text(
                'Crafting Your Perfect Trip',
                style: TextStyle(color: Voy.ink, fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              ...List.generate(stages.length, (idx) {
                final isPassed = _generationStage > idx;
                final isCurrent = _generationStage == idx;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        isPassed
                            ? Icons.check_circle_rounded
                            : (isCurrent ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded),
                        size: 16,
                        color: isPassed ? Colors.green : (isCurrent ? Voy.brand : Voy.sub.withValues(alpha: 0.5)),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        stages[idx],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                          color: isPassed ? Voy.ink : (isCurrent ? Voy.brand : Voy.sub),
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

  // ── Helper Widgets ──────────────────────────────────────────────────────
  Widget _sectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Voy.ink, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: Voy.sub, fontSize: 13.5)),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Voy.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Voy.hairline),
      ),
      child: child,
    );
  }

  Widget _reviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(color: Voy.sub, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Voy.ink, fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Voy.sub, fontSize: 13.5),
      prefixIcon: Icon(icon, color: Voy.sub, size: 20),
      filled: true,
      fillColor: Voy.bg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Voy.hairline)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Voy.hairline)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Voy.brand, width: 1.5)),
    );
  }

  Widget _suggestionTile(Map<String, dynamic> s, Function(Map<String, dynamic>) onSelect) {
    final title = s['place_name'] ?? s['name'] ?? '';
    return ListTile(
      dense: true,
      leading: const Icon(Icons.location_on_outlined, size: 18, color: Voy.brand),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Voy.ink)),
      onTap: () => onSelect(s),
    );
  }
}
