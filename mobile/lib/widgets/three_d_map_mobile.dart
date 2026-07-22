import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../models/trip_models.dart';

/// Native mobile map, rendered with MapLibre GL and free OpenFreeMap vector
/// tiles (no access token, no request limits). Web keeps its own renderer via
/// the conditional export in `three_d_map.dart`.
///
/// The public API mirrors the previous flutter_map implementation exactly so no
/// call site changes. Markers are drawn as circles (no sprite/glyph dependency)
/// so they render regardless of the style's icon set.
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
  // Free vector styles (no token). 'liberty' = street map; alternatives at
  // https://tiles.openfreemap.org/styles/{liberty,bright,positron}
  static const _streetStyle = 'https://tiles.openfreemap.org/styles/liberty';

  MapLibreMapController? _controller;
  Circle? _vehicleCircle;
  bool _routeDrawn = false;

  LatLng _ll(GeoPoint p) => LatLng(p.lat, p.lng);

  @override
  void didUpdateWidget(covariant ThreeDMap old) {
    super.didUpdateWidget(old);
    final pos = widget.animatedVehiclePosition;
    if (pos != null && pos != old.animatedVehiclePosition) {
      _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(_ll(pos), widget.customZoom ?? 15.5),
      );
      _updateVehicle(pos);
    }
  }

  Future<void> _onStyleLoaded() async {
    final c = _controller;
    if (c == null || _routeDrawn) return;
    _routeDrawn = true;

    if (widget.routePoints.isNotEmpty) {
      await c.addLine(LineOptions(
        geometry: widget.routePoints.map(_ll).toList(),
        lineColor: '#2E75B6',
        lineWidth: 6.0,
        lineJoin: 'round',
      ));
    }

    // Start / end / waypoint markers as colored circles.
    await _addMarker(widget.start, '#4CAF50');
    await _addMarker(widget.end, '#E53935');
    for (final wp in widget.waypoints) {
      await _addMarker(wp, '#2E75B6');
    }

    // Fit the camera to the route bounds.
    if (widget.routePoints.length >= 2) {
      final lats = widget.routePoints.map((p) => p.lat);
      final lngs = widget.routePoints.map((p) => p.lng);
      await c.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(lats.reduce((a, b) => a < b ? a : b), lngs.reduce((a, b) => a < b ? a : b)),
          northeast: LatLng(lats.reduce((a, b) => a > b ? a : b), lngs.reduce((a, b) => a > b ? a : b)),
        ),
        left: 48, right: 48, top: 48, bottom: 48,
      ));
    }

    final pos = widget.animatedVehiclePosition;
    if (pos != null) _updateVehicle(pos);
  }

  Future<void> _addMarker(GeoPoint p, String color) async {
    await _controller?.addCircle(CircleOptions(
      geometry: _ll(p),
      circleRadius: 7.0,
      circleColor: color,
      circleStrokeColor: '#FFFFFF',
      circleStrokeWidth: 2.0,
    ));
  }

  Future<void> _updateVehicle(GeoPoint pos) async {
    final c = _controller;
    if (c == null) return;
    final opts = CircleOptions(
      geometry: _ll(pos),
      circleRadius: 9.0,
      circleColor: '#6C63FF',
      circleStrokeColor: '#FFFFFF',
      circleStrokeWidth: 3.0,
    );
    if (_vehicleCircle == null) {
      _vehicleCircle = await c.addCircle(opts);
    } else {
      await c.updateCircle(_vehicleCircle!, opts);
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.routePoints.isNotEmpty
        ? _ll(widget.routePoints.first)
        : const LatLng(20.5937, 78.9629);
    return MapLibreMap(
      styleString: _streetStyle,
      initialCameraPosition: CameraPosition(target: target, zoom: 5, tilt: 45),
      onMapCreated: (c) => _controller = c,
      onStyleLoadedCallback: _onStyleLoaded,
      myLocationEnabled: false,
      trackCameraPosition: true,
      compassEnabled: true,
    );
  }
}
