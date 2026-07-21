import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math';
import '../models/trip_models.dart';

class ThreeDMap extends StatefulWidget {
  final List<GeoPoint> routePoints;
  final Map<String, List<PlaceOfInterest>> pois;
  final GeoPoint start;
  final GeoPoint end;
  final List<GeoPoint> waypoints;
  final bool useSatellite;
  final String vehicleType;
  final GeoPoint? animatedVehiclePosition;
  final double vehicleRotation;
  final double speed;
  final double? customZoom;
  final Function(PlaceOfInterest) onAddWaypoint;

  const ThreeDMap({
    super.key,
    required this.routePoints,
    required this.pois,
    required this.start,
    required this.end,
    required this.waypoints,
    required this.useSatellite,
    required this.vehicleType,
    this.animatedVehiclePosition,
    this.vehicleRotation = 0.0,
    this.speed = 1.0,
    this.customZoom,
    required this.onAddWaypoint,
  });

  @override
  State<ThreeDMap> createState() => _ThreeDMapState();
}

class _ThreeDMapState extends State<ThreeDMap> {
  final MapController _mapController = MapController();

  @override
  void didUpdateWidget(ThreeDMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animatedVehiclePosition != oldWidget.animatedVehiclePosition &&
        widget.animatedVehiclePosition != null) {
      _mapController.move(widget.animatedVehiclePosition!.toLatLng(), 14.5);
    }
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

  int _getClosestIndex(GeoPoint point) {
    int closestIdx = 0;
    double minDistance = double.infinity;
    for (int i = 0; i < widget.routePoints.length; i++) {
      final p = widget.routePoints[i];
      final dist = (p.lat - point.lat) * (p.lat - point.lat) + (p.lng - point.lng) * (p.lng - point.lng);
      if (dist < minDistance) {
        minDistance = dist;
        closestIdx = i;
      }
    }
    return closestIdx;
  }

  bool _isPointVisited(GeoPoint point) {
    if (widget.animatedVehiclePosition == null) return true;
    int currentIdx = _getClosestIndex(widget.animatedVehiclePosition!);
    int pointIdx = _getClosestIndex(point);
    return currentIdx >= pointIdx;
  }

  List<Marker> _buildMarkers(BuildContext context) {
    final markers = <Marker>[];

    // Start point pin (always show)
    if (widget.routePoints.isNotEmpty) {
      markers.add(_pin(
        widget.routePoints.first.toLatLng(),
        Icons.trip_origin,
        Colors.green,
        label: widget.start.name ?? 'Start',
      ));
    }

    // End point pin (pop up when reached)
    if (widget.routePoints.length > 1) {
      if (widget.animatedVehiclePosition == null ||
          _getClosestIndex(widget.animatedVehiclePosition!) >= widget.routePoints.length - 2) {
        markers.add(_pin(
          widget.routePoints.last.toLatLng(),
          Icons.flag,
          Colors.red,
          label: widget.end.name ?? 'End',
        ));
      }
    }

    // Selected places to visit (waypoints) pins (pop up as passed)
    for (int i = 0; i < widget.waypoints.length; i++) {
      final wp = widget.waypoints[i];
      if (!_isPointVisited(wp)) continue;
      markers.add(_pin(
        wp.toLatLng(),
        Icons.location_on,
        const Color(0xFF2E75B6),
        label: wp.name ?? 'Stop ${i + 1}',
      ));
    }

    // Animated vehicle marker using 3D Asset or Emoji and Pulsing Ring
    if (widget.animatedVehiclePosition != null) {
      final isCar = widget.vehicleType.toLowerCase() == 'car' || widget.vehicleType.toLowerCase() == 'suv';
      markers.add(Marker(
        point: widget.animatedVehiclePosition!.toLatLng(),
        width: 50,
        height: 50,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const _PulsingRing(),
            _DrivingWobble(
              child: isCar
                  ? Transform.rotate(
                      angle: widget.vehicleRotation + (3 * pi / 4), // 135 degree offset for SW isometric car
                      child: Image.asset(
                        'assets/images/isometric_car.png',
                        width: 28,
                        height: 28,
                        fit: BoxFit.contain,
                      ),
                    )
                  : Transform.rotate(
                      angle: widget.vehicleRotation + (pi / 2), // 90 degree offset for emojis
                      child: Text(
                        _getVehicleEmoji(widget.vehicleType),
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

  Marker _pin(LatLng point, IconData icon, Color color, {String? label}) {
    return Marker(
      point: point,
      width: label != null ? 120 : 40,
      height: label != null ? 60 : 40,
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
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.4), blurRadius: 6, spreadRadius: 1),
                BoxShadow(color: Colors.black26, blurRadius: 3, offset: const Offset(0, 1)),
              ],
              border: Border.all(color: color, width: 2),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fullLatLngPoints = widget.routePoints.map((c) => c.toLatLng()).toList();
    final bounds = LatLngBounds.fromPoints(fullLatLngPoints);

    // Dynamic Route Line: slice coordinates up to vehicle position if animating
    final visibleLatLngPoints = widget.animatedVehiclePosition == null
        ? fullLatLngPoints
        : fullLatLngPoints.take(_getClosestIndex(widget.animatedVehiclePosition!) + 1).toList();

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(80)),
      ),
      children: [
        TileLayer(
          urlTemplate: widget.useSatellite
              ? 'https://api.mapbox.com/styles/v1/mapbox/satellite-streets-v12/tiles/{z}/{x}/{y}?access_token=pk.eyJ1IjoiZ293dGhhbWVjNjQiLCJhIjoiY21yZzhnOG82MGh2dTJ6c2FuM3h6ZXdkayJ9.PmiHwk5A4-eSWu7zLYkSXQ'
              : 'https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/tiles/{z}/{x}/{y}?access_token=pk.eyJ1IjoiZ293dGhhbWVjNjQiLCJhIjoiY21yZzhnOG82MGh2dTJ6c2FuM3h6ZXdkayJ9.PmiHwk5A4-eSWu7zLYkSXQ',
          userAgentPackageName: 'com.example.travel_app',
          additionalOptions: const {
            'accessToken': 'pk.eyJ1IjoiZ293dGhhbWVjNjQiLCJhIjoiY21yZzhnOG82MGh2dTJ6c2FuM3h6ZXdkayJ9.PmiHwk5A4-eSWu7zLYkSXQ',
          },
        ),
        PolylineLayer(
          polylines: [
            Polyline(points: visibleLatLngPoints, strokeWidth: 6, color: const Color(0xFF2E75B6)),
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
