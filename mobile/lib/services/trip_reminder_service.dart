import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents a scheduled trip departure reminder.
class TripDepartureReminder {
  final String id;
  final String destination;
  final String startPoint;
  final DateTime departureTime;
  final int remindBeforeMinutes;
  final bool notified;
  final String vehicleType;

  TripDepartureReminder({
    required this.id,
    required this.destination,
    required this.startPoint,
    required this.departureTime,
    this.remindBeforeMinutes = 30,
    this.notified = false,
    this.vehicleType = 'car',
  });

  DateTime get reminderTriggerTime =>
      departureTime.subtract(Duration(minutes: remindBeforeMinutes));

  bool get isDue => DateTime.now().isAfter(reminderTriggerTime);
  bool get isPastDeparture => DateTime.now().isAfter(departureTime);

  Duration get timeUntilDeparture => departureTime.difference(DateTime.now());

  Map<String, dynamic> toJson() => {
        'id': id,
        'destination': destination,
        'startPoint': startPoint,
        'departureTime': departureTime.toIso8601String(),
        'remindBeforeMinutes': remindBeforeMinutes,
        'notified': notified,
        'vehicleType': vehicleType,
      };

  factory TripDepartureReminder.fromJson(Map<String, dynamic> json) =>
      TripDepartureReminder(
        id: json['id'] as String,
        destination: json['destination'] as String,
        startPoint: json['startPoint'] as String? ?? 'Home',
        departureTime: DateTime.parse(json['departureTime'] as String),
        remindBeforeMinutes: json['remindBeforeMinutes'] as int? ?? 30,
        notified: json['notified'] as bool? ?? false,
        vehicleType: json['vehicleType'] as String? ?? 'car',
      );
}

/// Service to manage 30-minute pre-trip departure reminders and notifications.
class TripReminderService {
  TripReminderService._();
  static final TripReminderService instance = TripReminderService._();

  static const MethodChannel _channel =
      MethodChannel('com.travelapp.notification');
  static const String _prefsKey = 'voyplan_departure_reminders_v1';

  final _reminderController =
      StreamController<TripDepartureReminder>.broadcast();
  Stream<TripDepartureReminder> get onReminderDue => _reminderController.stream;

  Timer? _pollingTimer;
  bool _initialized = false;

  /// Initialize the service and start periodic due-check.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Request notification permissions natively on launch
    if (!kIsWeb) {
      try {
        await _channel.invokeMethod('requestPermissions');
      } catch (_) {}
    }

    // Check on startup
    await checkDueReminders();

    // Check every 30 seconds while app is in foreground
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      checkDueReminders();
    });
  }

  /// Schedule a 30-minute departure reminder for an upcoming trip.
  Future<TripDepartureReminder> scheduleDepartureReminder({
    required String tripId,
    required String destination,
    String startPoint = 'Home',
    required DateTime departureTime,
    int remindBeforeMinutes = 30,
    String vehicleType = 'car',
  }) async {
    final reminder = TripDepartureReminder(
      id: tripId,
      destination: destination,
      startPoint: startPoint,
      departureTime: departureTime,
      remindBeforeMinutes: remindBeforeMinutes,
      vehicleType: vehicleType,
    );

    await _saveReminder(reminder);

    final now = DateTime.now();
    final triggerTime = reminder.reminderTriggerTime;
    final secondsUntil = triggerTime.difference(now).inSeconds;

    final formattedDeparture = _formatTime(departureTime);

    final title = '🚗 Trip to $destination in $remindBeforeMinutes mins!';
    final body =
        'Departure is set for $formattedDeparture. Time to finish packing, check vehicle/fuel and get ready!';

    if (!kIsWeb) {
      try {
        await _channel.invokeMethod('scheduleReminder', {
          'id': 'reminder_$tripId',
          'destination': destination,
          'title': title,
          'body': body,
          'secondsFromNow': secondsUntil > 0 ? secondsUntil.toDouble() : 1.0,
          'departureTime': departureTime.toIso8601String(),
        });
      } catch (_) {}
    }

    // If already within 30 minutes, trigger in-app alert immediately
    if (secondsUntil <= 0 && !reminder.isPastDeparture) {
      _reminderController.add(reminder);
    }

    return reminder;
  }

  /// Cancel a scheduled departure reminder.
  Future<void> cancelDepartureReminder(String tripId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getReminders();
    list.removeWhere((r) => r.id == tripId);

    final jsonStr = jsonEncode(list.map((r) => r.toJson()).toList());
    await prefs.setString(_prefsKey, jsonStr);

    if (!kIsWeb) {
      try {
        await _channel.invokeMethod('cancelReminder', {
          'id': 'reminder_$tripId',
        });
      } catch (_) {}
    }
  }

  /// Load all stored reminders.
  Future<List<TripDepartureReminder>> getReminders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_prefsKey);
      if (str == null || str.isEmpty) return [];
      final decoded = jsonDecode(str) as List<dynamic>;
      return decoded
          .map((item) =>
              TripDepartureReminder.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Get next upcoming trip reminder within the next 24 hours.
  Future<TripDepartureReminder?> getNextUpcomingReminder() async {
    final list = await getReminders();
    final now = DateTime.now();
    final upcoming = list.where((r) => r.departureTime.isAfter(now)).toList();
    if (upcoming.isEmpty) return null;
    upcoming.sort((a, b) => a.departureTime.compareTo(b.departureTime));
    return upcoming.first;
  }

  /// Check pending reminders and notify if due.
  Future<void> checkDueReminders() async {
    final list = await getReminders();
    bool updated = false;

    for (int i = 0; i < list.length; i++) {
      final r = list[i];
      if (!r.notified && r.isDue && !r.isPastDeparture) {
        _reminderController.add(r);
        list[i] = TripDepartureReminder(
          id: r.id,
          destination: r.destination,
          startPoint: r.startPoint,
          departureTime: r.departureTime,
          remindBeforeMinutes: r.remindBeforeMinutes,
          notified: true,
          vehicleType: r.vehicleType,
        );
        updated = true;
      }
    }

    if (updated) {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(list.map((r) => r.toJson()).toList());
      await prefs.setString(_prefsKey, jsonStr);
    }
  }

  Future<void> _saveReminder(TripDepartureReminder reminder) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getReminders();
    list.removeWhere((r) => r.id == reminder.id);
    list.add(reminder);

    final jsonStr = jsonEncode(list.map((r) => r.toJson()).toList());
    await prefs.setString(_prefsKey, jsonStr);
  }

  static String _formatTime(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute;
    final ampm = h >= 12 ? 'PM' : 'AM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '${h12.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $ampm';
  }
}
