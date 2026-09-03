import 'dart:math' as math;
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
    if (pos != null && pos != old.animatedVehiclePosition && _validPoint(pos)) {
      final zoom = widget.customZoom ?? 15.5;
      // A 3D tilt is only safe once we're zoomed in (following the vehicle);
      // pitch at low zoom makes MapLibre's projection throw std::domain_error.
      _controller?.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: _ll(pos), zoom: zoom, tilt: zoom >= 13 ? 45 : 0),
      ));
      _updateVehicle(pos);
    }
  }

  /// A geographic point is only safe to hand to the native map if it's finite
  /// and inside the valid lat/lng ranges. Anything else makes MapLibre GL Native
  /// throw std::domain_error, which aborts the whole app (SIGABRT).
  bool _validLL(double lat, double lng) =>
      lat.isFinite && lng.isFinite && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;

  bool _validPoint(GeoPoint p) => _validLL(p.lat, p.lng);

  /// A zoom level that comfortably frames a lat/lng span (in degrees) — a safe
  /// replacement for fit-to-bounds (which crashes on a pitched MapLibre camera).
  double _zoomForSpan(double latSpanDeg, double lngSpanDeg) {
    final maxSpan = math.max(latSpanDeg.abs(), lngSpanDeg.abs());
    if (maxSpan <= 0 || !maxSpan.isFinite) return 13.0;
    // The world spans 360° at zoom 0; subtract a little for padding.
    final z = (math.log(360.0 / maxSpan) / math.ln2) - 0.6;
    return z.clamp(2.0, 15.0);
  }

  Future<void> _onStyleLoaded() async {
    final c = _controller;
    if (c == null || _routeDrawn) return;
    _routeDrawn = true;

    final route = widget.routePoints.where(_validPoint).toList();

    if (route.length >= 2) {
      await c.addLine(LineOptions(
        geometry: route.map(_ll).toList(),
        lineColor: '#2E75B6',
        lineWidth: 6.0,
        lineJoin: 'round',
      ));
    }

    // Start / end / waypoint markers as colored circles (valid points only).
    if (_validPoint(widget.start)) await _addMarker(widget.start, '#4CAF50');
    if (_validPoint(widget.end)) await _addMarker(widget.end, '#E53935');
    for (final wp in widget.waypoints) {
      if (_validPoint(wp)) await _addMarker(wp, '#2E75B6');
    }

    // Frame the whole route. We deliberately DON'T use CameraUpdate.newLatLngBounds
    // here: the map has a tilted (pitched) camera, and MapLibre GL Native throws
    // std::domain_error — aborting the whole app (SIGABRT) — when asked to fit
    // bounds with a non-zero pitch. Instead we compute a centre + zoom ourselves
    // and move with newLatLngZoom, which is safe at any pitch.
    if (route.length >= 2) {
      final minLat = route.map((p) => p.lat).reduce((a, b) => a < b ? a : b);
      final maxLat = route.map((p) => p.lat).reduce((a, b) => a > b ? a : b);
      final minLng = route.map((p) => p.lng).reduce((a, b) => a < b ? a : b);
      final maxLng = route.map((p) => p.lng).reduce((a, b) => a > b ? a : b);
      final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
      await c.animateCamera(
          CameraUpdate.newLatLngZoom(center, _zoomForSpan(maxLat - minLat, maxLng - minLng)));
    }

    final pos = widget.animatedVehiclePosition;
    if (pos != null && _validPoint(pos)) _updateVehicle(pos);
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
      circleColor: '#2E75B6',
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
    final firstValid = widget.routePoints.where(_validPoint).cast<GeoPoint?>().firstWhere((_) => true, orElse: () => null);
    final target = firstValid != null ? _ll(firstValid) : const LatLng(20.5937, 78.9629);
    return MapLibreMap(
      styleString: _streetStyle,
      // NO tilt at this low overview zoom — a pitched camera at low zoom makes
      // MapLibre GL Native throw std::domain_error and abort the app. Tilt is
      // applied later only while following the vehicle at high zoom.
      initialCameraPosition: CameraPosition(target: target, zoom: 5, tilt: 0),
      onMapCreated: (c) => _controller = c,
      onStyleLoadedCallback: _onStyleLoaded,
      myLocationEnabled: false,
      trackCameraPosition: true,
      compassEnabled: true,
    );
  }
}
