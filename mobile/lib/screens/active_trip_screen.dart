import 'package:flutter/material.dart';
import '../models/trip_extras.dart';
import '../services/trip_extras_store.dart';
import '../theme/app_theme.dart';

/// Live "active trip" view: once a trip is started, this focuses on the current
/// day's plan as a checkable timeline — what's next, and each stop tickable as
/// you go. Progress persists per trip. The traveller can browse other days.
class ActiveTripScreen extends StatefulWidget {
  final TripExtrasStore store;
  final List<PlanDay> days;
  final DateTime startedAt;
  final String tripName;

  const ActiveTripScreen({
    super.key,
    required this.store,
    required this.days,
    required this.startedAt,
    required this.tripName,
  });

  @override
  State<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends State<ActiveTripScreen> {
  late List<PlanDay> _days;
  late int _dayIndex;

  @override
  void initState() {
    super.initState();
    _days = widget.days;
    _dayIndex = _todayIndex();
  }

  /// Which day of the trip "today" is, based on the start date. Clamped to the
  /// available days so an early or late viewing still lands on a real day.
  int _todayIndex() {
    if (_days.isEmpty) return 0;
    final start = DateTime(widget.startedAt.year, widget.startedAt.month, widget.startedAt.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(start).inDays;
    return diff.clamp(0, _days.length - 1);
  }

  bool get _isToday => _dayIndex == _todayIndex();

  DateTime _dateForDay(int i) => DateTime(widget.startedAt.year, widget.startedAt.month, widget.startedAt.day)
      .add(Duration(days: i));

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  String _fmtDate(DateTime d) => '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

  List<PlanItem> _sortedItems(PlanDay day) {
    final items = [...day.items];
    items.sort((a, b) {
      if (a.time.isEmpty && b.time.isEmpty) return 0;
      if (a.time.isEmpty) return 1;
      if (b.time.isEmpty) return -1;
      return a.time.compareTo(b.time);
    });
    return items;
  }

  void _toggle(PlanItem item) {
    setState(() => item.done = !item.done);
    widget.store.saveDays(_days, name: widget.tripName);
  }

  Future<void> _endTrip() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Voy.surface,
        title: const Text('End trip?', style: TextStyle(color: Voy.ink)),
        content: const Text('This exits active-trip mode. Your plan and ticked-off stops are kept.',
            style: TextStyle(color: Voy.sub)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('End trip', style: TextStyle(color: Voy.danger))),
        ],
      ),
    );
    if (ok == true) {
      await widget.store.saveStartedAt(null);
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final day = _days.isEmpty ? null : _days[_dayIndex.clamp(0, _days.length - 1)];
    final items = day == null ? <PlanItem>[] : _sortedItems(day);
    final doneCount = items.where((i) => i.done).length;
    final nextItem = items.where((i) => !i.done).cast<PlanItem?>().firstWhere((_) => true, orElse: () => null);

    return Scaffold(
      backgroundColor: Voy.bg,
      appBar: AppBar(
        backgroundColor: Voy.surface,
        foregroundColor: Voy.ink,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Active trip', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text(widget.tripName, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: Voy.sub, fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _endTrip,
            icon: const Icon(Icons.stop_circle_outlined, size: 18, color: Voy.danger),
            label: const Text('End', style: TextStyle(color: Voy.danger)),
          ),
        ],
      ),
      body: _days.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No days planned yet.', style: TextStyle(color: Voy.sub))))
          : Column(
              children: [
                _dayBar(day!),
                if (nextItem != null) _nextUpBanner(nextItem),
                Expanded(
                  child: items.isEmpty
                      ? const Center(child: Text('Nothing planned for this day.', style: TextStyle(color: Voy.sub)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                          itemCount: items.length,
                          itemBuilder: (_, i) => _itemRow(items[i], isNext: identical(items[i], nextItem)),
                        ),
                ),
                _progressFooter(doneCount, items.length),
              ],
            ),
    );
  }

  Widget _dayBar(PlanDay day) {
    return Container(
      color: Voy.surface,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: _dayIndex > 0 ? () => setState(() => _dayIndex--) : null,
            icon: const Icon(Icons.chevron_left_rounded, color: Voy.ink),
          ),
          Expanded(
            child: Column(
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('Day ${_dayIndex + 1} of ${_days.length}',
                      style: const TextStyle(color: Voy.ink, fontSize: 15, fontWeight: FontWeight.w800)),
                  if (_isToday) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Voy.brand.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                      child: const Text('TODAY', style: TextStyle(color: Voy.brand, fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ]),
                const SizedBox(height: 2),
                Text('${_fmtDate(_dateForDay(_dayIndex))} · ${day.title}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Voy.sub, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            onPressed: _dayIndex < _days.length - 1 ? () => setState(() => _dayIndex++) : null,
            icon: const Icon(Icons.chevron_right_rounded, color: Voy.ink),
          ),
        ],
      ),
    );
  }

  Widget _nextUpBanner(PlanItem item) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Voy.brand.withValues(alpha: 0.22), Voy.violet.withValues(alpha: 0.18)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Voy.brand.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        const Icon(Icons.navigation_rounded, color: Voy.brand),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('NEXT UP', style: TextStyle(color: Voy.brand, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
            const SizedBox(height: 2),
            Text([if (item.time.isNotEmpty) item.time, item.text].join('  '),
                style: const TextStyle(color: Voy.ink, fontSize: 15, fontWeight: FontWeight.w700)),
            if (item.note.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 2), child: Text(item.note, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Voy.sub, fontSize: 12.5))),
          ]),
        ),
        FilledButton(
          onPressed: () => _toggle(item),
          style: FilledButton.styleFrom(backgroundColor: Voy.brand, foregroundColor: const Color(0xFF04211F)),
          child: const Text('Done'),
        ),
      ]),
    );
  }

  IconData _catIcon(String c) {
    switch (c) {
      case 'restaurant':
        return Icons.restaurant_rounded;
      case 'stay':
        return Icons.hotel_rounded;
      case 'activity':
        return Icons.local_activity_rounded;
      default:
        return Icons.place_rounded;
    }
  }

  Widget _itemRow(PlanItem item, {required bool isNext}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isNext ? Voy.brand.withValues(alpha: 0.08) : Voy.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isNext ? Voy.brand.withValues(alpha: 0.45) : Voy.hairline),
      ),
      child: ListTile(
        onTap: () => _toggle(item),
        leading: SizedBox(
          width: 54,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(item.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: item.done ? Voy.success : Voy.sub, size: 22),
            const SizedBox(width: 4),
            Icon(_catIcon(item.category), size: 16, color: Voy.sub),
          ]),
        ),
        title: Text(item.text,
            style: TextStyle(
              color: item.done ? Voy.sub : Voy.ink,
              fontWeight: FontWeight.w600,
              decoration: item.done ? TextDecoration.lineThrough : null,
            )),
        subtitle: (item.time.isEmpty && item.note.isEmpty)
            ? null
            : Text([if (item.time.isNotEmpty) item.time, if (item.note.isNotEmpty) item.note].join(' · '),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Voy.sub, fontSize: 12)),
      ),
    );
  }

  Widget _progressFooter(int done, int total) {
    final pct = total == 0 ? 0.0 : done / total;
    return Container(
      color: Voy.surface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('$done of $total done', style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${(pct * 100).round()}%', style: const TextStyle(color: Voy.brand, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: pct, minHeight: 8, backgroundColor: Voy.hairline, color: Voy.brand),
          ),
        ],
      ),
    );
  }
}
