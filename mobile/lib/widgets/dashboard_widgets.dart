import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../models/trip_extras.dart';

/// Shared card shell for the dashboard sidebar widgets.
class DashCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? action;
  const DashCard({super.key, required this.title, required this.icon, required this.child, this.action});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Voy.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Voy.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Voy.sub, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title.toUpperCase(),
                    style: const TextStyle(color: Voy.sub, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
              ),
              if (action != null) action!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Currency mini-converter (live rate via backend)
// ─────────────────────────────────────────────────────────────────────────────

class CurrencyMiniCard extends StatefulWidget {
  const CurrencyMiniCard({super.key});
  @override
  State<CurrencyMiniCard> createState() => _CurrencyMiniCardState();
}

class _CurrencyMiniCardState extends State<CurrencyMiniCard> {
  final _api = ApiService();
  static const _currencies = ['USD', 'INR', 'EUR', 'GBP', 'AED', 'SGD', 'JPY', 'AUD'];
  String _from = 'USD', _to = 'INR';
  final _amount = TextEditingController(text: '100');
  String? _result, _rate;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _convert();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _convert() async {
    final amt = double.tryParse(_amount.text.trim());
    if (amt == null) return;
    setState(() => _loading = true);
    try {
      final r = await _api.convertCurrency(from: _from, to: _to, amount: amt);
      if (!mounted) return;
      setState(() {
        _result = '${r['result']}';
        _rate = '1 $_from = ${r['rate']} $_to';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _result = null;
        _rate = 'Rate unavailable';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DashCard(
      title: 'Currency',
      icon: Icons.currency_exchange_rounded,
      action: IconButton(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: _loading
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.refresh_rounded, color: Voy.sub, size: 18),
        onPressed: _loading ? null : _convert,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.w800, fontSize: 18),
                  decoration: const InputDecoration(isDense: true, labelText: 'From'),
                  onSubmitted: (_) => _convert(),
                ),
              ),
              const SizedBox(width: 8),
              _ccyDropdown(_from, (v) => setState(() => _from = v)),
            ],
          ),
          const SizedBox(height: 6),
          Center(
            child: IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.swap_vert_rounded, color: Voy.brand),
              onPressed: () {
                setState(() {
                  final t = _from;
                  _from = _to;
                  _to = t;
                });
                _convert();
              },
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(_result == null ? '—' : '$_to $_result',
                    style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.w800, fontSize: 18)),
              ),
              const SizedBox(width: 8),
              _ccyDropdown(_to, (v) => setState(() => _to = v)),
            ],
          ),
          if (_rate != null) ...[
            const SizedBox(height: 6),
            Text(_rate!, style: const TextStyle(color: Voy.sub, fontSize: 11.5)),
          ],
        ],
      ),
    );
  }

  Widget _ccyDropdown(String value, ValueChanged<String> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Voy.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Voy.hairline),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          dropdownColor: Voy.surface,
          style: const TextStyle(color: Voy.ink, fontSize: 13, fontWeight: FontWeight.w700),
          items: [for (final c in _currencies) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: (v) {
            if (v == null) return;
            onChanged(v);
            _convert();
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Timezones (live clocks for a few cities)
// ─────────────────────────────────────────────────────────────────────────────

class TimezonesCard extends StatefulWidget {
  const TimezonesCard({super.key});
  @override
  State<TimezonesCard> createState() => _TimezonesCardState();
}

class _TimezonesCardState extends State<TimezonesCard> {
  Timer? _timer;

  // City → UTC offset in minutes (standard offsets; not DST-adjusted).
  static const _zones = <String, int>{
    'India (IST)': 330,
    'Dubai': 240,
    'London': 60,
    'New York': -240,
    'Tokyo': 540,
  };

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmt(int offsetMin) {
    final t = DateTime.now().toUtc().add(Duration(minutes: offsetMin));
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _gmt(int offsetMin) {
    final sign = offsetMin >= 0 ? '+' : '-';
    final a = offsetMin.abs();
    final h = a ~/ 60, m = a % 60;
    return 'GMT$sign$h${m == 0 ? '' : ':${m.toString().padLeft(2, '0')}'}';
  }

  @override
  Widget build(BuildContext context) {
    return DashCard(
      title: 'Timezones',
      icon: Icons.public_rounded,
      child: Column(
        children: [
          for (final e in _zones.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: Voy.surface2,
                    child: Text(e.key[0], style: const TextStyle(color: Voy.sub, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.key, style: const TextStyle(color: Voy.ink, fontSize: 13, fontWeight: FontWeight.w600)),
                        Text(_gmt(e.value), style: const TextStyle(color: Voy.sub, fontSize: 10.5)),
                      ],
                    ),
                  ),
                  Text(_fmt(e.value), style: const TextStyle(color: Voy.ink, fontSize: 15, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Upcoming reservations (aggregated from every trip's saved bookings)
// ─────────────────────────────────────────────────────────────────────────────

class UpcomingReservationsCard extends StatefulWidget {
  const UpcomingReservationsCard({super.key});
  @override
  State<UpcomingReservationsCard> createState() => _UpcomingReservationsCardState();
}

class _UpcomingReservationsCardState extends State<UpcomingReservationsCard> {
  List<Reservation> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.endsWith('.reservations'));
      final all = <Reservation>[];
      for (final k in keys) {
        final raw = prefs.getString(k);
        if (raw == null || raw.isEmpty) continue;
        try {
          final list = jsonDecode(raw) as List;
          all.addAll(list.map((e) => Reservation.fromJson((e as Map).cast<String, dynamic>())));
        } catch (_) {}
      }
      final today = DateTime.now().subtract(const Duration(days: 1));
      final upcoming = all.where((r) => r.date != null && r.date!.isAfter(today)).toList()
        ..sort((a, b) => a.date!.compareTo(b.date!));
      if (!mounted) return;
      setState(() {
        _items = upcoming.take(5).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  IconData _icon(String t) {
    switch (t) {
      case 'flight':
        return Icons.flight_rounded;
      case 'hotel':
        return Icons.hotel_rounded;
      case 'restaurant':
        return Icons.restaurant_rounded;
      case 'activity':
        return Icons.local_activity_rounded;
      default:
        return Icons.confirmation_number_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DashCard(
      title: 'Upcoming reservations',
      icon: Icons.event_available_rounded,
      child: _loading
          ? const Padding(padding: EdgeInsets.all(8), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
          : _items.isEmpty
              ? Text('No upcoming bookings yet. Add them in a trip’s Bookings tab.',
                  style: TextStyle(color: Voy.sub.withValues(alpha: 0.85), fontSize: 12.5))
              : Column(
                  children: [
                    for (final r in _items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: Voy.surface2, borderRadius: BorderRadius.circular(11)),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('${r.date!.day}', style: const TextStyle(color: Voy.ink, fontSize: 13, fontWeight: FontWeight.w800, height: 1)),
                                  Text(_month(r.date!.month), style: const TextStyle(color: Voy.sub, fontSize: 8.5, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(r.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Voy.ink, fontSize: 13, fontWeight: FontWeight.w600)),
                            ),
                            Icon(_icon(r.type), color: Voy.brand, size: 18),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }

  String _month(int m) => const ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'][m - 1];
}
