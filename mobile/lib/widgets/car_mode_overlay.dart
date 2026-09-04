import 'package:flutter/material.dart';
import '../models/car_mode_models.dart';

/// A fullscreen, modern driving navigation overlay drawn on top of the live map.
/// Works across Web, iOS, and Android with responsive layout, lane guidance,
/// live speed, maneuver card, GPS status, and trip HUD.
class CarModeOverlay extends StatefulWidget {
  final ManeuverInstruction maneuver;
  final CarTelemetry telemetry;
  final bool isPlayingAnimation;
  final bool speechMuted;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onToggleMute;
  final VoidCallback onRecenterMap;
  final VoidCallback onExitCarMode;

  const CarModeOverlay({
    super.key,
    required this.maneuver,
    required this.telemetry,
    required this.isPlayingAnimation,
    required this.speechMuted,
    required this.onTogglePlayPause,
    required this.onToggleMute,
    required this.onRecenterMap,
    required this.onExitCarMode,
  });

  @override
  State<CarModeOverlay> createState() => _CarModeOverlayState();
}

class _CarModeOverlayState extends State<CarModeOverlay> {
  bool _isDarkMode = true;

  static const _green = Color(0xFF10B981);
  static const _blue = Color(0xFF0EA5E9);
  static const _purple = Color(0xFF8B5CF6);
  static const _red = Color(0xFFEF4444);
  static const _amber = Color(0xFFF59E0B);
  static const _teal = Color(0xFF14B8A6);

  Color get _panel => _isDarkMode ? const Color(0xEE111827) : const Color(0xEEF9FAFB);
  Color get _text => _isDarkMode ? Colors.white : const Color(0xFF111827);
  Color get _sub => _isDarkMode ? Colors.white70 : const Color(0xFF4B5563);
  Color get _hairline => _isDarkMode ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08);

  @override
  Widget build(BuildContext context) {
    return PointerInterceptor(
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 720;
          return SafeArea(
            child: Stack(
              children: [
                // 1. Top Maneuver & Lane Guidance Banner
                Positioned(
                  top: 12,
                  left: 14,
                  right: wide ? null : 14,
                  width: wide ? (c.maxWidth * 0.45).clamp(340.0, 480.0) : null,
                  child: _maneuverCard(),
                ),

                // 2. Top-Right: Speedometer + Status Chips
                Positioned(
                  top: 12,
                  right: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (wide) _speedometer(),
                      const SizedBox(height: 8),
                      ..._statusChips(),
                    ],
                  ),
                ),

                // 3. Bottom HUD Bar (Remaining Distance, Time, ETA, Controls)
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: _bottomBar(wide),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---- Maneuver & Lane Guidance --------------------------------------------

  Widget _maneuverCard() {
    final road = widget.maneuver.roadName;
    final showRoad = road != null &&
        road.trim().isNotEmpty &&
        !widget.maneuver.instruction.toLowerCase().contains(road.toLowerCase());
    final hasLanes = widget.maneuver.laneGuidance != null &&
        widget.maneuver.laneGuidance!.lanes.isNotEmpty;

    return _card(
      padding: const EdgeInsets.all(14),
      accentBorder: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_teal, _green],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: _green.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(widget.maneuver.icon, size: 40, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.maneuver.formattedDistance,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: _green,
                        letterSpacing: 0.3,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.maneuver.instruction,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _text,
                        height: 1.15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (showRoad) ...[
                      const SizedBox(height: 2),
                      Text(
                        'on $road',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _sub),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          // Lane Guidance Visualizer
          if (hasLanes) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _hairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < widget.maneuver.laneGuidance!.lanes.length; i++) ...[
                    _lanePill(widget.maneuver.laneGuidance!.lanes[i], isRecommended: i == widget.maneuver.laneGuidance!.recommendedIndex),
                    if (i < widget.maneuver.laneGuidance!.lanes.length - 1)
                      const SizedBox(width: 6),
                  ],
                  if (widget.maneuver.laneGuidance!.instruction != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.maneuver.laneGuidance!.instruction!,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _sub),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _lanePill(LaneInfo lane, {bool isRecommended = false}) {
    final active = lane.active || isRecommended;
    final color = active ? _green : (lane.valid ? Colors.white70 : Colors.white24);
    final bgColor = active ? _green.withValues(alpha: 0.22) : Colors.transparent;
    final borderColor = active ? _green : _hairline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: active ? 1.5 : 1.0),
      ),
      child: Icon(lane.icon, size: 20, color: color),
    );
  }

  // ---- Speedometer ---------------------------------------------------------

  Widget _speedometer() {
    return Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        color: _panel,
        shape: BoxShape.circle,
        border: Border.all(color: _hairline),
        boxShadow: _shadow,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${widget.telemetry.speedKmh.round()}',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: _text, height: 1.0),
          ),
          const SizedBox(height: 2),
          Text(
            widget.telemetry.speedUnit,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _sub),
          ),
        ],
      ),
    );
  }

  // ---- Status & Alert Chips ------------------------------------------------

  List<Widget> _statusChips() {
    final chips = <Widget>[];

    // Rerouting banner
    if (widget.telemetry.isRerouting) {
      chips.add(_chip(Icons.alt_route_rounded, '⚡ Rerouting…', _blue, textColor: Colors.white));
    }

    // GPS Status alerts
    if (widget.telemetry.gpsStatus == GpsHealthStatus.searching ||
        widget.telemetry.gpsStatus == GpsHealthStatus.lost) {
      chips.add(_chip(Icons.gps_not_fixed_rounded, 'Searching for GPS…', _amber, textColor: Colors.black87));
    } else if (widget.telemetry.gpsStatus == GpsHealthStatus.weak) {
      chips.add(_chip(Icons.gps_fixed_rounded, 'Weak GPS signal', _amber, textColor: Colors.black87));
    }

    // Next stop chip
    if (widget.telemetry.nextStopName != null && widget.telemetry.nextStopName!.isNotEmpty) {
      chips.add(_chip(Icons.flag_rounded, 'Next: ${widget.telemetry.nextStopName}', _purple, textColor: Colors.white));
    }

    if (widget.telemetry.hasTollAhead) {
      chips.add(_chip(Icons.toll, 'Toll ahead', _amber));
    }
    if (widget.telemetry.needsRefuel) {
      chips.add(_chip(Icons.local_gas_station, 'Refuel needed', const Color(0xFFFF9F0A)));
    }

    return chips
        .map((w) => Padding(padding: const EdgeInsets.only(top: 6), child: w))
        .toList();
  }

  Widget _chip(IconData icon, String label, Color color, {Color textColor = Colors.black87}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        boxShadow: _shadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: textColor)),
        ],
      ),
    );
  }

  // ---- Bottom Navigation Bar ----------------------------------------------

  Widget _bottomBar(bool wide) {
    final buttons = _controlButtons();

    return _card(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: wide
          ? Row(
              children: [
                Expanded(child: _etaBlock()),
                const SizedBox(width: 12),
                buttons,
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _speedometer(),
                    const SizedBox(width: 14),
                    Expanded(child: _etaBlock()),
                  ],
                ),
                const SizedBox(height: 12),
                buttons,
              ],
            ),
    );
  }

  Widget _etaBlock() {
    final arriving = widget.telemetry.remainingDistanceKm < 0.12;
    final progress = widget.telemetry.progressPercent.clamp(0.0, 1.0);
    final clockEta = widget.telemetry.formattedClockEta();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(arriving ? Icons.pin_drop_rounded : Icons.navigation_rounded, color: _green, size: 24),
            const SizedBox(width: 8),
            if (arriving)
              const Text('Arriving at destination',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _green, height: 1.0))
            else ...[
              Text(
                widget.telemetry.formattedEta,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _text, height: 1.0),
              ),
              const SizedBox(width: 8),
              Text('· ETA $clockEta',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _green)),
            ],
          ],
        ),
        const SizedBox(height: 6),
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: _hairline,
            valueColor: const AlwaysStoppedAnimation<Color>(_green),
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Text(
              '${widget.telemetry.remainingDistanceKm.toStringAsFixed(1)} km remaining',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _sub),
            ),
            const Spacer(),
            Text(
              '${(progress * 100).round()}% completed',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _sub),
            ),
          ],
        ),
      ],
    );
  }

  Widget _controlButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _circleBtn(
          icon: widget.isPlayingAnimation ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: _blue,
          onTap: widget.onTogglePlayPause,
          tooltip: widget.isPlayingAnimation ? 'Pause' : 'Drive',
        ),
        _circleBtn(
          icon: widget.speechMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          color: widget.speechMuted ? Colors.grey : _green,
          onTap: widget.onToggleMute,
          tooltip: widget.speechMuted ? 'Voice off' : 'Voice on',
        ),
        _circleBtn(
          icon: Icons.my_location_rounded,
          color: _purple,
          onTap: widget.onRecenterMap,
          tooltip: 'Recenter on vehicle',
        ),
        _circleBtn(
          icon: _isDarkMode ? Icons.wb_sunny_rounded : Icons.nightlight_round,
          color: _amber,
          onTap: () => setState(() => _isDarkMode = !_isDarkMode),
          tooltip: _isDarkMode ? 'Light mode' : 'Dark mode',
        ),
        _circleBtn(
          icon: Icons.close_rounded,
          color: _red,
          onTap: widget.onExitCarMode,
          tooltip: 'End Navigation',
          filled: true,
        ),
      ],
    );
  }

  Widget _circleBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required String tooltip,
    bool filled = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: tooltip,
        child: InkResponse(
          onTap: onTap,
          radius: 30,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: filled ? color : color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 1.8),
            ),
            child: Icon(icon, color: filled ? Colors.white : color, size: 23),
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child, required EdgeInsets padding, bool accentBorder = false}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accentBorder ? _green.withValues(alpha: 0.5) : _hairline,
          width: accentBorder ? 1.8 : 1,
        ),
        boxShadow: _shadow,
      ),
      child: child,
    );
  }

  List<BoxShadow> get _shadow => [
        BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6)),
      ];
}

class PointerInterceptor extends StatelessWidget {
  final Widget child;
  const PointerInterceptor({super.key, required this.child});
  @override
  Widget build(BuildContext context) => child;
}
