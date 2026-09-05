import 'dart:math' as math;

/// Canonical datetime and time utility for VoyPlan.
///
/// Guarantees:
/// - 12-hour <-> 24-hour conversions are 100% mathematically correct.
///   (12:00 AM = 00:00, 1:00 AM = 01:00, 11:59 AM = 11:59,
///    12:00 PM = 12:00, 1:00 PM = 13:00, 2:00 PM = 14:00, 11:59 PM = 23:59).
/// - 2:00 PM is NEVER accidentally converted to 2:00 AM.
/// - Canonical datetime representation: local time + timezone.
/// - Validates and re-anchors generated itinerary timelines to match the selected start time.
class TripDateTime {
  TripDateTime._();

  /// Converts any time string (12h or 24h) or hour+minute integers to canonical 24-hour format "HH:mm".
  ///
  /// Examples:
  /// - to24Hour(14, 0) -> "14:00"
  /// - to24Hour(2, 0) -> "02:00"
  /// - to24Hour("2:00 PM") -> "14:00"
  /// - to24Hour("2:00 AM") -> "02:00"
  /// - to24Hour("12:00 AM") -> "00:00"
  /// - to24Hour("12:00 PM") -> "12:00"
  static String to24Hour(dynamic input, [int? minute]) {
    if (input is int && minute != null) {
      final h = (input % 24).toString().padLeft(2, '0');
      final m = (minute % 60).toString().padLeft(2, '0');
      return '$h:$m';
    }
    final minutes = parseMinutes(input?.toString() ?? '');
    final h24 = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    return '${h24.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  /// Converts any time string (12h or 24h) or hour+minute to canonical 12-hour format "h:mm AM/PM".
  ///
  /// Examples:
  /// - "14:00" -> "2:00 PM"
  /// - "02:00" -> "2:00 AM"
  /// - "00:00" -> "12:00 AM"
  /// - "12:00" -> "12:00 PM"
  /// - "2:00 PM" -> "2:00 PM"
  static String to12Hour(dynamic input, [int? minute]) {
    if (input is int && minute != null) {
      return formatTimeDisplay(DateTime(2026, 1, 1, input, minute));
    }
    final minutes = parseMinutes(input?.toString() ?? '');
    final norm = minutes % (24 * 60);
    final h24 = norm ~/ 60;
    final m = norm % 60;
    final ampm = h24 >= 12 ? 'PM' : 'AM';
    final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
    return '$h12:${m.toString().padLeft(2, '0')} $ampm';
  }

  /// Parses any time string into total minutes from midnight (0..1439).
  ///
  /// Handles:
  /// - "2:00 PM", "2:00pm", "02:00 PM", "2 PM"
  /// - "2:00 AM", "2:00am", "02:00 AM", "12:00 AM", "12:00 PM"
  /// - "14:00", "02:00", "00:00"
  static int parseMinutes(String input) {
    final clean = input.trim().toLowerCase();
    if (clean.isEmpty) return 480; // default 08:00 AM

    final hasPm = clean.contains('pm') || clean.contains('p.m');
    final hasAm = clean.contains('am') || clean.contains('a.m');

    // Extract digits and colon
    final match = RegExp(r'(\d{1,2})(?::(\d{1,2}))?').firstMatch(clean);
    if (match != null) {
      int h = int.tryParse(match.group(1) ?? '8') ?? 8;
      final m = int.tryParse(match.group(2) ?? '0') ?? 0;

      if (hasPm) {
        if (h < 12) h += 12;
      } else if (hasAm) {
        if (h == 12) h = 0;
      }
      final clampedH = math.max(0, math.min(h, 23));
      final clampedM = math.max(0, math.min(m, 59));
      return clampedH * 60 + clampedM;
    }

    return 480;
  }

  /// Returns canonical display string for a DateTime: e.g. "2:00 PM"
  static String formatTimeDisplay(DateTime dt) {
    final h24 = dt.hour;
    final m = dt.minute;
    final ampm = h24 >= 12 ? 'PM' : 'AM';
    final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
    return '$h12:${m.toString().padLeft(2, '0')} $ampm';
  }

  /// Returns canonical display string for date: e.g. "Sat, 5 Sep" or "Saturday, September 5, 2026"
  static String formatDateDisplay(DateTime dt, {bool full = false}) {
    const weekdaysShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const weekdaysFull = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const monthsFull = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

    final wd = full ? weekdaysFull[dt.weekday - 1] : weekdaysShort[dt.weekday - 1];
    final mo = full ? monthsFull[dt.month - 1] : monthsShort[dt.month - 1];

    if (full) {
      return '$wd, $mo ${dt.day}, ${dt.year}';
    }
    return '$wd, ${dt.day} $mo';
  }

  /// Returns full canonical datetime label: e.g. "Sat, 5 Sep · 2:00 PM"
  static String formatFullDisplay(DateTime dt) {
    return '${formatDateDisplay(dt)} · ${formatTimeDisplay(dt)}';
  }

  /// Returns canonical ISO string in local timezone: "YYYY-MM-DD HH:mm"
  static String toCanonicalLocalIso(DateTime dt, [int? hour, int? minute]) {
    final effectiveDt = (hour != null && minute != null)
        ? DateTime(dt.year, dt.month, dt.day, hour, minute)
        : dt;
    final y = effectiveDt.year.toString().padLeft(4, '0');
    final m = effectiveDt.month.toString().padLeft(2, '0');
    final d = effectiveDt.day.toString().padLeft(2, '0');
    final h = effectiveDt.hour.toString().padLeft(2, '0');
    final min = effectiveDt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  /// Format minutes from midnight to "h:mm AM/PM"
  static String formatMinutes(int totalMin) {
    final norm = totalMin % (24 * 60);
    final h24 = norm ~/ 60;
    final m = norm % 60;
    final ampm = h24 >= 12 ? 'PM' : 'AM';
    final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
    return '$h12:${m.toString().padLeft(2, '0')} $ampm';
  }

  /// Validates and re-anchors Day 1 activities and timeline blocks so that Day 1 begins at the exact requested start time.
  static List<Map<String, dynamic>> validateAndReanchorDays(
    List<dynamic> rawDays, {
    required int startMinutes,
  }) {
    if (rawDays.isEmpty) return [];
    final List<Map<String, dynamic>> result = [];
    for (int i = 0; i < rawDays.length; i++) {
      final raw = rawDays[i];
      if (raw is! Map) continue;
      final dayMap = Map<String, dynamic>.from(raw);
      final rawActs = (dayMap['activities'] as List?) ?? [];
      final rawBlocks = (dayMap['blocks'] as List?) ?? [];

      if (rawActs.isNotEmpty) {
        final acts = rawActs
            .whereType<Map>()
            .map((a) => Map<String, dynamic>.from(a))
            .toList();

        if (i == 0 && acts.isNotEmpty) {
          int currentMin = startMinutes;
          for (final act in acts) {
            act['time'] = formatMinutes(currentMin);
            currentMin += 90; // space activities out realistically
            if (currentMin >= 23 * 60) currentMin = 22 * 60;
          }
        }
        dayMap['activities'] = acts;
      }

      if (rawBlocks.isNotEmpty) {
        final blocks = rawBlocks
            .whereType<Map>()
            .map((b) => Map<String, dynamic>.from(b))
            .toList();

        if (i == 0 && blocks.isNotEmpty) {
          int currentMin = startMinutes;
          for (final b in blocks) {
            final dur = (b['durationMin'] as num?)?.toInt() ??
                ((b['travelMin'] as num?)?.toInt() ?? 30);
            final d = dur > 0 ? dur : 30;
            b['start'] = formatMinutes(currentMin);
            b['end'] = formatMinutes(currentMin + d);
            currentMin += d;
          }
        }
        dayMap['blocks'] = blocks;
      }

      result.add(dayMap);
    }
    return result;
  }
}
