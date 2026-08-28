import 'package:flutter/material.dart';
import '../models/trip_models.dart';
import '../models/trip_extras.dart';
import '../services/api_service.dart';
import '../services/trip_extras_store.dart';
import '../widgets/app_design.dart';
import 'day_planner_screen.dart';

/// AI-powered smart trip planner: pick a start date/time + destination and the
/// AI builds a realistic, time-blocked day-by-day itinerary with automatic
/// meal/rest breaks, travel time and per-block reasoning — then lets you nudge it
/// (regenerate, optimise, more sightseeing, less travel, pace mode…).
class SmartItineraryScreen extends StatefulWidget {
  const SmartItineraryScreen({super.key});

  @override
  State<SmartItineraryScreen> createState() => _SmartItineraryScreenState();
}

class _SmartItineraryScreenState extends State<SmartItineraryScreen> {
  static const String _bgUrl =
      'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?q=80&w=2000&auto=format&fit=crop';

  final _api = ApiService();
  final _destCtrl = TextEditingController();
  final _startLocCtrl = TextEditingController();
  final _placesCtrl = TextEditingController();
  final _prefsCtrl = TextEditingController();

  DateTime? _startDate;
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 0);
  DateTime? _endDate;
  TimeOfDay? _endTime;
  int _days = 2;
  String _mode = 'balanced';

  bool _loading = false;
  String? _error;
  List<SmartDay> _itinerary = [];

  @override
  void dispose() {
    _destCtrl.dispose();
    _startLocCtrl.dispose();
    _placesCtrl.dispose();
    _prefsCtrl.dispose();
    super.dispose();
  }

  int get _durationDays {
    if (_startDate != null && _endDate != null) {
      final d = _endDate!.difference(DateTime(_startDate!.year, _startDate!.month, _startDate!.day)).inDays + 1;
      return d.clamp(1, 14);
    }
    return _days;
  }

  String _fmtDate(DateTime? d) => d == null ? 'Pick date' : '${d.day}/${d.month}/${d.year}';
  String _fmtTime(TimeOfDay? t) => t == null ? '--:--' : t.format(context);

  Future<void> _generate({String directive = ''}) async {
    final dest = _destCtrl.text.trim();
    if (dest.isEmpty) {
      setState(() => _error = 'Enter a destination first.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final places = _placesCtrl.text
          .split(RegExp(r'[,\n]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final days = await _api.aiSmartItinerary(
        destination: dest,
        startLocation: _startLocCtrl.text.trim(),
        places: places,
        startDate: _startDate == null ? '' : _fmtDate(_startDate),
        startTime: _startTime.format(context),
        endDate: _endDate == null ? '' : _fmtDate(_endDate),
        endTime: _endTime == null ? '' : _endTime!.format(context),
        durationDays: _durationDays,
        mode: _mode,
        preferences: _prefsCtrl.text.trim(),
        directive: directive,
      );
      if (!mounted) return;
      setState(() => _itinerary = days);
      if (days.isEmpty) setState(() => _error = 'The AI returned an empty plan — try again.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setMode(String m) {
    setState(() => _mode = m);
    if (_itinerary.isNotEmpty) _generate();
  }

  /// Convert the AI timeline to PlanDays and persist it locally. Returns the
  /// tripKey it was saved under.
  Future<String> _persistPlan() async {
    final planDays = <PlanDay>[];
    for (int i = 0; i < _itinerary.length; i++) {
      final d = _itinerary[i];
      final items = <PlanItem>[];
      for (int j = 0; j < d.blocks.length; j++) {
        final b = d.blocks[j];
        if (b.title.trim().isEmpty) continue;
        items.add(PlanItem(
          id: '${DateTime.now().microsecondsSinceEpoch}_${i}_$j',
          text: b.title,
          time: b.start,
          note: b.reason,
          category: _blockToCategory(b.type),
        ));
      }
      planDays.add(PlanDay(id: '${DateTime.now().microsecondsSinceEpoch}_d$i', title: d.title.isEmpty ? 'Day ${i + 1}' : d.title, items: items));
    }
    final dest = _destCtrl.text.trim();
    final tripKey = 'smart_${dest.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    await TripExtrasStore(tripKey).saveDays(planDays);
    return tripKey;
  }

  /// Save the itinerary without leaving the screen.
  Future<void> _save() async {
    await _persistPlan();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Itinerary saved ✓ — find it in the day planner')),
    );
  }

  /// Save and open the day-by-day planner to start following the trip.
  Future<void> _start() async {
    final tripKey = await _persistPlan();
    if (!mounted) return;
    final dest = _destCtrl.text.trim();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DayPlannerScreen(tripKey: tripKey, tripName: '$dest (AI plan)'),
    ));
  }

  String _blockToCategory(String type) {
    switch (type) {
      case 'meal':
      case 'coffee':
        return 'restaurant';
      case 'checkin':
      case 'checkout':
        return 'stay';
      case 'activity':
      case 'shopping':
      case 'freetime':
      case 'rest':
        return 'activity';
      default:
        return 'place';
    }
  }

  (IconData, Color) _blockStyle(String type) {
    switch (type) {
      case 'start':
        return (Icons.flag_rounded, const Color(0xFF22C7C0));
      case 'travel':
        return (Icons.directions_car_rounded, const Color(0xFF94A3B8));
      case 'meal':
        return (Icons.restaurant_rounded, const Color(0xFFF97316));
      case 'coffee':
        return (Icons.local_cafe_rounded, const Color(0xFFD9A066));
      case 'rest':
        return (Icons.airline_seat_recline_normal_rounded, const Color(0xFF8B5CF6));
      case 'checkin':
        return (Icons.hotel_rounded, const Color(0xFF22C55E));
      case 'checkout':
        return (Icons.luggage_rounded, const Color(0xFF22C55E));
      case 'buffer':
        return (Icons.hourglass_bottom_rounded, const Color(0xFF94A3B8));
      case 'shopping':
        return (Icons.shopping_bag_rounded, const Color(0xFFEC4899));
      case 'freetime':
        return (Icons.beach_access_rounded, const Color(0xFF06B6D4));
      case 'return':
        return (Icons.home_rounded, const Color(0xFFEF4444));
      default:
        return (Icons.photo_camera_rounded, AppColors.accentLight);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppColors.obsidian,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Smart AI planner'),
      ),
      body: AnimatedBackground(
        imageUrl: _bgUrl,
        overlayOpacity: 0.64,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              RevealIn(child: _inputCard()),
              const SizedBox(height: 14),
              if (_error != null) ...[
                _errorBanner(),
                const SizedBox(height: 12),
              ],
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_itinerary.isNotEmpty)
                ..._results(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorBanner() => GlassCard(
        padding: const EdgeInsets.all(14),
        glow: false,
        child: Row(children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12.5))),
        ]),
      );

  Widget _field(TextEditingController c, String hint, IconData icon, {int maxLines = 1}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        prefixIcon: Icon(icon, color: Colors.white70, size: 20),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.07),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
      ),
    );
  }

  Widget _pill(String label, IconData icon, VoidCallback onTap) => Expanded(
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 16, color: AppColors.accentLight),
          label: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      );

  Widget _inputCard() {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Plan a trip with AI', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Set your start date & time — the AI schedules everything, breaks included.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5)),
          const SizedBox(height: 14),
          _field(_destCtrl, 'Destination (e.g. Coorg, Karnataka)', Icons.explore_rounded),
          const SizedBox(height: 10),
          _field(_startLocCtrl, 'Starting location (optional)', Icons.my_location_rounded),
          const SizedBox(height: 10),
          _field(_placesCtrl, 'Places to visit (comma-separated, optional)', Icons.place_rounded, maxLines: 2),
          const SizedBox(height: 14),
          // Start date + time
          Row(children: [
            _pill(_fmtDate(_startDate), Icons.calendar_today_rounded, () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: _startDate ?? now,
                firstDate: DateTime(now.year - 1),
                lastDate: DateTime(now.year + 3),
              );
              if (picked != null) setState(() => _startDate = picked);
            }),
            const SizedBox(width: 10),
            _pill('Start ${_fmtTime(_startTime)}', Icons.schedule_rounded, () async {
              final picked = await showTimePicker(context: context, initialTime: _startTime);
              if (picked != null) setState(() => _startTime = picked);
            }),
          ]),
          const SizedBox(height: 10),
          // Optional end date + time
          Row(children: [
            _pill(_endDate == null ? 'End date (opt)' : _fmtDate(_endDate), Icons.event_rounded, () async {
              final base = _startDate ?? DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: _endDate ?? base,
                firstDate: base,
                lastDate: DateTime(base.year + 3),
              );
              if (picked != null) setState(() => _endDate = picked);
            }),
            const SizedBox(width: 10),
            _pill(_endTime == null ? 'End time (opt)' : 'End ${_fmtTime(_endTime)}', Icons.schedule_outlined, () async {
              final picked = await showTimePicker(context: context, initialTime: _endTime ?? const TimeOfDay(hour: 20, minute: 0));
              if (picked != null) setState(() => _endTime = picked);
            }),
          ]),
          const SizedBox(height: 14),
          // Duration (days) when no end date is set
          if (_endDate == null)
            Row(children: [
              Text('Days', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
              const SizedBox(width: 12),
              _stepBtn(Icons.remove, () => setState(() => _days = (_days - 1).clamp(1, 14))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text('$_days', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              _stepBtn(Icons.add, () => setState(() => _days = (_days + 1).clamp(1, 14))),
            ])
          else
            Text('Duration: $_durationDays day(s)', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
          const SizedBox(height: 14),
          // Pace mode
          Text('Pace', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
          const SizedBox(height: 8),
          Row(children: [
            for (final m in const ['relaxed', 'balanced', 'packed'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _modeChip(m),
              ),
          ]),
          const SizedBox(height: 12),
          _field(_prefsCtrl, 'Preferences (e.g. temples, hiking, veg food)', Icons.tune_rounded, maxLines: 2),
          const SizedBox(height: 16),
          AccentButton(
            onPressed: _loading ? null : () => _generate(),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(_itinerary.isEmpty ? 'GENERATE ITINERARY' : 'REGENERATE'),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _modeChip(String m) {
    final selected = _mode == m;
    return GestureDetector(
      onTap: () => _setMode(m),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentLight.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.accentLight : Colors.white.withValues(alpha: 0.15)),
        ),
        child: Text('${m[0].toUpperCase()}${m.substring(1)}',
            style: TextStyle(
                color: selected ? AppColors.accentLight : Colors.white.withValues(alpha: 0.8),
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      );

  List<Widget> _results() {
    return [
      _controlsCard(),
      const SizedBox(height: 14),
      ...RevealIn.stagger(
        [for (final day in _itinerary) _dayCard(day)],
        initial: const Duration(milliseconds: 80),
        step: const Duration(milliseconds: 60),
      ),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.bookmark_add_rounded, size: 18, color: Colors.white),
            label: const Text('Save', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AccentButton(
            onPressed: _start,
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
              SizedBox(width: 6),
              Text('START TRIP'),
            ]),
          ),
        ),
      ]),
    ];
  }

  Widget _controlsCard() {
    Widget ctl(String label, IconData icon, String directive) => OutlinedButton.icon(
          onPressed: _loading ? null : () => _generate(directive: directive),
          icon: Icon(icon, size: 16, color: AppColors.accentLight),
          label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        );
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tune with AI', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ctl('Optimize', Icons.tune_rounded, 'Optimise the schedule: tighten timings, minimise backtracking, better flow.'),
            ctl('More sightseeing', Icons.add_photo_alternate_rounded, 'Add more sightseeing and notable attractions.'),
            ctl('More free time', Icons.self_improvement_rounded, 'Add more free/relaxation time and shorten packed stretches.'),
            ctl('Reduce travel', Icons.route_rounded, 'Reduce travel: group nearby places, cut long transfers.'),
            ctl('Add meal breaks', Icons.restaurant_rounded, 'Ensure proper breakfast, lunch, dinner and a coffee break each day.'),
          ]),
        ],
      ),
    );
  }

  Widget _dayCard(SmartDay day) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: AppColors.accentGradient,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('DAY ${day.day}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(day.title.isEmpty ? '' : day.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700)),
              ),
              if (day.date.isNotEmpty)
                Text(day.date, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11.5)),
            ]),
            const SizedBox(height: 12),
            for (int i = 0; i < day.blocks.length; i++) _blockRow(day.blocks[i], i == day.blocks.length - 1),
          ],
        ),
      ),
    );
  }

  Widget _blockRow(TimelineBlock b, bool isLast) {
    final (icon, color) = _blockStyle(b.type);
    final timeLabel = b.end.isNotEmpty && b.end != b.start ? '${b.start}–${b.end}' : b.start;
    final meta = <String>[];
    if (b.durationMin > 0) meta.add('${b.durationMin} min');
    if (b.travelMin > 0) meta.add('🚗 ${b.travelMin} min');
    if (b.distanceKm > 0) meta.add('${b.distanceKm.toStringAsFixed(1)} km');
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time column
          SizedBox(
            width: 82,
            child: Text(timeLabel,
                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
          // Timeline rail
          Column(children: [
            Container(
              width: 30, height: 30, alignment: Alignment.center,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle, border: Border.all(color: color, width: 1.2)),
              child: Icon(icon, size: 16, color: color),
            ),
            if (!isLast) Expanded(child: Container(width: 2, color: Colors.white.withValues(alpha: 0.12), margin: const EdgeInsets.symmetric(vertical: 2))),
          ]),
          const SizedBox(width: 10),
          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(b.title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600))),
                    if (b.breakType.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                        child: Text(b.breakType, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
                      ),
                  ]),
                  if (meta.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(meta.join(' · '), style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11.5)),
                    ),
                  if (b.reason.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(b.reason,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11.5, fontStyle: FontStyle.italic)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
