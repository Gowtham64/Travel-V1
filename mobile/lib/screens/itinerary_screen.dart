import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/trip_models.dart';
import '../services/api_service.dart';
import '../utils/calendar_helper.dart';

/// Premium, AI-powered Travel Itinerary screen.
///
/// Wired to the data the planner already produces: [TripPlan.itinerary] (daily
/// drive plan), [TripPlan.budget], [TripPlan.weather] / [TripPlan.departureAdvice],
/// and the backend AI assistant. Sections: Trip Overview + Timeline, Budget,
/// Weather + Packing, and AI Assistant.
class ItineraryScreen extends StatefulWidget {
  final TripPlan plan;
  final String startAddress;
  final String endAddress;
  final GeoPoint start;
  final GeoPoint end;
  final List<GeoPoint> waypoints;
  final String vehicleType;
  final int travellers;
  final DateTime tripStart;
  /// A previously-saved AI itinerary to preload (list of day maps).
  final List<Map<String, dynamic>>? initialItinerary;

  const ItineraryScreen({
    super.key,
    required this.plan,
    required this.startAddress,
    required this.endAddress,
    required this.start,
    required this.end,
    required this.travellers,
    required this.tripStart,
    this.waypoints = const [],
    this.vehicleType = 'car',
    this.initialItinerary,
  });

  @override
  State<ItineraryScreen> createState() => _ItineraryScreenState();
}

// ---- palette (dark, matches the app + prototype) ----
const _bg = Color(0xFF0E1116);
const _surface = Color(0xFF161B22);
const _surface2 = Color(0xFF1B212C);
const _hairline = Color(0xFF242C38);
const _ink = Color(0xFFEDEFF3);
const _sub = Color(0xFF8B97A7);
const _brand = Color(0xFF22C7C0);
const _violet = Color(0xFF8F81F2);
const _pink = Color(0xFFF472B6);
const _amber = Color(0xFFFBBF24);
const _coral = Color(0xFFFF8672);
const _success = Color(0xFF34D27B);
const _info = Color(0xFF60A5FA);

class _ItineraryScreenState extends State<ItineraryScreen> {
  final _api = ApiService();
  Timer? _countdownTimer;
  Duration _remaining = Duration.zero;

  // Editable trip start (date + time), initialised from the caller.
  late DateTime _tripStart;

  // Packing checklist state
  late Map<String, List<String>> _packing;
  final Set<String> _packed = {};

  // AI chat
  final _chat = <_Msg>[];
  final _chatCtrl = TextEditingController();
  bool _aiLoading = false;

  // AI-generated day-by-day itinerary
  List<_GenDay>? _generated;
  bool _building = false;
  bool _saving = false;
  final Set<String> _doneActivities = {};

  @override
  void initState() {
    super.initState();
    _tripStart = widget.tripStart;
    if (widget.initialItinerary != null && widget.initialItinerary!.isNotEmpty) {
      final days = widget.initialItinerary!.map(_GenDay.fromJson).where((d) => d.activities.isNotEmpty).toList();
      if (days.isNotEmpty) _generated = days;
    }
    _packing = _generatePacking();
    _chat.add(_Msg(false, _openingLine()));
    _tickCountdown();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickCountdown());
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _chatCtrl.dispose();
    super.dispose();
  }

  // ---------- derived ----------
  DateTime get _endDate => _tripStart.add(Duration(days: math.max(0, widget.plan.estimatedDays - 1)));

  String get _statusLabel {
    final now = DateTime.now();
    if (now.isBefore(_tripStart)) return 'Upcoming';
    if (now.isAfter(_endDate.add(const Duration(days: 1)))) return 'Completed';
    return 'Ongoing';
  }

  Color get _statusColor => _statusLabel == 'Upcoming'
      ? _success
      : _statusLabel == 'Ongoing'
          ? _amber
          : _sub;

  void _tickCountdown() {
    final d = _tripStart.difference(DateTime.now());
    if (mounted) setState(() => _remaining = d.isNegative ? Duration.zero : d);
  }

  String _cur(int v) {
    final c = widget.plan.budget?.currency ?? 'INR';
    final sym = c == 'INR'
        ? '₹'
        : c == 'USD'
            ? '\$'
            : c == 'EUR'
                ? '€'
                : c == 'GBP'
                    ? '£'
                    : '$c ';
    // compact for large numbers
    if (v >= 100000) return '$sym${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '$sym${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
    return '$sym$v';
  }

  String _curFull(int v) {
    final c = widget.plan.budget?.currency ?? 'INR';
    final sym = c == 'INR' ? '₹' : c == 'USD' ? '\$' : c == 'EUR' ? '€' : c == 'GBP' ? '£' : '$c ';
    final s = v.toString();
    // thousands separators
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '$sym$buf';
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String _fmtDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';
  String _fmtDateRange() {
    final a = _tripStart, b = _endDate;
    if (a.year == b.year && a.month == b.month && a.day == b.day) return _fmtDate(a);
    if (a.month == b.month) return '${a.day}–${b.day} ${_months[a.month - 1]}';
    return '${_fmtDate(a)} – ${_fmtDate(b)}';
  }

  String get _dest => widget.end.name?.isNotEmpty == true ? widget.end.name! : widget.endAddress;
  String get _origin => widget.start.name?.isNotEmpty == true ? widget.start.name! : widget.startAddress;

  // ---------- build ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: _bg.withOpacity(0.85),
            surfaceTintColor: Colors.transparent,
            pinned: true,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _ink, size: 20),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: const Text('Trip Itinerary', style: TextStyle(color: _ink, fontWeight: FontWeight.w700, fontSize: 16)),
            actions: [
              _saving
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _brand)),
                    )
                  : IconButton(
                      onPressed: _saveTrip,
                      tooltip: 'Save trip',
                      icon: const Icon(Icons.bookmark_add_rounded, color: _ink, size: 22),
                    ),
              IconButton(onPressed: _share, icon: const Icon(Icons.ios_share_rounded, color: _ink, size: 20)),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _heroOverview(),
                const SizedBox(height: 26),
                _sectionHead(Icons.timeline_rounded, 'Daily Itinerary', 'Your day-by-day plan'),
                const SizedBox(height: 12),
                _timeline(),
                const SizedBox(height: 26),
                _sectionHead(Icons.account_balance_wallet_rounded, 'Budget Planner',
                    widget.plan.budget != null ? '${_curFull(widget.plan.budget!.total)} total' : 'Estimate'),
                const SizedBox(height: 12),
                _budget(),
                const SizedBox(height: 26),
                _sectionHead(Icons.wb_cloudy_rounded, 'Weather & Packing', 'Along your route'),
                const SizedBox(height: 12),
                _weather(),
                const SizedBox(height: 12),
                _packingCard(),
                const SizedBox(height: 26),
                _sectionHead(Icons.auto_awesome_rounded, 'AI Travel Assistant', 'Ask anything about your trip'),
                const SizedBox(height: 12),
                _assistant(),
                const SizedBox(height: 30),
                Center(
                  child: Text('Voyplan · AI-powered itinerary',
                      style: TextStyle(color: _sub.withOpacity(0.6), fontSize: 11)),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Section header ----------
  Widget _sectionHead(IconData icon, String title, String sub) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: _brand.withOpacity(0.14), borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, color: _brand, size: 19),
        ),
        const SizedBox(width: 11),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
            Text(sub, style: const TextStyle(color: _sub, fontSize: 12)),
          ],
        ),
      ],
    );
  }

  // ---------- 1. HERO OVERVIEW ----------
  Widget _heroOverview() {
    final days = widget.plan.estimatedDays;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              Container(
                height: 176,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFFEC4899), Color(0xFFF59E0B)],
                    stops: [0.0, 0.42, 0.74, 1.0],
                  ),
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.55)],
                    ),
                  ),
                ),
              ),
              // sun
              Positioned(
                right: 26,
                top: 22,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(colors: [Colors.white, Color(0xFFFFE9B0), Color(0xFFFFB44A)]),
                    boxShadow: [BoxShadow(color: const Color(0xFFFFBE5A).withOpacity(0.5), blurRadius: 36, spreadRadius: 8)],
                  ),
                ),
              ),
              Positioned(top: 14, left: 14, child: _pill(_statusLabel, _statusColor, dot: true, glass: true)),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$_origin → $_dest',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.15)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.place_rounded, color: Colors.white70, size: 14),
                        const SizedBox(width: 4),
                        Text('${widget.plan.distanceKm.toStringAsFixed(0)} km · $days ${days == 1 ? 'day' : 'days'}',
                            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // stat strip
        Row(
          children: [
            _oStat(Icons.calendar_today_rounded, 'Dates', _fmtDateRange()),
            const SizedBox(width: 9),
            _oStat(Icons.schedule_rounded, 'Duration', '$days ${days == 1 ? 'Day' : 'Days'}'),
            const SizedBox(width: 9),
            _oStat(Icons.group_rounded, 'Travelers', '${widget.travellers}'),
          ],
        ),
        const SizedBox(height: 12),
        // editable trip start (calendar + clock)
        _tripStartEditor(),
        const SizedBox(height: 12),
        // countdown (only if upcoming)
        if (_remaining > Duration.zero) _countdownCard(),
        if (_remaining > Duration.zero) const SizedBox(height: 12),
        // actions
        Row(
          children: [
            _action(Icons.ios_share_rounded, 'Share', _share),
            const SizedBox(width: 9),
            _action(Icons.picture_as_pdf_rounded, 'Export', _share),
            const SizedBox(width: 9),
            _action(Icons.event_available_rounded, 'Calendar', _addToCalendar),
          ],
        ),
      ],
    );
  }

  String _fmtTime(DateTime d) {
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    var h = d.hour % 12;
    if (h == 0) h = 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} $ampm';
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// Editable "Trip start" card — opens the built-in calendar then clock.
  Widget _tripStartEditor() {
    final label = '${_weekdays[_tripStart.weekday - 1]}, ${_fmtDate(_tripStart)} · ${_fmtTime(_tripStart)}';
    return InkWell(
      onTap: _pickTripStart,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: _hairline)),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: _brand.withOpacity(0.14), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.event_rounded, color: _brand, size: 18),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TRIP START', style: TextStyle(color: _sub, fontSize: 9.5, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                  const SizedBox(height: 2),
                  Text(label, style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Row(
              children: const [
                Text('Edit', style: TextStyle(color: _brand, fontSize: 12, fontWeight: FontWeight.w700)),
                SizedBox(width: 4),
                Icon(Icons.edit_calendar_rounded, color: _brand, size: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Built-in calendar (date) then clock (time) pickers.
  Future<void> _pickTripStart() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 1);
    final last = DateTime(now.year + 2, 12, 31);
    var initial = _tripStart;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Select trip start date',
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_tripStart),
      helpText: 'Select start time',
    );
    if (!mounted) return;
    final t = time ?? TimeOfDay.fromDateTime(_tripStart);

    setState(() => _tripStart = DateTime(date.year, date.month, date.day, t.hour, t.minute));
  }

  Widget _oStat(IconData icon, String k, String v) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: _hairline)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k.toUpperCase(), style: const TextStyle(color: _sub, fontSize: 9.5, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(icon, color: _brand, size: 15),
                const SizedBox(width: 5),
                Flexible(child: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w700))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _countdownCard() {
    final d = _remaining.inDays;
    final h = _remaining.inHours % 24;
    final m = _remaining.inMinutes % 60;
    final s = _remaining.inSeconds % 60;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: _hairline)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.timer_outlined, color: _violet, size: 14),
              SizedBox(width: 6),
              Text('COUNTDOWN TO DEPARTURE', style: TextStyle(color: _sub, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              _cd('$d', 'Days'),
              const SizedBox(width: 8),
              _cd(h.toString().padLeft(2, '0'), 'Hrs'),
              const SizedBox(width: 8),
              _cd(m.toString().padLeft(2, '0'), 'Min'),
              const SizedBox(width: 8),
              _cd(s.toString().padLeft(2, '0'), 'Sec'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cd(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: _surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: _hairline)),
        child: Column(
          children: [
            ShaderMask(
              shaderCallback: (r) => const LinearGradient(colors: [_violet, _pink]).createShader(r),
              child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            ),
            Text(label.toUpperCase(), style: const TextStyle(color: _sub, fontSize: 9.5, fontWeight: FontWeight.w600, letterSpacing: 0.6)),
          ],
        ),
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(color: _surface2, borderRadius: BorderRadius.circular(13), border: Border.all(color: _hairline)),
          child: Column(
            children: [
              Icon(icon, color: _ink, size: 19),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(color: _ink, fontSize: 11.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- 2. TIMELINE ----------
  Widget _timeline() {
    return Column(
      children: [
        _buildBar(),
        const SizedBox(height: 12),
        if (_generated != null)
          for (int i = 0; i < _generated!.length; i++) _genDayCard(_generated![i], i == _generated!.length - 1)
        else if (widget.plan.itinerary.isNotEmpty)
          for (int i = 0; i < widget.plan.itinerary.length; i++)
            _dayCard(widget.plan.itinerary[i], i == widget.plan.itinerary.length - 1)
        else
          _emptyCard('Tap “Build itinerary with AI” to generate a day-by-day plan.'),
      ],
    );
  }

  /// The Build / Regenerate control for the AI day-by-day itinerary.
  Widget _buildBar() {
    if (_building) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [_violet.withOpacity(0.9), _pink.withOpacity(0.9)]),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white)),
            SizedBox(width: 12),
            Text('Building your itinerary…', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5)),
          ],
        ),
      );
    }
    if (_generated == null) {
      return InkWell(
        onTap: _buildAiItinerary,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_violet, _pink]),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: _violet.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 19),
              SizedBox(width: 9),
              Text('Build itinerary with AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
            ],
          ),
        ),
      );
    }
    // generated: show a header + regenerate
    return Row(
      children: [
        _pill('AI itinerary', _violet, dot: true),
        const Spacer(),
        InkWell(
          onTap: _buildAiItinerary,
          borderRadius: BorderRadius.circular(11),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: _surface2, borderRadius: BorderRadius.circular(11), border: Border.all(color: _hairline)),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.refresh_rounded, color: _ink, size: 15),
                SizedBox(width: 6),
                Text('Regenerate', style: TextStyle(color: _ink, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _buildAiItinerary() async {
    setState(() => _building = true);
    try {
      final raw = await _api.aiBuildItinerary(
        start: _origin,
        end: _dest,
        days: widget.plan.estimatedDays,
        travellers: widget.travellers,
        startDate: '${_weekdays[_tripStart.weekday - 1]}, ${_fmtDate(_tripStart)} ${_tripStart.year}',
        startTime: _fmtTime(_tripStart),
        weather: _weatherSummary(),
      );
      final days = raw.map(_GenDay.fromJson).where((d) => d.activities.isNotEmpty).toList();
      if (!mounted) return;
      if (days.isEmpty) {
        setState(() => _building = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn’t generate an itinerary — please try again.')),
        );
        return;
      }
      setState(() {
        _generated = days;
        _doneActivities.clear();
        _building = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _building = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Itinerary build failed: $e')));
    }
  }

  Widget _genDayCard(_GenDay day, bool isLast) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_violet, _pink], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('DAY', style: TextStyle(color: Colors.white70, fontSize: 7.5, fontWeight: FontWeight.w700, height: 1)),
                    Text(day.day.toString().padLeft(2, '0'),
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, height: 1.1)),
                  ],
                ),
              ),
              if (!isLast) Expanded(child: Container(width: 2, color: _hairline, margin: const EdgeInsets.symmetric(vertical: 4))),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: _hairline)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(day.title,
                        style: const TextStyle(color: _ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    for (int i = 0; i < day.activities.length; i++) _activityRow(day.day, i, day.activities[i]),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _activityRow(int dayNum, int idx, _GenActivity a) {
    final key = '$dayNum-$idx';
    final done = _doneActivities.contains(key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_partEmoji(a.part), style: const TextStyle(fontSize: 14)),
                if (a.time.isNotEmpty)
                  Text(a.time, style: const TextStyle(color: _sub, fontSize: 10.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.part.toUpperCase(),
                    style: const TextStyle(color: _brand, fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                const SizedBox(height: 1),
                Text(a.title,
                    style: TextStyle(
                      color: done ? _sub : _ink,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      decoration: done ? TextDecoration.lineThrough : null,
                    )),
                if (a.note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(a.note, style: const TextStyle(color: _sub, fontSize: 11.5, height: 1.3)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => setState(() => done ? _doneActivities.remove(key) : _doneActivities.add(key)),
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: done ? _success : _surface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: done ? _success : _hairline, width: 2),
              ),
              child: done ? const Icon(Icons.check_rounded, color: Colors.white, size: 15) : null,
            ),
          ),
        ],
      ),
    );
  }

  String _partEmoji(String part) {
    final p = part.toLowerCase();
    if (p.contains('morning')) return '☀️';
    if (p.contains('after')) return '🍴';
    if (p.contains('even')) return '🌆';
    if (p.contains('night')) return '🌙';
    return '📍';
  }

  Widget _dayCard(DayPlan day, bool isLast) {
    // rest breaks that fall within this day's km range
    final breaks = widget.plan.restStops
        .where((r) => r.distanceFromStartKm >= day.fromKm && r.distanceFromStartKm <= day.toKm)
        .toList();
    final driveH = day.driveHours;
    final hrs = driveH.floor();
    final mins = ((driveH - hrs) * 60).round();

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // rail
          Column(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_violet, _pink], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('DAY', style: TextStyle(color: Colors.white70, fontSize: 7.5, fontWeight: FontWeight.w700, height: 1)),
                    Text(day.day.toString().padLeft(2, '0'),
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, height: 1.1)),
                  ],
                ),
              ),
              if (!isLast) Expanded(child: Container(width: 2, color: _hairline, margin: const EdgeInsets.symmetric(vertical: 4))),
            ],
          ),
          const SizedBox(width: 12),
          // content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: _hairline)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            day.isFinal ? 'Arrive at $_dest' : 'Day ${day.day} · on the road',
                            style: const TextStyle(color: _ink, fontSize: 14.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (day.isFinal) _pill('Destination', _coral),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 14,
                      runSpacing: 6,
                      children: [
                        _metaItem(Icons.route_rounded, '${day.distanceKm.toStringAsFixed(0)} km'),
                        _metaItem(Icons.schedule_rounded, hrs > 0 ? '${hrs}h ${mins}m drive' : '${mins}m drive'),
                        _metaItem(Icons.flag_rounded, 'to ${day.toKm.toStringAsFixed(0)} km'),
                      ],
                    ),
                    if (widget.plan.departureAdvice != null && day.day == 1 && widget.plan.departureAdvice!.recommendation.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _inlineNote(Icons.wb_sunny_rounded, widget.plan.departureAdvice!.recommendation, _amber),
                    ],
                    for (final b in breaks) ...[
                      const SizedBox(height: 8),
                      _inlineNote(Icons.local_cafe_rounded, '${b.label} · ${b.distanceFromStartKm.toStringAsFixed(0)} km', _brand),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: _sub, size: 13),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: _sub, fontSize: 11.5)),
      ],
    );
  }

  Widget _inlineNote(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(11), border: Border.all(color: color.withOpacity(0.25))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: _ink, fontSize: 12, height: 1.3))),
        ],
      ),
    );
  }

  // ---------- 3. BUDGET ----------
  Widget _budget() {
    final b = widget.plan.budget;
    if (b == null) return _emptyCard('Budget estimate is not available for this trip yet.');
    final segments = <_Seg>[
      _Seg('Stay', b.stay, _violet),
      _Seg('Fuel', b.fuel, _brand),
      _Seg('Food', b.food, _amber),
      _Seg('Tolls', b.tolls, _coral),
      _Seg('Buffer', b.buffer, _info),
    ].where((s) => s.value > 0).toList();
    final total = b.total > 0 ? b.total : segments.fold<int>(0, (a, s) => a + s.value);
    final perPerson = widget.travellers > 0 ? (total / widget.travellers).round() : total;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: _hairline)),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 124,
                height: 124,
                child: CustomPaint(
                  painter: _PiePainter(segments, total),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_cur(total), style: const TextStyle(color: _ink, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                        const Text('TOTAL', style: TextStyle(color: _sub, fontSize: 9.5, fontWeight: FontWeight.w600, letterSpacing: 0.6)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    for (final s in segments) _legendRow(s, total),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _budgetMetric(_curFull(perPerson), 'Per person'),
              const SizedBox(width: 9),
              _budgetMetric(_curFull(b.perDay), 'Per day'),
              const SizedBox(width: 9),
              _budgetMetric('${b.nights}', b.nights == 1 ? 'Night' : 'Nights'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendRow(_Seg s, int total) {
    final pct = total > 0 ? (s.value / total * 100).round() : 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(width: 11, height: 11, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 8),
          Text(s.label, style: const TextStyle(color: _ink, fontSize: 12.5)),
          const SizedBox(width: 6),
          Text('$pct%', style: const TextStyle(color: _sub, fontSize: 11)),
          const Spacer(),
          Text(_curFull(s.value), style: const TextStyle(color: _ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _budgetMetric(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(color: _surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: _hairline)),
        child: Column(
          children: [
            Text(value, style: const TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w800)),
            Text(label, style: const TextStyle(color: _sub, fontSize: 10.5)),
          ],
        ),
      ),
    );
  }

  // ---------- 4. WEATHER ----------
  Widget _weather() {
    final w = widget.plan.weather;
    if (w == null || w.points.isEmpty) {
      return _emptyCard('Weather along the route is not available for this trip.');
    }
    // sample up to ~7 points spread along the route
    final pts = _sample(w.points, 7);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: _hairline)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_wxEmoji(pts.first.icon), style: const TextStyle(fontSize: 34)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pts.first.tempC != null ? '${pts.first.tempC!.round()}°C' : '—',
                        style: const TextStyle(color: _ink, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1, height: 1)),
                    Text('${pts.first.description} at start', style: const TextStyle(color: _sub, fontSize: 12.5)),
                  ],
                ),
              ),
              if (w.hasAlerts) _pill('Alerts', _coral, dot: true),
            ],
          ),
          const SizedBox(height: 14),
          const Text('ALONG YOUR ROUTE', style: TextStyle(color: _sub, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in pts) _wxChip(p),
              ],
            ),
          ),
          if (widget.plan.departureAdvice != null && widget.plan.departureAdvice!.recommendation.isNotEmpty) ...[
            const SizedBox(height: 14),
            _inlineNote(Icons.auto_awesome_rounded, widget.plan.departureAdvice!.recommendation, _brand),
          ],
        ],
      ),
    );
  }

  Widget _wxChip(WeatherPoint p) {
    return Container(
      width: 66,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(color: _surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: _hairline)),
      child: Column(
        children: [
          Text('${p.distanceFromStartKm.toStringAsFixed(0)} km', style: const TextStyle(color: _sub, fontSize: 10)),
          const SizedBox(height: 4),
          Text(_wxEmoji(p.icon), style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          Text(p.tempC != null ? '${p.tempC!.round()}°' : '—', style: const TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w700)),
          if (p.rainChancePct != null) Text('${p.rainChancePct}%', style: const TextStyle(color: _info, fontSize: 9.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ---------- Packing ----------
  Widget _packingCard() {
    final total = _packing.values.fold<int>(0, (a, l) => a + l.length);
    final done = _packed.length;
    final pct = total > 0 ? done / total : 0.0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: _hairline)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 58,
                height: 58,
                child: CustomPaint(
                  painter: _RingPainter(pct),
                  child: Center(child: Text('${(pct * 100).round()}%', style: const TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w800))),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$done of $total packed', style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    const Text('AI-generated for your trip length & weather', style: TextStyle(color: _sub, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final entry in _packing.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 2),
              child: Text(entry.key.toUpperCase(), style: const TextStyle(color: _sub, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            ),
            for (final item in entry.value) _packRow(item),
          ],
        ],
      ),
    );
  }

  Widget _packRow(String item) {
    final on = _packed.contains(item);
    return InkWell(
      onTap: () => setState(() => on ? _packed.remove(item) : _packed.add(item)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: on ? _brand : _surface2,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: on ? _brand : _hairline, width: 2),
              ),
              child: on ? const Icon(Icons.check_rounded, color: Colors.white, size: 15) : null,
            ),
            const SizedBox(width: 11),
            Text(
              item,
              style: TextStyle(
                color: on ? _sub : _ink,
                fontSize: 13.5,
                decoration: on ? TextDecoration.lineThrough : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 5. AI ASSISTANT ----------
  Widget _assistant() {
    const suggestions = [
      'What should I do on day 1?',
      'Best places to eat on the way',
      'How can I save on this budget?',
      'Anything I should pack?',
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_violet.withOpacity(0.12), _surface],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _violet.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final m in _chat) _bubble(m),
          if (_aiLoading) _bubble(_Msg(false, '…'), typing: true),
          const SizedBox(height: 6),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final s in suggestions) _suggestion(s),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: _hairline)),
            padding: const EdgeInsets.only(left: 14, right: 6, top: 4, bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatCtrl,
                    style: const TextStyle(color: _ink, fontSize: 13),
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (v) => _ask(v),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Ask anything about your trip…',
                      hintStyle: TextStyle(color: _sub, fontSize: 13),
                    ),
                  ),
                ),
                InkWell(
                  onTap: _aiLoading ? null : () => _ask(_chatCtrl.text),
                  borderRadius: BorderRadius.circular(11),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [_violet, _pink]),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 19),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(_Msg m, {bool typing = false}) {
    if (m.fromUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_violet, _pink]),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(m.text, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.35)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [_violet, _pink]), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 17),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                border: Border.all(color: _hairline),
              ),
              child: typing
                  ? const SizedBox(
                      height: 16,
                      width: 30,
                      child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _violet))),
                    )
                  : Text(m.text, style: const TextStyle(color: _ink, fontSize: 13, height: 1.4)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestion(String s) {
    return InkWell(
      onTap: _aiLoading ? null : () => _ask(s),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: _hairline)),
        child: Text(s, style: const TextStyle(color: _ink, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Future<void> _ask(String q) async {
    final question = q.trim();
    if (question.isEmpty || _aiLoading) return;
    _chatCtrl.clear();
    setState(() {
      _chat.add(_Msg(true, question));
      _aiLoading = true;
    });
    try {
      final answer = await _api.aiAsk(question: question, context: {
        'from': _origin,
        'to': _dest,
        'distanceKm': widget.plan.distanceKm.round(),
        'days': widget.plan.estimatedDays,
        'travellers': widget.travellers,
        if (widget.plan.budget != null) 'budgetTotal': widget.plan.budget!.total,
        'startDate': _fmtDate(_tripStart),
      });
      if (mounted) setState(() => _chat.add(_Msg(false, answer.trim().isEmpty ? 'I could not find an answer for that.' : answer.trim())));
    } catch (e) {
      if (mounted) setState(() => _chat.add(_Msg(false, "I couldn't reach the assistant right now. Please try again.")));
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  // ---------- helpers ----------
  Widget _pill(String text, Color color, {bool dot = false, bool glass = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: glass ? Colors.black.withOpacity(0.3) : color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: glass ? Border.all(color: Colors.white.withOpacity(0.25)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 5),
          ],
          Text(text, style: TextStyle(color: glass ? Colors.white : color, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _emptyCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: _hairline)),
      child: Text(text, style: const TextStyle(color: _sub, fontSize: 13)),
    );
  }

  /// Compact forecast summary the AI planner can reason over (temps, rain
  /// chance along the route + best-departure advice).
  String _weatherSummary() {
    final w = widget.plan.weather;
    final parts = <String>[];
    if (w != null && w.points.isNotEmpty) {
      for (final p in _sample(w.points, 4)) {
        final t = p.tempC != null ? ' ${p.tempC!.round()}°C' : '';
        final rain = p.rainChancePct != null ? ', ${p.rainChancePct}% rain' : '';
        parts.add('${p.distanceFromStartKm.toStringAsFixed(0)}km ${p.description}$t$rain');
      }
    }
    final adv = widget.plan.departureAdvice?.recommendation ?? '';
    final summary = [
      if (parts.isNotEmpty) parts.join('; '),
      if (adv.isNotEmpty) adv,
    ].join('. ');
    return summary;
  }

  List<WeatherPoint> _sample(List<WeatherPoint> pts, int n) {
    if (pts.length <= n) return pts;
    final out = <WeatherPoint>[];
    final step = (pts.length - 1) / (n - 1);
    for (int i = 0; i < n; i++) {
      out.add(pts[(i * step).round().clamp(0, pts.length - 1)]);
    }
    return out;
  }

  String _wxEmoji(String icon) {
    switch (icon) {
      case 'clear':
        return '☀️';
      case 'partly_cloudy':
        return '⛅';
      case 'cloudy':
        return '☁️';
      case 'fog':
        return '🌫️';
      case 'drizzle':
        return '🌦️';
      case 'rain':
        return '🌧️';
      case 'snow':
        return '❄️';
      case 'thunderstorm':
        return '⛈️';
      default:
        return '🌤️';
    }
  }

  String _openingLine() {
    final days = widget.plan.estimatedDays;
    return "Hi! I'm your trip assistant for $_origin → $_dest — "
        "${widget.plan.distanceKm.toStringAsFixed(0)} km over $days ${days == 1 ? 'day' : 'days'}. "
        "Ask me about your schedule, budget, food stops, or what to pack.";
  }

  Map<String, List<String>> _generatePacking() {
    final days = widget.plan.estimatedDays;
    final pts = widget.plan.weather?.points ?? const [];
    final rainy = pts.any((p) => (p.rainChancePct ?? 0) >= 40) || (widget.plan.departureAdvice?.nowRainPct ?? 0) >= 40;
    final hot = pts.any((p) => (p.tempC ?? 0) >= 30);
    final cold = pts.any((p) => (p.tempC ?? 99) <= 12);

    final clothes = <String>[
      '${math.max(2, days)} shirts / tops',
      'Comfortable walking shoes',
      'Sleepwear',
    ];
    if (hot) clothes.addAll(['Sunglasses', 'Cap / hat']);
    if (cold) clothes.add('Warm jacket / sweater');
    if (rainy) clothes.add('Rain jacket / umbrella');

    return {
      'Essentials': ['Wallet + cash', 'Phone', 'Water bottle', 'Snacks for the road'],
      'Clothes': clothes,
      'Electronics': ['Phone charger', 'Power bank', 'Car phone mount', 'Earphones'],
      'Documents': ['Driving license', 'ID proof', 'Booking confirmations', 'Vehicle papers'],
      'Health': ['Basic medicines', 'First-aid kit', if (hot) 'Sunscreen', 'Hand sanitizer'],
    };
  }

  // ---------- actions ----------
  void _share() {
    final b = widget.plan.budget;
    final sb = StringBuffer()
      ..writeln('🧭 ${_origin} → ${_dest}')
      ..writeln('${_fmtDateRange()} · ${widget.plan.estimatedDays} days · ${widget.plan.distanceKm.toStringAsFixed(0)} km')
      ..writeln('${widget.travellers} traveller${widget.travellers == 1 ? '' : 's'}');
    if (b != null) sb.writeln('Est. budget: ${_curFull(b.total)} (${_curFull(b.perDay)}/day)');
    sb.writeln('\nPlanned with Voyplan');
    Share.share(sb.toString(), subject: 'My trip: $_origin → $_dest');
  }

  /// Saves the complete trip — route, vehicle, chosen start date/time, and the
  /// generated day-by-day itinerary — to the user's account.
  Future<void> _saveTrip() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please log in to save trips.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await _api.saveTrip(
        name: '$_origin to $_dest',
        start: widget.start,
        end: widget.end,
        waypoints: widget.waypoints,
        vehicleType: widget.vehicleType,
        token: session.accessToken,
        tripStart: _tripStart,
        itinerary: _generated?.map((d) => d.toJson()).toList(),
      );
      if (!mounted) return;
      setState(() => _saving = false);
      final withPlan = _generated != null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(withPlan ? 'Trip + itinerary saved ✓' : 'Trip saved ✓')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  Future<void> _addToCalendar() async {
    await addTripToCalendar(
      title: 'Trip: $_origin → $_dest',
      description: '${widget.plan.distanceKm.toStringAsFixed(0)} km · ${widget.plan.estimatedDays} days · planned with Voyplan',
      location: _dest,
      start: _tripStart,
      end: _endDate.add(const Duration(hours: 20)),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Calendar file ready — open it to add the trip to your calendar')),
      );
    }
  }
}

// ---------- support types ----------
class _Msg {
  final bool fromUser;
  final String text;
  _Msg(this.fromUser, this.text);
}

class _GenActivity {
  final String part;
  final String time;
  final String title;
  final String note;
  _GenActivity({required this.part, required this.time, required this.title, required this.note});

  Map<String, dynamic> toJson() => {'part': part, 'time': time, 'title': title, 'note': note};
}

class _GenDay {
  final int day;
  final String title;
  final List<_GenActivity> activities;
  _GenDay({required this.day, required this.title, required this.activities});

  Map<String, dynamic> toJson() => {'day': day, 'title': title, 'activities': activities.map((a) => a.toJson()).toList()};

  factory _GenDay.fromJson(Map<String, dynamic> j) {
    final acts = (j['activities'] as List? ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .map((a) => _GenActivity(
              part: (a['part'] ?? '').toString(),
              time: (a['time'] ?? '').toString(),
              title: (a['title'] ?? '').toString(),
              note: (a['note'] ?? '').toString(),
            ))
        .where((a) => a.title.isNotEmpty)
        .toList();
    return _GenDay(
      day: (j['day'] as num?)?.toInt() ?? 1,
      title: (j['title'] ?? 'Day').toString(),
      activities: acts,
    );
  }
}

class _Seg {
  final String label;
  final int value;
  final Color color;
  _Seg(this.label, this.value, this.color);
}

class _PiePainter extends CustomPainter {
  final List<_Seg> segments;
  final int total;
  _PiePainter(this.segments, this.total);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final stroke = radius * 0.30;
    final rect = Rect.fromCircle(center: center, radius: radius - stroke / 2);
    double start = -math.pi / 2;
    final sum = total > 0 ? total : segments.fold<int>(0, (a, s) => a + s.value);
    if (sum <= 0) return;
    for (final s in segments) {
      final sweep = (s.value / sum) * 2 * math.pi;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..color = s.color;
      canvas.drawArc(rect, start + 0.02, sweep - 0.04, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter old) => old.segments != segments || old.total != total;
}

class _RingPainter extends CustomPainter {
  final double pct;
  _RingPainter(this.pct);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 4;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = _surface2;
    canvas.drawCircle(center, radius, bg);
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(colors: [_brand, _violet]).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * pct.clamp(0.0, 1.0), false, fg);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.pct != pct;
}
