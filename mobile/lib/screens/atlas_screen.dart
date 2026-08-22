import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

/// "Atlas" — a personal travel map plotting every place from the user's saved
/// trips, with lightweight travel statistics. Read-only, Mapbox-rendered.
class AtlasScreen extends StatefulWidget {
  const AtlasScreen({super.key});
  @override
  State<AtlasScreen> createState() => _AtlasScreenState();
}

class _AtlasScreenState extends State<AtlasScreen> {
  final _api = ApiService();
  bool _loading = true;
  String? _error;

  final List<LatLng> _points = [];
  int _tripCount = 0;
  double _totalKm = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      setState(() {
        _error = 'Log in to see your travel atlas.';
        _loading = false;
      });
      return;
    }
    try {
      final trips = await _api.getSavedTrips(session.accessToken);
      const distance = Distance();
      final pts = <LatLng>[];
      double km = 0;
      for (final t in trips) {
        final sp = t['start_point'];
        final ep = t['end_point'];
        final stops = (t['trip_stops'] as List?) ?? [];
        final route = <LatLng>[];
        if (sp is Map && sp['lat'] != null && sp['lng'] != null) {
          route.add(LatLng((sp['lat'] as num).toDouble(), (sp['lng'] as num).toDouble()));
        }
        for (final s in stops) {
          if (s is Map && s['lat'] != null && s['lng'] != null) {
            route.add(LatLng((s['lat'] as num).toDouble(), (s['lng'] as num).toDouble()));
          }
        }
        if (ep is Map && ep['lat'] != null && ep['lng'] != null) {
          route.add(LatLng((ep['lat'] as num).toDouble(), (ep['lng'] as num).toDouble()));
        }
        pts.addAll(route);
        for (int i = 0; i < route.length - 1; i++) {
          km += distance(route[i], route[i + 1]) / 1000.0;
        }
      }
      if (!mounted) return;
      setState(() {
        _points
          ..clear()
          ..addAll(pts);
        _tripCount = trips.length;
        _totalKm = km;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'Could not load your trips.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final token = AppConfig.mapboxToken;
    final tileUrl = token.isNotEmpty
        ? 'https://api.mapbox.com/styles/v1/mapbox/dark-v11/tiles/256/{z}/{x}/{y}?access_token=$token'
        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

    return Scaffold(
      backgroundColor: Voy.bg,
      appBar: AppBar(
        title: const Text('My Atlas', style: TextStyle(color: Voy.ink, fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.public_off_rounded, size: 54, color: Voy.sub.withValues(alpha: 0.5)),
                        const SizedBox(height: 14),
                        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Voy.sub)),
                      ],
                    ),
                  ),
                )
              : Stack(
                  children: [
                    FlutterMap(
                      options: MapOptions(
                        initialCameraFit: _points.length > 1
                            ? CameraFit.bounds(
                                bounds: LatLngBounds.fromPoints(_points),
                                padding: const EdgeInsets.all(56),
                              )
                            : null,
                        initialCenter: _points.isNotEmpty ? _points.first : const LatLng(20.5937, 78.9629),
                        initialZoom: _points.length == 1 ? 10 : 4,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: tileUrl,
                          userAgentPackageName: 'com.example.travel_app',
                          additionalOptions: {'accessToken': token},
                        ),
                        MarkerLayer(
                          markers: [
                            for (final p in _points)
                              Marker(
                                point: p,
                                width: 18,
                                height: 18,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Voy.brand,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                    boxShadow: [BoxShadow(color: Voy.brand.withValues(alpha: 0.6), blurRadius: 8)],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Voy.surface.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Voy.hairline),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _stat(Icons.route_rounded, '$_tripCount', 'Trips'),
                            _stat(Icons.place_rounded, '${_points.length}', 'Places'),
                            _stat(Icons.straighten_rounded, '${_totalKm.toStringAsFixed(0)} km', 'Distance'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _stat(IconData icon, String value, String label) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Voy.brand, size: 20),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.w800, fontSize: 16)),
          Text(label, style: const TextStyle(color: Voy.sub, fontSize: 11.5)),
        ],
      );
}
