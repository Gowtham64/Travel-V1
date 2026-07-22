import 'package:flutter/material.dart';
import '../models/car_mode_models.dart';

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

  @override
  Widget build(BuildContext context) {
    final cardBg = _isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    final textColor = _isDarkMode ? Colors.white : Colors.black87;
    final subTextColor = _isDarkMode ? Colors.white70 : Colors.black54;

    return PointerInterceptor(
      child: Container(
        color: Colors.transparent,
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // --- TOP MANEUVER BANNER ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                    border: Border.all(
                      color: const Color(0xFF10B981).withOpacity(0.6),
                      width: 2,
                    ),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Large Maneuver Icon Box
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          widget.maneuver.icon,
                          size: 42,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Instruction Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.maneuver.formattedDistance,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF10B981),
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              widget.maneuver.instruction,
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      // Exit Car Mode Button
                      IconButton(
                        onPressed: widget.onExitCarMode,
                        icon: const Icon(Icons.close_rounded, size: 28),
                        color: Colors.redAccent,
                        tooltip: 'Exit Car Mode',
                      ),
                    ],
                  ),
                ),
              ),

              // --- MIDDLE SPACING / TELEMETRY BADGES ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Speedometer Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${widget.telemetry.speedKmh.round()}',
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              color: textColor,
                            ),
                          ),
                          Text(
                            'KM/H',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: subTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Warnings & Next Stop Badges
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (widget.telemetry.hasTollAhead)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade900,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.toll, size: 16, color: Colors.white),
                                SizedBox(width: 6),
                                Text(
                                  'Toll Ahead',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (widget.telemetry.needsRefuel)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade900,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.local_gas_station, size: 16, color: Colors.white),
                                SizedBox(width: 6),
                                Text(
                                  'Refuel Needed',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // --- BOTTOM CONTROL BAR & ETA TELEMETRY ---
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 20,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ETA & Distance Readout
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.schedule, color: Color(0xFF10B981), size: 22),
                              const SizedBox(width: 8),
                              Text(
                                widget.telemetry.formattedEta,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${widget.telemetry.remainingDistanceKm.toStringAsFixed(1)} km left',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: subTextColor,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // Driver Action Buttons (Extra Large 60dp targets)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Play / Pause Simulation
                          _DriverButton(
                            icon: widget.isPlayingAnimation ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            label: widget.isPlayingAnimation ? 'Pause' : 'Drive',
                            onTap: widget.onTogglePlayPause,
                            color: const Color(0xFF3B82F6),
                          ),

                          // Voice Guidance Mute / Unmute
                          _DriverButton(
                            icon: widget.speechMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                            label: widget.speechMuted ? 'Muted' : 'Voice',
                            onTap: widget.onToggleMute,
                            color: widget.speechMuted ? Colors.grey : const Color(0xFF10B981),
                          ),

                          // Recenter Map
                          _DriverButton(
                            icon: Icons.my_location_rounded,
                            label: 'Center',
                            onTap: widget.onRecenterMap,
                            color: const Color(0xFF8B5CF6),
                          ),

                          // Day / Night Theme Toggle
                          _DriverButton(
                            icon: _isDarkMode ? Icons.wb_sunny_rounded : Icons.nightlight_round,
                            label: _isDarkMode ? 'Day' : 'Night',
                            onTap: () {
                              setState(() {
                                _isDarkMode = !_isDarkMode;
                              });
                            },
                            color: Colors.amber.shade700,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriverButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _DriverButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Wrapper for Web Pointer Events intercept
class PointerInterceptor extends StatelessWidget {
  final Widget child;
  const PointerInterceptor({super.key, required this.child});
  @override
  Widget build(BuildContext context) => child;
}
