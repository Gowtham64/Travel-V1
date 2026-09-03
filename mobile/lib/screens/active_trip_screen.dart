import 'dart:async';
import 'package:flutter/material.dart';
import '../models/trip_extras.dart';
import '../services/api_service.dart';
import '../services/trip_extras_store.dart';
import '../services/auth_guard.dart';
import '../theme/app_theme.dart';
import 'day_planner_screen.dart';

/// Live "active trip" view: once a trip is started, this focuses on the current
/// day's plan as a checkable timeline — what's next, and each stop tickable as
/// you go.
///
/// Travellers can edit the plan on the go:
/// - Add new places (via search or manual entry) with categories, times, and notes.
/// - Edit stop details.
/// - Reorder stops.
/// - Move stops between days.
/// - Add or rename days.
/// - Open the full visual planner workspace and sync back.
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
  final _api = ApiService();
  late List<PlanDay> _days;
  late int _dayIndex;
  bool _isReordering = false;

  static const List<(String, String, IconData)> _categories = [
    ('place', 'Place', Icons.place_rounded),
    ('restaurant', 'Restaurant', Icons.restaurant_rounded),
    ('stay', 'Stay', Icons.hotel_rounded),
    ('activity', 'Activity', Icons.local_activity_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _days = List.from(widget.days);
    _dayIndex = _todayIndex();
  }

  String _uid() => DateTime.now().microsecondsSinceEpoch.toString();

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

  void _persist() {
    widget.store.saveDays(_days, name: widget.tripName);
  }

  void _toggle(PlanItem item) {
    setState(() => item.done = !item.done);
    _persist();
  }

  Future<void> _endTrip() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Voy.surface,
        title: const Text('End trip?', style: TextStyle(color: Voy.ink, fontWeight: FontWeight.bold)),
        content: const Text(
          'This exits active-trip mode. Your plan and ticked-off stops are kept and saved in your history.',
          style: TextStyle(color: Voy.sub),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End trip', style: TextStyle(color: Voy.danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.store.saveStartedAt(null);
      if (mounted) Navigator.pop(context, true);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Editing & adding places on the go
  // ───────────────────────────────────────────────────────────────────────────

  /// Open full DayPlannerScreen to visually edit everything, then reload state
  Future<void> _openFullPlanner() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DayPlannerScreen(
        tripKey: widget.store.tripKey,
        tripName: widget.tripName,
      ),
    ));
    if (!mounted) return;
    final refreshed = await widget.store.loadDays();
    setState(() {
      _days = refreshed;
      if (_dayIndex >= _days.length) {
        _dayIndex = _days.isEmpty ? 0 : _days.length - 1;
      }
    });
  }

  /// Add a new day to the trip
  void _addDay() {
    setState(() {
      _days.add(PlanDay(id: _uid(), title: 'Day ${_days.length + 1}'));
      _dayIndex = _days.length - 1;
    });
    _persist();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added Day ${_days.length} to trip plan'),
        backgroundColor: Voy.surface2,
      ),
    );
  }

  /// Rename the current day
  Future<void> _renameDay(PlanDay day) async {
    final ctrl = TextEditingController(text: day.title);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Voy.surface,
        title: const Text('Rename Day', style: TextStyle(color: Voy.ink)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Voy.ink),
          decoration: const InputDecoration(labelText: 'Day title (e.g. Beaches & Temples)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    setState(() => day.title = text);
    _persist();
  }

  /// Opens the Add Place bottom sheet
  Future<void> _showAddPlaceSheet() async {
    if (!AuthGuard.ensure(context, action: 'edit trip plans')) return;
    if (_days.isEmpty) _addDay();

    int targetDayIndex = _dayIndex;

    final searchCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String category = 'place';
    String time = '';
    bool isSearching = false;
    List<Map<String, String>> searchResults = [];
    String? searchErr;
    int tab = 0; // 0 = Search places, 1 = Custom stop

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Voy.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> runSearch() async {
            final q = searchCtrl.text.trim();
            if (q.isEmpty) return;
            setSheet(() {
              isSearching = true;
              searchErr = null;
            });
            try {
              final res = await _api.aiSearchPlaces(query: q, near: widget.tripName);
              if (!mounted) return;
              setSheet(() => searchResults = res);
            } catch (e) {
              if (!mounted) return;
              setSheet(() => searchErr = e is ApiException ? e.message : 'Search failed. Try custom entry.');
            } finally {
              if (mounted) setSheet(() => isSearching = false);
            }
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (ctx, scroll) => Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 14,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
              ),
              child: ListView(
                controller: scroll,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Voy.sub.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.add_location_alt_rounded, color: Voy.brand, size: 22),
                      const SizedBox(width: 8),
                      const Text(
                        'Add Place to Active Trip',
                        style: TextStyle(color: Voy.ink, fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Voy.sub),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Target Day picker
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Voy.surface2,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Voy.hairline),
                    ),
                    child: Row(
                      children: [
                        const Text('Add to: ', style: TextStyle(color: Voy.sub, fontSize: 13)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: targetDayIndex,
                              isDense: true,
                              dropdownColor: Voy.surface2,
                              style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.bold, fontSize: 13.5),
                              items: [
                                for (int i = 0; i < _days.length; i++)
                                  DropdownMenuItem(
                                    value: i,
                                    child: Text(
                                      'Day ${i + 1} (${_days[i].title})${i == _todayIndex() ? ' · TODAY' : ''}',
                                    ),
                                  ),
                              ],
                              onChanged: (v) {
                                if (v != null) setSheet(() => targetDayIndex = v);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Mode switcher
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('Search Place / Spot')),
                          avatar: const Icon(Icons.search_rounded, size: 16),
                          selected: tab == 0,
                          selectedColor: Voy.brand.withValues(alpha: 0.25),
                          labelStyle: TextStyle(
                            color: tab == 0 ? Voy.brand : Voy.sub,
                            fontWeight: FontWeight.w700,
                          ),
                          onSelected: (_) => setSheet(() => tab = 0),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('Custom Stop')),
                          avatar: const Icon(Icons.edit_note_rounded, size: 16),
                          selected: tab == 1,
                          selectedColor: Voy.brand.withValues(alpha: 0.25),
                          labelStyle: TextStyle(
                            color: tab == 1 ? Voy.brand : Voy.sub,
                            fontWeight: FontWeight.w700,
                          ),
                          onSelected: (_) => setSheet(() => tab = 1),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (tab == 0) ...[
                    // Search box
                    TextField(
                      controller: searchCtrl,
                      style: const TextStyle(color: Voy.ink),
                      decoration: InputDecoration(
                        hintText: 'e.g. Viewpoint, Temple, Sunset cafe, Museum',
                        prefixIcon: const Icon(Icons.search_rounded, color: Voy.brand),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.arrow_forward_rounded, color: Voy.brand),
                          onPressed: runSearch,
                        ),
                        filled: true,
                        fillColor: Voy.surface2,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Voy.hairline),
                        ),
                      ),
                      onSubmitted: (_) => runSearch(),
                    ),
                    const SizedBox(height: 10),
                    if (isSearching)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator(color: Voy.brand)),
                      )
                    else if (searchErr != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(searchErr!, style: const TextStyle(color: Voy.coral, fontSize: 13)),
                      )
                    else if (searchResults.isNotEmpty) ...[
                      const Text(
                        'Suggestions (Tap to add):',
                        style: TextStyle(color: Voy.sub, fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      for (final r in searchResults)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: Voy.surface2,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Voy.hairline),
                          ),
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Voy.brand.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.place_rounded, color: Voy.brand, size: 18),
                            ),
                            title: Text(
                              r['name'] ?? '',
                              style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            subtitle: (r['area']?.isNotEmpty == true)
                                ? Text(r['area']!, style: const TextStyle(color: Voy.sub, fontSize: 12))
                                : null,
                            trailing: const Icon(Icons.add_circle_outline_rounded, color: Voy.brand),
                            onTap: () async {
                              final name = r['name'] ?? '';
                              final area = r['area'] ?? '';
                              final label = area.isEmpty ? name : '$name — $area';
                              final item = PlanItem(id: _uid(), text: label, category: 'place');
                              setState(() {
                                _days[targetDayIndex].items.add(item);
                              });
                              _persist();
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Added "$name" to ${_days[targetDayIndex].title}')),
                              );
                              try {
                                final gp = await _api.geocode(area.isEmpty ? name : '$name, $area');
                                if (mounted) {
                                  setState(() {
                                    item.lat = gp.lat;
                                    item.lng = gp.lng;
                                  });
                                  _persist();
                                }
                              } catch (_) {}
                            },
                          ),
                        ),
                    ] else ...[
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.travel_explore_rounded, size: 40, color: Voy.sub.withValues(alpha: 0.5)),
                              const SizedBox(height: 8),
                              const Text(
                                'Search places to visit or switch to "Custom Stop" to add directly.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Voy.sub, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ] else ...[
                    // Custom Entry Form
                    const Text('Category', style: TextStyle(color: Voy.sub, fontSize: 12.5)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in _categories)
                          ChoiceChip(
                            label: Text(c.$2),
                            avatar: Icon(c.$3, size: 16, color: category == c.$1 ? Colors.white : Voy.sub),
                            selected: category == c.$1,
                            selectedColor: Voy.brand,
                            labelStyle: TextStyle(
                              color: category == c.$1 ? Colors.white : Voy.ink,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                            onSelected: (_) => setSheet(() => category = c.$1),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: nameCtrl,
                      autofocus: true,
                      style: const TextStyle(color: Voy.ink),
                      decoration: const InputDecoration(
                        labelText: 'Place / Stop name',
                        hintText: 'e.g. Marina Beach, Lunch at Saravana Bhavan',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.schedule_rounded, size: 18),
                            label: Text(time.isEmpty ? 'Set time (optional)' : time),
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: ctx,
                                initialTime: TimeOfDay.now(),
                              );
                              if (picked != null) {
                                setSheet(() => time = picked.format(ctx));
                              }
                            },
                          ),
                        ),
                        if (time.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18, color: Voy.sub),
                            onPressed: () => setSheet(() => time = ''),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteCtrl,
                      style: const TextStyle(color: Voy.ink),
                      decoration: const InputDecoration(
                        labelText: 'Notes / Tips (optional)',
                        hintText: 'e.g. Parking on left side, entry closes at 5pm',
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Voy.brand,
                          foregroundColor: const Color(0xFF04211F),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.check_circle_rounded),
                        label: const Text('Add to Trip Plan', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          final text = nameCtrl.text.trim();
                          if (text.isEmpty) return;
                          final item = PlanItem(
                            id: _uid(),
                            text: text,
                            time: time,
                            note: noteCtrl.text.trim(),
                            category: category,
                          );
                          setState(() {
                            _days[targetDayIndex].items.add(item);
                          });
                          _persist();
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Added "$text" to ${_days[targetDayIndex].title}')),
                          );
                          try {
                            final gp = await _api.geocode(text);
                            if (mounted) {
                              setState(() {
                                item.lat = gp.lat;
                                item.lng = gp.lng;
                              });
                              _persist();
                            }
                          } catch (_) {}
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Edit an existing stop
  Future<void> _editItem(PlanItem item, PlanDay day) async {
    final textCtrl = TextEditingController(text: item.text);
    final noteCtrl = TextEditingController(text: item.note);
    String time = item.time;
    String category = item.category;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Voy.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 18,
            right: 18,
            top: 18,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.edit_location_alt_rounded, color: Voy.brand, size: 22),
                  const SizedBox(width: 8),
                  const Text('Edit Stop', style: TextStyle(color: Voy.ink, fontSize: 17, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Voy.danger),
                    onPressed: () {
                      Navigator.pop(ctx, false);
                      _deleteItem(item, day);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in _categories)
                    ChoiceChip(
                      label: Text(c.$2),
                      avatar: Icon(c.$3, size: 16, color: category == c.$1 ? Colors.white : Voy.sub),
                      selected: category == c.$1,
                      selectedColor: Voy.brand,
                      labelStyle: TextStyle(
                        color: category == c.$1 ? Colors.white : Voy.ink,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      onSelected: (_) => setSheet(() => category = c.$1),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textCtrl,
                style: const TextStyle(color: Voy.ink),
                decoration: const InputDecoration(labelText: 'Place / Stop name'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.schedule_rounded, size: 18),
                      label: Text(time.isEmpty ? 'Set time' : time),
                      onPressed: () async {
                        final picked = await showTimePicker(context: ctx, initialTime: TimeOfDay.now());
                        if (picked != null) {
                          setSheet(() => time = picked.format(ctx));
                        }
                      },
                    ),
                  ),
                  if (time.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18, color: Voy.sub),
                      onPressed: () => setSheet(() => time = ''),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                style: const TextStyle(color: Voy.ink),
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Voy.brand,
                    foregroundColor: const Color(0xFF04211F),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved == true && mounted) {
      setState(() {
        item.text = textCtrl.text.trim();
        item.time = time;
        item.note = noteCtrl.text.trim();
        item.category = category;
      });
      _persist();
    }
  }

  /// Move item to another day
  Future<void> _moveItemToDay(PlanItem item, PlanDay currentDay) async {
    if (_days.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add another day to the trip first before moving stops.')),
      );
      return;
    }

    final targetIndex = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Voy.surface,
        title: const Text('Move to another day', style: TextStyle(color: Voy.ink, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < _days.length; i++)
              ListTile(
                title: Text(
                  'Day ${i + 1}: ${_days[i].title}',
                  style: TextStyle(
                    color: _days[i] == currentDay ? Voy.sub : Voy.ink,
                    fontWeight: _days[i] == currentDay ? FontWeight.normal : FontWeight.bold,
                  ),
                ),
                trailing: _days[i] == currentDay
                    ? const Text('(Current)', style: TextStyle(color: Voy.sub, fontSize: 11))
                    : const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Voy.brand),
                onTap: _days[i] == currentDay ? null : () => Navigator.pop(ctx, i),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );

    if (targetIndex != null && mounted) {
      setState(() {
        currentDay.items.remove(item);
        _days[targetIndex].items.add(item);
      });
      _persist();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Moved "${item.text}" to Day ${targetIndex + 1}')),
      );
    }
  }

  /// Delete a stop with undo option
  void _deleteItem(PlanItem item, PlanDay day) {
    final originalIndex = day.items.indexOf(item);
    setState(() {
      day.items.remove(item);
    });
    _persist();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed "${item.text}"'),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: Voy.brand,
          onPressed: () {
            setState(() {
              if (originalIndex >= 0 && originalIndex <= day.items.length) {
                day.items.insert(originalIndex, item);
              } else {
                day.items.add(item);
              }
            });
            _persist();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final day = _days.isEmpty ? null : _days[_dayIndex.clamp(0, _days.length - 1)];
    final items = day == null ? <PlanItem>[] : day.items;
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
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: const BoxDecoration(color: Voy.success, shape: BoxShape.circle),
                ),
                const Text('Active Trip', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ],
            ),
            Text(
              widget.tripName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: Voy.sub, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          // Reorder / edit toggle
          IconButton(
            icon: Icon(
              _isReordering ? Icons.check_circle_rounded : Icons.swap_vert_rounded,
              color: _isReordering ? Voy.brand : Voy.sub,
            ),
            tooltip: _isReordering ? 'Done reordering' : 'Reorder stops',
            onPressed: () => setState(() => _isReordering = !_isReordering),
          ),
          // Edit Plan Menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Voy.ink),
            tooltip: 'Plan Options',
            color: Voy.surface2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (action) {
              switch (action) {
                case 'add_place':
                  _showAddPlaceSheet();
                  break;
                case 'add_day':
                  _addDay();
                  break;
                case 'rename_day':
                  if (day != null) _renameDay(day);
                  break;
                case 'full_planner':
                  _openFullPlanner();
                  break;
                case 'end_trip':
                  _endTrip();
                  break;
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'add_place',
                child: Row(children: [
                  Icon(Icons.add_location_alt_rounded, color: Voy.brand, size: 18),
                  SizedBox(width: 10),
                  Text('Add Place / Stop', style: TextStyle(color: Voy.ink)),
                ]),
              ),
              const PopupMenuItem(
                value: 'add_day',
                child: Row(children: [
                  Icon(Icons.add_rounded, color: Voy.ink, size: 18),
                  SizedBox(width: 10),
                  Text('Add New Day', style: TextStyle(color: Voy.ink)),
                ]),
              ),
              if (day != null)
                const PopupMenuItem(
                  value: 'rename_day',
                  child: Row(children: [
                    Icon(Icons.edit_rounded, color: Voy.ink, size: 18),
                    SizedBox(width: 10),
                    Text('Rename Day', style: TextStyle(color: Voy.ink)),
                  ]),
                ),
              const PopupMenuItem(
                value: 'full_planner',
                child: Row(children: [
                  Icon(Icons.auto_awesome_rounded, color: Voy.violet, size: 18),
                  SizedBox(width: 10),
                  Text('Open Full Planner', style: TextStyle(color: Voy.ink)),
                ]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'end_trip',
                child: Row(children: [
                  Icon(Icons.stop_circle_outlined, color: Voy.danger, size: 18),
                  SizedBox(width: 10),
                  Text('End Active Trip', style: TextStyle(color: Voy.danger, fontWeight: FontWeight.bold)),
                ]),
              ),
            ],
          ),
          TextButton.icon(
            onPressed: _endTrip,
            icon: const Icon(Icons.stop_circle_outlined, size: 18, color: Voy.danger),
            label: const Text('End', style: TextStyle(color: Voy.danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddPlaceSheet,
        backgroundColor: Voy.brand,
        foregroundColor: const Color(0xFF04211F),
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('Add Place', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _days.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.map_outlined, size: 48, color: Voy.sub),
                    const SizedBox(height: 12),
                    const Text('No days planned yet.', style: TextStyle(color: Voy.sub, fontSize: 16)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _addDay,
                      icon: const Icon(Icons.add),
                      label: const Text('Add First Day'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                _dayBar(day!),
                if (_isReordering)
                  Container(
                    width: double.infinity,
                    color: Voy.brand.withValues(alpha: 0.15),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.drag_indicator_rounded, color: Voy.brand, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Drag stops up or down to reorder them on the fly.',
                            style: TextStyle(color: Voy.ink, fontSize: 12.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _isReordering = false),
                          child: const Text('Done', style: TextStyle(color: Voy.brand, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  )
                else if (nextItem != null)
                  _nextUpBanner(nextItem),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.place_outlined, size: 48, color: Voy.sub.withValues(alpha: 0.5)),
                                const SizedBox(height: 12),
                                const Text(
                                  'Nothing planned for this day yet.',
                                  style: TextStyle(color: Voy.sub, fontSize: 15, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Tap "+ Add Place" below to search or add stops on the go.',
                                  style: TextStyle(color: Voy.sub, fontSize: 12.5),
                                ),
                                const SizedBox(height: 16),
                                OutlinedButton.icon(
                                  onPressed: _showAddPlaceSheet,
                                  icon: const Icon(Icons.add_location_alt_rounded, size: 18),
                                  label: const Text('Add a Place to Visit'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _isReordering
                          ? ReorderableListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                              itemCount: items.length,
                              onReorder: (oldIdx, newIdx) {
                                setState(() {
                                  if (newIdx > oldIdx) newIdx -= 1;
                                  final it = items.removeAt(oldIdx);
                                  items.insert(newIdx, it);
                                });
                                _persist();
                              },
                              itemBuilder: (_, i) => _itemRow(
                                items[i],
                                isNext: identical(items[i], nextItem),
                                key: ValueKey(items[i].id),
                                reorderable: true,
                                day: day,
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                              itemCount: items.length,
                              itemBuilder: (_, i) => _itemRow(
                                items[i],
                                isNext: identical(items[i], nextItem),
                                key: ValueKey(items[i].id),
                                reorderable: false,
                                day: day,
                              ),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: _dayIndex > 0 ? () => setState(() => _dayIndex--) : null,
                icon: const Icon(Icons.chevron_left_rounded, color: Voy.ink),
              ),
              Expanded(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Day ${_dayIndex + 1} of ${_days.length}',
                          style: const TextStyle(color: Voy.ink, fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                        if (_isToday) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Voy.brand.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'TODAY',
                              style: TextStyle(color: Voy.brand, fontSize: 10, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    InkWell(
                      onTap: () => _renameDay(day),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              '${_fmtDate(_dateForDay(_dayIndex))} · ${day.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Voy.sub, fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.edit_rounded, size: 12, color: Voy.sub),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _dayIndex < _days.length - 1 ? () => setState(() => _dayIndex++) : null,
                icon: const Icon(Icons.chevron_right_rounded, color: Voy.ink),
              ),
            ],
          ),
          // Day selector chips
          if (_days.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  for (int i = 0; i < _days.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text('Day ${i + 1}'),
                        selected: i == _dayIndex,
                        selectedColor: Voy.brand.withValues(alpha: 0.25),
                        labelStyle: TextStyle(
                          color: i == _dayIndex ? Voy.brand : Voy.sub,
                          fontSize: 11,
                          fontWeight: i == _dayIndex ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (_) => setState(() => _dayIndex = i),
                      ),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 14, color: Voy.brand),
                    label: const Text('+ Day', style: TextStyle(color: Voy.brand, fontSize: 11)),
                    onPressed: _addDay,
                  ),
                ],
              ),
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
        gradient: LinearGradient(
          colors: [Voy.brand.withValues(alpha: 0.22), Voy.violet.withValues(alpha: 0.18)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Voy.brand.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Voy.brand.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.navigation_rounded, color: Voy.brand, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'NEXT UP',
                  style: TextStyle(color: Voy.brand, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1),
                ),
                const SizedBox(height: 2),
                Text(
                  [if (item.time.isNotEmpty) item.time, item.text].join('  '),
                  style: const TextStyle(color: Voy.ink, fontSize: 15, fontWeight: FontWeight.w700),
                ),
                if (item.note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      item.note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Voy.sub, fontSize: 12.5),
                    ),
                  ),
              ],
            ),
          ),
          FilledButton(
            onPressed: () => _toggle(item),
            style: FilledButton.styleFrom(
              backgroundColor: Voy.brand,
              foregroundColor: const Color(0xFF04211F),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
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

  Widget _itemRow(PlanItem item, {required bool isNext, required Key key, required bool reorderable, required PlanDay day}) {
    return Container(
      key: key,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isNext ? Voy.brand.withValues(alpha: 0.08) : Voy.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isNext ? Voy.brand.withValues(alpha: 0.45) : Voy.hairline),
      ),
      child: ListTile(
        onTap: reorderable ? null : () => _toggle(item),
        leading: reorderable
            ? const Icon(Icons.drag_handle_rounded, color: Voy.brand)
            : SizedBox(
                width: 54,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: item.done ? Voy.success : Voy.sub,
                      size: 22,
                    ),
                    const SizedBox(width: 4),
                    Icon(_catIcon(item.category), size: 16, color: Voy.sub),
                  ],
                ),
              ),
        title: Row(
          children: [
            if (item.time.isNotEmpty) ...[
              Text(
                item.time,
                style: const TextStyle(color: Voy.brand, fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                item.text,
                style: TextStyle(
                  color: item.done ? Voy.sub : Voy.ink,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  decoration: item.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
        subtitle: (item.note.isEmpty)
            ? null
            : Text(
                item.note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Voy.sub, fontSize: 12),
              ),
        trailing: reorderable
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_rounded, color: Voy.sub, size: 18),
                    tooltip: 'Edit stop',
                    onPressed: () => _editItem(item, day),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, color: Voy.sub, size: 18),
                    tooltip: 'More actions',
                    color: Voy.surface2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onSelected: (act) {
                      switch (act) {
                        case 'edit':
                          _editItem(item, day);
                          break;
                        case 'move_day':
                          _moveItemToDay(item, day);
                          break;
                        case 'toggle':
                          _toggle(item);
                          break;
                        case 'delete':
                          _deleteItem(item, day);
                          break;
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(children: [
                          Icon(Icons.edit_rounded, size: 16, color: Voy.ink),
                          SizedBox(width: 8),
                          Text('Edit details'),
                        ]),
                      ),
                      const PopupMenuItem(
                        value: 'move_day',
                        child: Row(children: [
                          Icon(Icons.calendar_month_rounded, size: 16, color: Voy.brand),
                          SizedBox(width: 8),
                          Text('Move to another day'),
                        ]),
                      ),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Row(children: [
                          Icon(item.done ? Icons.undo_rounded : Icons.check_rounded, size: 16, color: Voy.ink),
                          SizedBox(width: 8),
                          Text(item.done ? 'Mark unvisited' : 'Mark visited'),
                        ]),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete_outline_rounded, size: 16, color: Voy.danger),
                          SizedBox(width: 8),
                          Text('Remove place', style: TextStyle(color: Voy.danger)),
                        ]),
                      ),
                    ],
                  ),
                ],
              ),
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
          Row(
            children: [
              Text('$done of $total stops completed', style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${(pct * 100).round()}%', style: const TextStyle(color: Voy.brand, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: Voy.hairline,
              color: Voy.brand,
            ),
          ),
        ],
      ),
    );
  }
}
