import 'package:flutter/material.dart';
import '../services/trip_reminder_service.dart';
import '../utils/trip_date_time.dart';

/// Modal dialog presented when a scheduled trip reaches its departure time.
/// Allows the user to either start navigation immediately or postpone.
class TripStartDialog extends StatefulWidget {
  final TripDepartureReminder reminder;
  final VoidCallback? onStartNavigation;
  final void Function(Duration duration)? onPostponed;

  const TripStartDialog({
    super.key,
    required this.reminder,
    this.onStartNavigation,
    this.onPostponed,
  });

  /// Shows the dialog globally using a Navigator context.
  static Future<void> show(
    BuildContext context,
    TripDepartureReminder reminder, {
    VoidCallback? onStartNavigation,
    void Function(Duration duration)? onPostponed,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TripStartDialog(
        reminder: reminder,
        onStartNavigation: onStartNavigation,
        onPostponed: onPostponed,
      ),
    );
  }

  @override
  State<TripStartDialog> createState() => _TripStartDialogState();
}

class _TripStartDialogState extends State<TripStartDialog> {
  bool _showingPostponeOptions = false;
  bool _isProcessing = false;

  Future<void> _handleStart() async {
    setState(() => _isProcessing = true);
    await TripReminderService.instance.startTrip(widget.reminder.id);
    if (!mounted) return;
    Navigator.of(context).pop();
    if (widget.onStartNavigation != null) {
      widget.onStartNavigation!();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Starting navigation to ${widget.reminder.destination}…'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    }
  }

  Future<void> _handlePostpone(Duration duration) async {
    setState(() => _isProcessing = true);
    final updated = await TripReminderService.instance.postponeTrip(widget.reminder.id, duration);
    if (!mounted) return;
    Navigator.of(context).pop();
    if (widget.onPostponed != null) {
      widget.onPostponed!(duration);
    }
    final formattedTime = updated != null
        ? TripDateTime.formatFullDisplay(updated.departureTime)
        : 'new time';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Trip postponed to $formattedTime. Reminder rescheduled!'),
        backgroundColor: const Color(0xFF6366F1),
      ),
    );
  }

  Future<void> _pickCustomTime() async {
    final now = DateTime.now();
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 45))),
      helpText: 'Select new departure time',
    );
    if (pickedTime == null || !mounted) return;

    DateTime target = DateTime(
      now.year,
      now.month,
      now.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    if (target.isBefore(now)) {
      target = target.add(const Duration(days: 1));
    }
    final diff = target.difference(now);
    await _handlePostpone(diff);
  }

  @override
  Widget build(BuildContext context) {
    const bgDark = Color(0xFF111827);
    const surfaceDark = Color(0xFF1F2937);
    const brandEmerald = Color(0xFF10B981);
    const accentIndigo = Color(0xFF6366F1);

    final r = widget.reminder;
    final formattedTime = TripDateTime.formatFullDisplay(r.departureTime);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        decoration: BoxDecoration(
          color: bgDark,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 32,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header banner
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF064E3B), Color(0xFF065F46)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: brandEmerald.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: brandEmerald.withValues(alpha: 0.4)),
                      ),
                      child: const Center(
                        child: Text('🚗', style: TextStyle(fontSize: 22)),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your trip is ready to start!',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Departure time has arrived',
                            style: TextStyle(
                              color: Color(0xFF6EE7B7),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Content body
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Trip route info card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: surfaceDark,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.navigation_rounded, color: brandEmerald, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  r.startPoint.isNotEmpty && r.startPoint != 'Home'
                                      ? '${r.startPoint} → ${r.destination}'
                                      : r.destination,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Divider(height: 1, color: Colors.white12),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.schedule_rounded, color: Colors.white60, size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    formattedTime,
                                    style: const TextStyle(
                                      color: Color(0xFFD1D5DB),
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              if (r.distanceKm > 0)
                                Row(
                                  children: [
                                    const Icon(Icons.straighten_rounded, color: Colors.white60, size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${r.distanceKm.toStringAsFixed(0)} km',
                                      style: const TextStyle(
                                        color: Color(0xFFD1D5DB),
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          if (r.stops.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.place_outlined, color: Colors.white60, size: 14),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${r.stops.length} stop${r.stops.length == 1 ? '' : 's'}: ${r.stops.take(3).join(', ')}${r.stops.length > 3 ? '…' : ''}',
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 11.5,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Actions or Postpone options
                    if (!_showingPostponeOptions) ...[
                      // Primary CTA: Start Navigation
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing ? null : _handleStart,
                          icon: _isProcessing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.navigation_rounded, color: Colors.white, size: 18),
                          label: const Text(
                            'Start Navigation',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: brandEmerald,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Secondary CTA: Need More Time
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: _isProcessing
                              ? null
                              : () => setState(() => _showingPostponeOptions = true),
                          icon: const Icon(Icons.more_time_rounded, color: Color(0xFF9CA3AF), size: 17),
                          label: const Text(
                            'Need More Time',
                            style: TextStyle(
                              color: Color(0xFFD1D5DB),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      // Postpone Options Menu
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Postpone departure by:',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() => _showingPostponeOptions = false),
                            icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _postponePill('+15 mins', const Duration(minutes: 15)),
                          _postponePill('+30 mins', const Duration(minutes: 30)),
                          _postponePill('+1 hour', const Duration(hours: 1)),
                          _postponePill('+2 hours', const Duration(hours: 2)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: OutlinedButton.icon(
                          onPressed: _isProcessing ? null : _pickCustomTime,
                          icon: const Icon(Icons.access_time_rounded, color: accentIndigo, size: 16),
                          label: const Text(
                            'Custom Time…',
                            style: TextStyle(
                              color: Color(0xFFA5B4FC),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF4F46E5)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _postponePill(String label, Duration duration) {
    return InkWell(
      onTap: _isProcessing ? null : () => _handlePostpone(duration),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF374151),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
