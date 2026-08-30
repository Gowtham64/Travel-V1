import 'package:flutter/material.dart';
import '../models/car_mode_models.dart';

/// A fullscreen, CarPlay-style driving overlay drawn on top of the map.
///
/// Layout mirrors Apple Maps in CarPlay: a maneuver card pinned to a top
/// corner, a speed pill, small alert chips, and a rounded status/control bar
/// along the bottom. It adapts between a landscape (dash) layout and a
/// portrait (phone) layout.
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

  // Apple-flavoured system colours.
  static const _green = Color(0xFF30D158);
  static const _blue = Color(0xFF0A84FF);
  static const _purple = Color(0xFFBF5AF2);
  static const _red = Color(0xFFFF453A);
  static const _amber = Color(0xFFFFD60A);

  Color get _panel => _isDarkMode ? const Color(0xF21C1C1E) : const Color(0xF2F2F2F7);
  Color get _text => _isDarkMode ? Colors.white : const Color(0xFF1C1C1E);
  Color get _sub => _isDarkMode ? Colors.white70 : const Color(0xFF3A3A3C);
  Color get _hairline => _isDarkMode ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08);

  @override
  Widget build(BuildContext context) {
    return PointerInterceptor(
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 720;
          return SafeArea(
            child: Stack(
              children: [
                // Maneuver card — top-left (landscape) / top full-width (portrait).
                Positioned(
                  top: 14,
                  left: 14,
                  right: wide ? null : 14,
                  width: wide ? (c.maxWidth * 0.42).clamp(320.0, 460.0) : null,
                  child: _maneuverCard(),
                ),

                // Speed pill + alert chips — top-right.
                Positioned(
                  top: 14,
                  right: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // In portrait the maneuver card spans the full width, so
                      // keep the speed pill below it to avoid overlap.
                      if (wide) _speedPill(),
                      if (wide) const SizedBox(height: 10),
                      ..._alertChips(),
                    ],
                  ),
                ),

                // Bottom status + control bar.
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 14,
                  child: _bottomBar(wide),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---- Maneuver card -------------------------------------------------------

  Widget _maneuverCard() {
    // Show the road name as a subtitle only when it adds information the
    // instruction line doesn't already carry.
    final road = widget.maneuver.roadName;
    final showRoad = road != null &&
        road.trim().isNotEmpty &&
        !widget.maneuver.instruction.toLowerCase().contains(road.toLowerCase());
    return _card(
      padding: const EdgeInsets.all(16),
      accentBorder: true,
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _green,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(widget.maneuver.icon, size: 46, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.maneuver.formattedDistance,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: _green,
                    letterSpacing: 0.3,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.maneuver.instruction,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _text),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (showRoad) ...[
                  const SizedBox(height: 2),
                  Text(
                    'on $road',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _sub),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Speed pill ----------------------------------------------------------

  Widget _speedPill() {
    return Container(
      width: 76,
      height: 76,
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
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: _text, height: 1.0),
          ),
          Text('km/h', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _sub)),
        ],
      ),
    );
  }

  // ---- Alert chips ---------------------------------------------------------

  List<Widget> _alertChips() {
    final chips = <Widget>[];
    if (widget.telemetry.hasTollAhead) {
      chips.add(_chip(Icons.toll, 'Toll ahead', _amber));
    }
    if (widget.telemetry.needsRefuel) {
      chips.add(_chip(Icons.local_gas_station, 'Refuel', const Color(0xFFFF9F0A)));
    }
    return chips
        .map((w) => Padding(padding: const EdgeInsets.only(top: 8), child: w))
        .toList();
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: _shadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.black87),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87)),
        ],
      ),
    );
  }

  // ---- Bottom status + controls -------------------------------------------

  Widget _bottomBar(bool wide) {
    final buttons = _controlButtons();

    return _card(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: wide
          ? Row(
              children: [
                Expanded(child: _etaBlock()),
                const SizedBox(width: 12),
                buttons,
              ],
            )
          // Portrait: speed pill lives inside the bar (left of the ETA) so it
          // can't collide with anything on the map.
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _speedPill(),
                    const SizedBox(width: 14),
                    Expanded(child: _etaBlock()),
                  ],
                ),
                const SizedBox(height: 14),
                buttons,
              ],
            ),
    );
  }

  /// Wall-clock arrival time, e.g. "3:45 PM", from the remaining duration.
  String get _arrivalClock {
    final arrive = DateTime.now().add(Duration(minutes: widget.telemetry.remainingDurationMin));
    final h24 = arrive.hour;
    final period = h24 >= 12 ? 'PM' : 'AM';
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    final mm = arrive.minute.toString().padLeft(2, '0');
    return '$h12:$mm $period';
  }

  Widget _etaBlock() {
    // "Arriving" state once we're basically on top of the destination.
    final arriving = widget.telemetry.remainingDistanceKm < 0.15;
    final progress = widget.telemetry.progressPercent.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(arriving ? Icons.pin_drop_rounded : Icons.navigation_rounded, color: _green, size: 26),
            const SizedBox(width: 12),
            if (arriving)
              Text('Arriving',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _green, height: 1.0))
            else ...[
              Text(
                widget.telemetry.formattedEta,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _text, height: 1.0),
              ),
              const SizedBox(width: 10),
              Text('· $_arrivalClock',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _sub)),
            ],
          ],
        ),
        const SizedBox(height: 8),
        // Route progress bar.
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: _hairline,
            valueColor: AlwaysStoppedAnimation<Color>(_green),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${widget.telemetry.remainingDistanceKm.toStringAsFixed(1)} km left · ${(progress * 100).round()}%',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _sub),
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
          tooltip: 'Recenter',
        ),
        _circleBtn(
          icon: _isDarkMode ? Icons.wb_sunny_rounded : Icons.nightlight_round,
          color: _amber,
          onTap: () => setState(() => _isDarkMode = !_isDarkMode),
          tooltip: _isDarkMode ? 'Day' : 'Night',
        ),
        _circleBtn(
          icon: Icons.close_rounded,
          color: _red,
          onTap: widget.onExitCarMode,
          tooltip: 'End',
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
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Tooltip(
        message: tooltip,
        child: InkResponse(
          onTap: onTap,
          radius: 34,
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: filled ? color : color.withOpacity(0.18),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
            child: Icon(icon, color: filled ? Colors.white : color, size: 26),
          ),
        ),
      ),
    );
  }

  // ---- Shared card chrome --------------------------------------------------

  Widget _card({required Widget child, required EdgeInsets padding, bool accentBorder = false}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: accentBorder ? _green.withOpacity(0.55) : _hairline,
          width: accentBorder ? 2 : 1,
        ),
        boxShadow: _shadow,
      ),
      child: child,
    );
  }

  List<BoxShadow> get _shadow => [
        BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 6)),
      ];
}

// Wrapper for Web Pointer Events intercept (no-op placeholder).
class PointerInterceptor extends StatelessWidget {
  final Widget child;
  const PointerInterceptor({super.key, required this.child});
  @override
  Widget build(BuildContext context) => child;
}
