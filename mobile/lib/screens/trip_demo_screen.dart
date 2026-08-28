import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/app_config.dart';
import '../widgets/app_design.dart';

/// One located stop in the demo playback.
class DemoStop {
  final String dayLabel;
  final String time;
  final String name;
  final String category;
  final LatLng point;
  const DemoStop({required this.dayLabel, required this.time, required this.name, required this.category, required this.point});
}

/// A cinematic "demo" of a saved trip: a marker travels stop-to-stop through the
/// itinerary while the camera follows and a card narrates each stop.
class TripDemoScreen extends StatefulWidget {
  final List<DemoStop> stops;
  final String tripName;
  const TripDemoScreen({super.key, required this.stops, required this.tripName});

  @override
  State<TripDemoScreen> createState() => _TripDemoScreenState();
}

class _TripDemoScreenState extends State<TripDemoScreen> with SingleTickerProviderStateMixin {
  final _map = MapController();
  late final AnimationController _ctrl;
  int _seg = 0; // travelling from stops[_seg] to stops[_seg+1]
  bool _playing = true;
  bool _done = false;
  Timer? _pause;
  late LatLng _marker;

  List<DemoStop> get _stops => widget.stops;

  @override
  void initState() {
    super.initState();
    _marker = _stops.first.point;
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
      ..addListener(_tick)
      ..addStatusListener(_onStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _safeMove(_stops.first.point, 13.0);
      if (_stops.length > 1) _ctrl.forward();
      else setState(() { _playing = false; _done = true; });
    });
  }

  @override
  void dispose() {
    _pause?.cancel();
    _ctrl.dispose();
    _map.dispose();
    super.dispose();
  }

  void _safeMove(LatLng p, double z) {
    try { _map.move(p, z); } catch (_) {}
  }

  void _tick() {
    if (_seg >= _stops.length - 1) return;
    final a = _stops[_seg].point;
    final b = _stops[_seg + 1].point;
    final t = Curves.easeInOut.transform(_ctrl.value);
    final here = LatLng(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t);
    setState(() => _marker = here);
    _safeMove(here, 13.0);
  }

  void _onStatus(AnimationStatus s) {
    if (s != AnimationStatus.completed) return;
    if (_seg >= _stops.length - 2) {
      setState(() { _done = true; _playing = false; });
      return;
    }
    // Brief pause "at" the stop before moving on.
    setState(() => _seg += 1);
    _pause = Timer(const Duration(milliseconds: 900), () {
      if (mounted && _playing) _ctrl.forward(from: 0);
    });
  }

  void _togglePlay() {
    setState(() => _playing = !_playing);
    if (_playing) {
      if (_done) { _restart(); return; }
      _ctrl.forward();
    } else {
      _ctrl.stop();
      _pause?.cancel();
    }
  }

  void _restart() {
    _pause?.cancel();
    setState(() { _seg = 0; _done = false; _playing = true; _marker = _stops.first.point; });
    _safeMove(_stops.first.point, 13.0);
    _ctrl.forward(from: 0);
  }

  Color _catColor(String c) {
    switch (c) {
      case 'restaurant': return const Color(0xFFF97316);
      case 'stay': return const Color(0xFF8B5CF6);
      case 'activity': return const Color(0xFF22C55E);
      default: return AppColors.accentLight;
    }
  }

  IconData _catIcon(String c) {
    switch (c) {
      case 'restaurant': return Icons.restaurant_rounded;
      case 'stay': return Icons.hotel_rounded;
      case 'activity': return Icons.local_activity_rounded;
      default: return Icons.place_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    // The stop we're heading toward (or the last one when finished).
    final target = _stops[(_seg + (_done ? 0 : 1)).clamp(0, _stops.length - 1)];
    final token = AppConfig.mapboxToken;
    final tileUrl = token.isNotEmpty
        ? 'https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/tiles/256/{z}/{x}/{y}?access_token=$token'
        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

    return Scaffold(
      backgroundColor: AppColors.obsidian,
      appBar: AppBar(
        backgroundColor: AppColors.slate,
        foregroundColor: Colors.white,
        title: Text('Demo · ${widget.tripName}', overflow: TextOverflow.ellipsis),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _stops.first.point,
              initialZoom: 13,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
            ),
            children: [
              TileLayer(urlTemplate: tileUrl, userAgentPackageName: 'com.voyplan.app'),
              PolylineLayer(polylines: [
                Polyline(points: _stops.map((s) => s.point).toList(), strokeWidth: 4, color: AppColors.accentLight.withValues(alpha: 0.7)),
              ]),
              MarkerLayer(markers: [
                for (int i = 0; i < _stops.length; i++)
                  Marker(
                    point: _stops[i].point, width: 26, height: 26,
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: (i <= _seg ? _catColor(_stops[i].category) : Colors.white24),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                  ),
                // Moving marker
                Marker(
                  point: _marker, width: 40, height: 40,
                  child: const Icon(Icons.navigation_rounded, color: Color(0xFF2563EB), size: 34),
                ),
              ]),
            ],
          ),
          // Progress bar
          Positioned(
            top: 0, left: 0, right: 0,
            child: LinearProgressIndicator(
              value: _stops.length <= 1 ? 1 : ((_seg + _ctrl.value) / (_stops.length - 1)).clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(AppColors.accentLight),
            ),
          ),
          // Current-stop card + controls
          Positioned(
            left: 16, right: 16, bottom: 24,
            child: GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 36, height: 36, alignment: Alignment.center,
                      decoration: BoxDecoration(color: _catColor(target.category).withValues(alpha: 0.2), shape: BoxShape.circle, border: Border.all(color: _catColor(target.category))),
                      child: Icon(_catIcon(target.category), size: 18, color: _catColor(target.category)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(target.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                        Text('${target.dayLabel}${target.time.isNotEmpty ? ' · ${target.time}' : ''}', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
                      ]),
                    ),
                    Text('${(_seg + (_done ? 1 : 1)).clamp(1, _stops.length)}/${_stops.length}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    IconButton(
                      onPressed: _restart,
                      icon: const Icon(Icons.replay_rounded, color: Colors.white),
                      tooltip: 'Restart',
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _togglePlay,
                      icon: Icon(_done ? Icons.replay_rounded : (_playing ? Icons.pause_rounded : Icons.play_arrow_rounded)),
                      label: Text(_done ? 'Replay' : (_playing ? 'Pause' : 'Play')),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
