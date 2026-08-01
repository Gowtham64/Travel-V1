import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:share_plus/share_plus.dart';
// Web download vs. non-web stub (mobile shares via the OS instead).
import 'calendar_export_stub.dart' if (dart.library.html) 'calendar_export_web.dart';

String _stamp(DateTime d) {
  final u = d.toUtc();
  String p2(int n) => n.toString().padLeft(2, '0');
  return '${u.year}${p2(u.month)}${p2(u.day)}T${p2(u.hour)}${p2(u.minute)}00Z';
}

String _esc(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll(',', '\\,')
    .replaceAll(';', '\\;')
    .replaceAll('\n', '\\n');

/// Builds a standard iCalendar (.ics) event.
String buildIcs({
  required String title,
  required String description,
  required String location,
  required DateTime start,
  required DateTime end,
}) {
  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Voyplan//Trip//EN',
    'CALSCALE:GREGORIAN',
    'BEGIN:VEVENT',
    'UID:${start.millisecondsSinceEpoch}@voyplan',
    'DTSTAMP:${_stamp(DateTime.now())}',
    'DTSTART:${_stamp(start)}',
    'DTEND:${_stamp(end)}',
    'SUMMARY:${_esc(title)}',
    'DESCRIPTION:${_esc(description)}',
    'LOCATION:${_esc(location)}',
    'END:VEVENT',
    'END:VCALENDAR',
  ].join('\r\n');
}

/// Adds a trip to the user's calendar via a standard .ics file — the OS/browser
/// routes it to whatever calendar app they use (not forced to Google). On web
/// it downloads the file; on mobile it opens the share sheet.
Future<void> addTripToCalendar({
  required String title,
  required String description,
  required String location,
  required DateTime start,
  required DateTime end,
  String filename = 'voyplan-trip.ics',
}) async {
  final ics = buildIcs(title: title, description: description, location: location, start: start, end: end);
  if (kIsWeb) {
    downloadIcs(filename, ics);
  } else {
    final bytes = Uint8List.fromList(utf8.encode(ics));
    await Share.shareXFiles(
      [XFile.fromData(bytes, mimeType: 'text/calendar', name: filename)],
      subject: title,
    );
  }
}
