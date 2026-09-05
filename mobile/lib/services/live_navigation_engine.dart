import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/trip_models.dart';
import '../models/car_mode_models.dart';
import 'api_service.dart';
import 'car_guidance_service.dart';
import 'car_platform_channel.dart';
import 'voice_guide.dart';

class LiveNavigationEngine extends ChangeNotifier {
  static final LiveNavigationEngine _instance = LiveNavigationEngine._internal();
  factory LiveNavigationEngine() => _instance;
  LiveNavigationEngine._internal();

  final ApiService _api = ApiService();
  final CarGuidanceService _guidance = CarGuidanceService();
  final VoiceGuide _voice = VoiceGuide();

  // Navigation state
  bool _isNavigating = false;
  bool _isRerouting = false;
  bool _isArrivedAtDestination = false;
  String? _arrivedStopName;

  Position? _rawPosition;
  LatLng? _vehiclePosition;
  double _vehicleRotation = 0.0; // radians
  double _liveSpeedKmh = 0.0;
  String _speedUnit = 'km/h'; // 'km/h' or 'mph'
  GpsHealthStatus _gpsStatus = GpsHealthStatus.searching;

  TripPlan? _activePlan;
  GeoPoint? _currentOrigin;
  GeoPoint? _destination;
  List<GeoPoint> _remainingWaypoints = [];
  final List<GeoPoint> _visitedWaypoints = [];
  List<RefuelStop> _fuelStops = [];
  final Set<String> _announcedFuelStops = {};
  final Set<String> _visitedFuelStops = {};
  Vehicle? _vehicle;

  ManeuverInstruction _currentManeuver = const ManeuverInstruction(
    type: ManeuverType.straight,
    instruction: 'Starting navigation…',
    distanceMeters: 0,
  );

  double _remainingDistanceKm = 0.0;
  int _remainingDurationMin = 0;
  double _progressPercent = 0.0;

  StreamSubscription<Position>? _positionSubscription;
  Timer? _gpsWatchdog;
  DateTime? _lastFixTime;
  int _offRouteStreak = 0;
  static const int _kRequiredOffRouteFixes = 3;
  static const double _kOffRouteThresholdMeters = 45.0;
  static const double _kStopArrivalRadiusMeters = 75.0;

  // Getters
  bool get isNavigating => _isNavigating;
  bool get isRerouting => _isRerouting;
  bool get isArrivedAtDestination => _isArrivedAtDestination;
  String? get arrivedStopName => _arrivedStopName;

  Position? get rawPosition => _rawPosition;
  LatLng? get vehiclePosition => _vehiclePosition;
  double get vehicleRotation => _vehicleRotation;
  double get liveSpeedKmh => _liveSpeedKmh;
  String get speedUnit => _speedUnit;
  GpsHealthStatus get gpsStatus => _gpsStatus;

  TripPlan? get activePlan => _activePlan;
  GeoPoint? get currentOrigin => _currentOrigin;
  GeoPoint? get destination => _destination;
  List<GeoPoint> get remainingWaypoints => List.unmodifiable(_remainingWaypoints);
  List<GeoPoint> get visitedWaypoints => List.unmodifiable(_visitedWaypoints);
  List<RefuelStop> get fuelStops => List.unmodifiable(_fuelStops);

  ManeuverInstruction get currentManeuver => _currentManeuver;
  double get remainingDistanceKm => _remainingDistanceKm;
  int get remainingDurationMin => _remainingDurationMin;
  double get progressPercent => _progressPercent;

  CarTelemetry get telemetry => CarTelemetry(
        speedKmh: _liveSpeedKmh,
        remainingDistanceKm: _remainingDistanceKm,
        remainingDurationMin: _remainingDurationMin,
        progressPercent: _progressPercent,
        nextStopName: _remainingWaypoints.isNotEmpty ? _remainingWaypoints.first.name : _destination?.name,
        gpsStatus: _gpsStatus,
        isRerouting: _isRerouting,
        speedUnit: _speedUnit,
      );

  Future<void> startNavigation({
    required TripPlan initialPlan,
    required GeoPoint start,
    required GeoPoint end,
    List<GeoPoint> waypoints = const [],
    List<RefuelStop>? fuelStops,
    required Vehicle vehicle,
    String speedUnit = 'km/h',
  }) async {
    await stopNavigation();

    _activePlan = initialPlan;
    _currentOrigin = start;
    _destination = end;
    _remainingWaypoints = List.from(waypoints);
    _fuelStops = fuelStops != null ? List.from(fuelStops) : List.from(initialPlan.fuel.refuelStops);
    _visitedWaypoints.clear();
    _announcedFuelStops.clear();
    _visitedFuelStops.clear();
    _vehicle = vehicle;
    _speedUnit = speedUnit;
    _isNavigating = true;
    _isRerouting = false;
    _isArrivedAtDestination = false;
    _arrivedStopName = null;
    _offRouteStreak = 0;
    _gpsStatus = GpsHealthStatus.searching;
    _remainingDistanceKm = initialPlan.distanceKm;
    _remainingDurationMin = initialPlan.durationMin;
    _progressPercent = 0.0;

    if (_fuelStops.isNotEmpty) {
      debugPrint('[FUEL] LiveNavigationEngine initialized with ${_fuelStops.length} fuel stop(s)');
    }

    CarPlatformChannel.initialize();
    CarPlatformChannel.onCarStopNavigation = () {
      debugPrint('[CAR] Navigation stop requested from car display');
      stopNavigation();
    };

    CarPlatformChannel.setRoute(
      start: start,
      end: end,
      waypoints: _remainingWaypoints,
      routeCoordinates: initialPlan.coordinates,
      fuelStops: _fuelStops,
      destinationName: end.name,
    );
    CarPlatformChannel.setNavigationState(isNavigating: true);

    // Platform-appropriate location settings
    final LocationSettings settings = (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
        ? AppleSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 2,
            activityType: ActivityType.automotiveNavigation,
            pauseLocationUpdatesAutomatically: false,
            showBackgroundLocationIndicator: true,
            allowBackgroundLocationUpdates: true,
          )
        : (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
            ? AndroidSettings(
                accuracy: LocationAccuracy.high,
                distanceFilter: 2,
                intervalDuration: const Duration(milliseconds: 1000),
                foregroundNotificationConfig: const ForegroundNotificationConfig(
                  notificationTitle: 'Voyplan Live Navigation',
                  notificationText: 'Turn-by-turn guidance is active',
                  enableWakeLock: true,
                ),
              )
            : const LocationSettings(
                accuracy: LocationAccuracy.high,
                distanceFilter: 2,
              );

    // Initial fix attempt
    try {
      final firstPos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      _onPositionUpdate(firstPos);
    } catch (_) {}

    _positionSubscription = Geolocator.getPositionStream(locationSettings: settings).listen(
      _onPositionUpdate,
      onError: (err) {
        _gpsStatus = GpsHealthStatus.lost;
        notifyListeners();
      },
    );

    // GPS Watchdog to detect signal loss (> 7s without fix)
    _gpsWatchdog = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_isNavigating) return;
      if (_lastFixTime == null || DateTime.now().difference(_lastFixTime!).inSeconds > 6) {
        if (_gpsStatus != GpsHealthStatus.searching && _gpsStatus != GpsHealthStatus.lost) {
          _gpsStatus = GpsHealthStatus.lost;
          notifyListeners();
        }
      }
    });

    notifyListeners();
  }

  /// Handles incoming live GPS positions from the device stream.
  void _onPositionUpdate(Position pos) {
    if (!_isNavigating) return;

    _lastFixTime = DateTime.now();
    _rawPosition = pos;

    // Filter accuracy
    if (pos.accuracy > 70) {
      _gpsStatus = GpsHealthStatus.weak;
    } else {
      _gpsStatus = GpsHealthStatus.active;
    }

    final here = LatLng(pos.latitude, pos.longitude);
    final routePoints = _activePlan?.coordinates ?? [];

    if (routePoints.isEmpty) {
      _vehiclePosition = here;
      notifyListeners();
      return;
    }

    // 1. Road matching & projection
    final proj = _guidance.projectOnRoute(here, routePoints);
    final double distFromRoute = proj.distanceFromRouteMeters;

    // Calculate live speed in km/h
    final speed = (pos.speed.isFinite && pos.speed > 0) ? pos.speed * 3.6 : 0.0;
    _liveSpeedKmh = speed;

    // Heading calculation: when moving (> 2.5 km/h), use device heading or segment bearing;
    // when stationary (<= 2.5 km/h), preserve last reliable heading to prevent spinning from GPS jitter.
    double headingRad;
    if (speed > 2.5) {
      if (pos.heading.isFinite && pos.heading >= 0) {
        headingRad = pos.heading * pi / 180.0;
      } else {
        headingRad = proj.segmentBearing * pi / 180.0;
      }
    } else {
      headingRad = _vehicleRotation;
    }
    _vehicleRotation = headingRad;

    // 2. Off-Route Check & Automatic Reroute
    if (distFromRoute > _kOffRouteThresholdMeters && pos.accuracy <= 35) {
      _offRouteStreak++;
      // If vehicle is off-route, display real GPS position rather than snapping
      _vehiclePosition = here;

      if (_offRouteStreak >= _kRequiredOffRouteFixes && !_isRerouting) {
        _triggerReroute(here);
      }
    } else {
      _offRouteStreak = 0;
      // When on-route within 45m, snap vehicle marker smoothly to road centerline
      if (distFromRoute <= 45.0) {
        _vehiclePosition = proj.snappedPoint;
      } else {
        _vehiclePosition = here;
      }
    }

    // 3. Compute remaining distance & duration
    final totalKm = _activePlan?.distanceKm ?? 0.0;
    _progressPercent = proj.progressPercent;
    _remainingDistanceKm = (proj.remainingDistanceMeters / 1000.0).clamp(0.0, totalKm > 0 ? totalKm : 9999.0);

    final double paceKmh = speed > 10
        ? speed
        : (totalKm > 0 && (_activePlan?.durationMin ?? 0) > 0
            ? totalKm / (_activePlan!.durationMin / 60.0)
            : 42.0);
    _remainingDurationMin = paceKmh > 0 ? (_remainingDistanceKm / paceKmh * 60).round() : 0;

    // 4. Calculate Maneuvers & Lane Guidance
    if (_destination != null) {
      _currentManeuver = _guidance.calculateManeuver(
        currentPos: _vehiclePosition ?? here,
        routePoints: routePoints,
        end: _destination!,
        waypoints: _remainingWaypoints,
        activeWaypointIndex: _remainingWaypoints.isNotEmpty ? 0 : null,
      );

      // Voice announcements
      _guidance.announceManeuver(_currentManeuver);
    }

    // 5. Check Stop & Destination Arrivals
    _checkArrivals(here);

    // 6. Push telemetry to CarPlay / Android Auto
    CarPlatformChannel.updateNavigation(
      maneuver: _currentManeuver,
      telemetry: telemetry,
      currentLat: here.latitude,
      currentLng: here.longitude,
      bearingDeg: _vehicleRotation * 180.0 / pi,
      roadName: _currentManeuver.roadName,
      nextFuelStop: _fuelStops.isNotEmpty ? _fuelStops.first : null,
    );

    notifyListeners();
  }

  /// Automatically triggers dynamic route recalculation from the CURRENT vehicle position.
  Future<void> _triggerReroute(LatLng currentGps) async {
    if (_isRerouting || _destination == null || _vehicle == null) return;

    _isRerouting = true;
    _guidance.announceManeuver(
      const ManeuverInstruction(
        type: ManeuverType.straight,
        instruction: 'Rerouting from current location',
        distanceMeters: 0,
      ),
      force: true,
    );
    notifyListeners();

    try {
      // Filter out any waypoint that was already visited or passed near the vehicle
      final unvisitedWaypoints = <GeoPoint>[];
      for (final wp in _remainingWaypoints) {
        final distToWp = const Distance().as(LengthUnit.Meter, currentGps, wp.toLatLng());
        if (distToWp <= _kStopArrivalRadiusMeters) {
          _visitedWaypoints.add(wp);
        } else {
          unvisitedWaypoints.add(wp);
        }
      }
      _remainingWaypoints = unvisitedWaypoints;

      final currentOrigin = GeoPoint(
        lat: currentGps.latitude,
        lng: currentGps.longitude,
        name: 'Current Location',
      );

      final newPlan = await _api.planTrip(
        start: currentOrigin,
        end: _destination!,
        waypoints: _remainingWaypoints,
        vehicle: _vehicle!,
      );

      if (newPlan.coordinates.isNotEmpty) {
        _activePlan = newPlan;
        _currentOrigin = currentOrigin;
        _remainingDistanceKm = newPlan.distanceKm;
        _remainingDurationMin = newPlan.durationMin;
        _offRouteStreak = 0;
        if (newPlan.fuel.refuelStops.isNotEmpty) {
          _fuelStops = List.from(newPlan.fuel.refuelStops);
          debugPrint('[FUEL] Live reroute updated fuel stops: ${_fuelStops.length} stop(s)');
        }

        // Sync recalculated route and fuel stops with Android Auto / CarPlay immediately
        CarPlatformChannel.setRoute(
          start: currentOrigin,
          end: _destination!,
          waypoints: _remainingWaypoints,
          routeCoordinates: newPlan.coordinates,
          fuelStops: _fuelStops,
          destinationName: _destination?.name,
        );

        _guidance.announceManeuver(
          const ManeuverInstruction(
            type: ManeuverType.straight,
            instruction: 'New route calculated. Follow the road.',
            distanceMeters: 0,
          ),
          force: true,
        );
      }
    } catch (e) {
      debugPrint('Automatic reroute error: $e');
    } finally {
      _isRerouting = false;
      notifyListeners();
    }
  }

  /// Checks if the vehicle has arrived at intermediate waypoints, fuel stops, or the final destination.
  void _checkArrivals(LatLng currentPos) {
    const distCalc = Distance();

    // 1. Check intermediate waypoints
    if (_remainingWaypoints.isNotEmpty) {
      final nextWp = _remainingWaypoints.first;
      final d = distCalc.as(LengthUnit.Meter, currentPos, nextWp.toLatLng());
      bool isArrived = d <= _kStopArrivalRadiusMeters;

      // Also check if vehicle has progressed past this waypoint along the planned polyline
      if (!isArrived && _activePlan != null && _activePlan!.coordinates.length >= 2) {
        final totalM = _activePlan!.distanceMeters;
        if (totalM > 0) {
          final wpProj = _guidance.projectOnRoute(
            nextWp.toLatLng(),
            _activePlan!.coordinates,
          );
          final currDistanceMeters = _progressPercent * totalM;
          final wpDistanceMeters = wpProj.progressPercent * totalM;
          if (currDistanceMeters > wpDistanceMeters + 120) {
            isArrived = true;
          }
        }
      }

      if (isArrived) {
        final arrived = _remainingWaypoints.removeAt(0);
        _visitedWaypoints.add(arrived);
        _arrivedStopName = arrived.name ?? 'Stop';
        _guidance.announceManeuver(
          ManeuverInstruction(
            type: ManeuverType.waypoint,
            instruction: 'You have arrived at ${arrived.name ?? "stop"}',
            distanceMeters: 0,
          ),
          force: true,
        );
        notifyListeners();
      }
    }

    // 2. Check fuel stops approach and arrivals
    for (final fs in _fuelStops) {
      final stopKey = fs.id.isNotEmpty ? fs.id : 'fuel_${fs.lat}_${fs.lng}';
      if (_visitedFuelStops.contains(stopKey)) continue;

      final fuelLatLng = LatLng(fs.lat, fs.lng);
      final d = distCalc.as(LengthUnit.Meter, currentPos, fuelLatLng);

      // Voice approach notice (around 2km)
      if (d <= 2500 && d > 150 && !_announcedFuelStops.contains(stopKey)) {
        _announcedFuelStops.add(stopKey);
        final distKm = (d / 1000.0).toStringAsFixed(1);
        _voice.speak('Fuel stop ahead: ${fs.name}, in $distKm kilometers.');
      }

      // Arrival at fuel stop (within 75m)
      if (d <= 75.0) {
        _visitedFuelStops.add(stopKey);
        _arrivedStopName = '⛽ ${fs.name}';
        _guidance.announceManeuver(
          ManeuverInstruction(
            type: ManeuverType.waypoint,
            instruction: 'Arriving at fuel stop: ${fs.name}. Tank refueled.',
            distanceMeters: 0,
          ),
          force: true,
        );

        // Top-up vehicle tank to capacity
        if (_vehicle != null) {
          _vehicle = _vehicle!.copyWith(
            currentFuelLiters: _vehicle!.tankCapacityLiters,
          );
          debugPrint('[FUEL] Vehicle refueled at ${fs.name}. Fuel level reset to ${_vehicle!.tankCapacityLiters}L');
        }
        notifyListeners();
      }
    }

    // 2. Check final destination
    if (_destination != null && !_isArrivedAtDestination) {
      final destDistance = distCalc.as(LengthUnit.Meter, currentPos, _destination!.toLatLng());
      if (destDistance <= _kStopArrivalRadiusMeters) {
        _isArrivedAtDestination = true;
        _arrivedStopName = _destination!.name ?? 'Destination';
        _guidance.announceManeuver(
          ManeuverInstruction(
            type: ManeuverType.destination,
            instruction: 'You have arrived at your destination: ${_destination!.name ?? ""}',
            distanceMeters: 0,
          ),
          force: true,
        );
        notifyListeners();
      }
    }
  }

  /// Stops active navigation session.
  Future<void> stopNavigation() async {
    _isNavigating = false;
    _isRerouting = false;
    _gpsWatchdog?.cancel();
    _gpsWatchdog = null;
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    CarPlatformChannel.setNavigationState(isNavigating: false);
    notifyListeners();
  }

  @override
  void dispose() {
    stopNavigation();
    super.dispose();
  }
}
