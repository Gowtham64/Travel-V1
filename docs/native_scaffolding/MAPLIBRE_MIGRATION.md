# MapLibre GL migration (free vector map, no token)

Replaces the raster `flutter_map` + Mapbox tiles on **mobile** with a native
**MapLibre GL** vector map using free **OpenFreeMap** tiles (no API key, no
request limits). Web keeps its existing renderer via the conditional import in
`lib/widgets/three_d_map.dart`.

> Kept as a doc (not applied) so it can't break the green build. Apply it on a
> branch and let CI confirm the native build before merging — a new native
> dependency (`maplibre_gl`) links iOS pods + Android Gradle that can't be
> verified without the toolchains.

## 1. Dependency
`mobile/pubspec.yaml`:
```yaml
dependencies:
  maplibre_gl: ^0.20.0   # check pub.dev for the latest compatible version
```
Then `flutter pub get`. iOS: `cd ios && pod install`. Android: MapLibre needs
`minSdk` 21+ (already satisfied).

## 2. Replace the mobile map widget
Swap the body of `mobile/lib/widgets/three_d_map_mobile.dart` for the MapLibre
implementation below. It keeps the **exact same `ThreeDMap` constructor** the app
already uses, so no call sites change.

```dart
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../models/trip_models.dart';

// Free, no-token vector style. Alternatives:
//   https://tiles.openfreemap.org/styles/bright
//   MapTiler (free tier, needs key): https://api.maptiler.com/maps/streets/style.json?key=KEY
const _styleUrl = 'https://tiles.openfreemap.org/styles/liberty';

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
  MapLibreMapController? _controller;
  Line? _routeLine;
  Symbol? _vehicleSymbol;

  LatLng _toLatLng(GeoPoint p) => LatLng(p.lat, p.lng);

  @override
  void didUpdateWidget(covariant ThreeDMap old) {
    super.didUpdateWidget(old);
    final pos = widget.animatedVehiclePosition;
    if (pos != null && pos != old.animatedVehiclePosition) {
      _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(_toLatLng(pos), widget.customZoom ?? 15.5),
      );
      _updateVehicle(pos);
    }
  }

  Future<void> _onStyleLoaded() async {
    final c = _controller;
    if (c == null || widget.routePoints.isEmpty) return;

    // Route polyline
    _routeLine = await c.addLine(LineOptions(
      geometry: widget.routePoints.map(_toLatLng).toList(),
      lineColor: '#2E75B6',
      lineWidth: 6.0,
    ));

    // Start / end / waypoint markers
    await c.addSymbol(SymbolOptions(
      geometry: _toLatLng(widget.start),
      iconImage: 'marker-15',
      textField: widget.start.name ?? 'Start',
      textOffset: const Offset(0, 1.4),
    ));
    await c.addSymbol(SymbolOptions(
      geometry: _toLatLng(widget.end),
      iconImage: 'marker-15',
      textField: widget.end.name ?? 'Destination',
      textOffset: const Offset(0, 1.4),
    ));
    for (final wp in widget.waypoints) {
      await c.addSymbol(SymbolOptions(
        geometry: _toLatLng(wp),
        iconImage: 'marker-15',
        textField: wp.name ?? '',
      ));
    }

    // Fit the route bounds
    final lats = widget.routePoints.map((p) => p.lat);
    final lngs = widget.routePoints.map((p) => p.lng);
    await c.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(lats.reduce((a, b) => a < b ? a : b), lngs.reduce((a, b) => a < b ? a : b)),
        northeast: LatLng(lats.reduce((a, b) => a > b ? a : b), lngs.reduce((a, b) => a > b ? a : b)),
      ),
      left: 40, right: 40, top: 40, bottom: 40,
    ));
  }

  Future<void> _updateVehicle(GeoPoint pos) async {
    final c = _controller;
    if (c == null) return;
    final opts = SymbolOptions(
      geometry: _toLatLng(pos),
      iconImage: 'car-15',
      iconRotate: widget.vehicleRotation * 180 / 3.14159,
      iconSize: 1.6,
    );
    if (_vehicleSymbol == null) {
      _vehicleSymbol = await c.addSymbol(opts);
    } else {
      await c.updateSymbol(_vehicleSymbol!, opts);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MapLibreMap(
      styleString: _styleUrl,
      initialCameraPosition: CameraPosition(
        target: widget.routePoints.isNotEmpty
            ? _toLatLng(widget.routePoints.first)
            : const LatLng(20.5937, 78.9629),
        zoom: 5,
      ),
      onMapCreated: (c) => _controller = c,
      onStyleLoadedCallback: _onStyleLoaded,
      myLocationEnabled: false,
      trackCameraPosition: true,
    );
  }
}
```

## 3. 3D terrain / tilt (optional, matches the old globe vibe)
MapLibre supports pitch + a terrain source for the “3D navigation” feel:
```dart
initialCameraPosition: CameraPosition(target: ..., zoom: 15, tilt: 60),
```
For real 3D terrain, add a `raster-dem` source + `terrain` in a custom style JSON.

## 4. Remove the Mapbox token dependency
Once mobile is on MapLibre/OpenFreeMap, the Mapbox access token in the raster
tile URLs (`three_d_map_mobile.dart`, `trip_screen.dart` 2D layers) is no longer
needed on mobile. Web can stay as-is or also move to MapLibre GL JS later.

## 5. Verify
- `flutter analyze`
- Push to a branch → the **Mobile Build** CI proves the native link works.
- Then test the APK on a device (pan/zoom/route render + live vehicle marker).
