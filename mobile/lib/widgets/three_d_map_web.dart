import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'dart:js' as js;
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
  late final String _viewType;
  late final String _containerId;
  bool _isMapInitialized = false;

  @override
  void initState() {
    super.initState();
    final uniqueId = DateTime.now().millisecondsSinceEpoch;
    _viewType = 'mapbox-3d-map-view-$uniqueId';
    _containerId = 'mapbox-3d-map-container-$uniqueId';

    // Register platform view factory dynamically for this instance
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) {
        final element = html.DivElement()
          ..id = _containerId
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.backgroundColor = '#1a1a1a';
        return element;
      },
    );

    // Setup global callback to intercept waypoint addition clicks from the Mapbox popup
    js.context['addWaypointFrom3D'] = (String name, double lat, double lng) {
      widget.onAddWaypoint(PlaceOfInterest(
        id: DateTime.now().millisecondsSinceEpoch,
        name: name,
        lat: lat,
        lng: lng,
      ));
    };
  }

  DateTime? _lastCallTime;

  @override
  void dispose() {
    // Tear down the Mapbox map + its render loop so disposed previews don't
    // keep running behind the current one (which caused animation stutter).
    try {
      js.context.callMethod('removeMapbox3D', [_containerId]);
    } catch (_) {}
    super.dispose();
  }

  @override
  void didUpdateWidget(ThreeDMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animatedVehiclePosition != oldWidget.animatedVehiclePosition ||
        widget.speed != oldWidget.speed ||
        widget.customZoom != oldWidget.customZoom) {
      if (widget.animatedVehiclePosition != null) {
        final now = DateTime.now();
        // Throttle JS calls to max 30 FPS (every 33ms) to prevent WebGL/JS bridge congestion
        if (_lastCallTime == null ||
            now.difference(_lastCallTime!).inMilliseconds > 16 ||
            widget.speed == 0.0) {
          _lastCallTime = now;
          js.context.callMethod('update3DVehiclePosition', [
            widget.animatedVehiclePosition!.lng,
            widget.animatedVehiclePosition!.lat,
            widget.vehicleRotation,
            widget.speed,
            widget.customZoom,
          ]);
        }
      } else {
        js.context.callMethod('hide3DVehicle');
      }
    }
  }

  void _initMap() {
    final routeJson = jsonEncode(widget.routePoints.map((p) => [p.lng, p.lat]).toList());
    final waypointsJson = jsonEncode(widget.waypoints.map((p) => {'lat': p.lat, 'lng': p.lng, 'name': p.name}).toList());
    
    final flatPois = <Map<String, dynamic>>[];
    widget.pois.forEach((category, list) {
      for (final p in list) {
        flatPois.add({
          'id': p.id,
          'name': p.name,
          'lat': p.lat,
          'lng': p.lng,
          'address': p.address,
          'category': category,
        });
      }
    });
    final poisJson = jsonEncode(flatPois);

    const accessToken = 'pk.eyJ1IjoiZ293dGhhbWVjNjQiLCJhIjoiY21yZzhnOG82MGh2dTJ6c2FuM3h6ZXdkayJ9.PmiHwk5A4-eSWu7zLYkSXQ';
    // Mapbox Standard: 3D buildings + clean day lighting for the cinematic
    // turn-by-turn look (matches the reference navigation view).
    const styleUrl = 'mapbox://styles/mapbox/standard';

    // Invoke the JS global helper
    js.context.callMethod('initMapbox3D', [
      _containerId,
      accessToken,
      styleUrl,
      routeJson,
      waypointsJson,
      poisJson,
      widget.vehicleType,
    ]);
  }

  Widget? _cachedHtmlView;

  @override
  Widget build(BuildContext context) {
    _cachedHtmlView ??= HtmlElementView(
      viewType: _viewType,
      onPlatformViewCreated: (int id) {
        if (!_isMapInitialized) {
          _isMapInitialized = true;
          // Wait briefly for the DOM element to mount and be ready
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) {
              _initMap();
            }
          });
        }
      },
    );
    return _cachedHtmlView!;
  }
}
