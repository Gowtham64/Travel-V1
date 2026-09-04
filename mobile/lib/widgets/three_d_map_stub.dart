import 'package:flutter/material.dart';
import '../models/trip_models.dart';

class ThreeDMap extends StatelessWidget {
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
  final VoidCallback? onUserExplore;

  static void recenter(double lng, double lat, double bearingDeg) {}

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
    this.onUserExplore,
  });

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '3D Map is loading or not supported on this platform',
        style: TextStyle(color: Colors.white70),
      ),
    );
  }
}
