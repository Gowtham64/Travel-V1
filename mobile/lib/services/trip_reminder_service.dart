import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/trip_date_time.dart';

/// Represents a scheduled trip and its reminder/confirmation state.
class TripDepartureReminder {
  final String id;
  final String destination;
  final String startPoint;
  final DateTime departureTime;
  final int remindBeforeMinutes;
  final bool notified;
  final bool startNotified;
  final String vehicleType;
  final String status; // 'CONFIRMED', 'READY_TO_START', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'
  final List<String> stops;
  final double distanceKm;

  TripDepartureReminder({
    required this.id,
    required this.destination,
    required this.startPoint,
    required this.departureTime,
    this.remindBeforeMinutes = 30,
    this.notified = false,
    this.startNotified = false,
    this.vehicleType = 'car',
    this.status = 'CONFIRMED',
    this.stops = const [],
    this.distanceKm = 0.0,
  });

  DateTime get reminderTriggerTime =>
      departureTime.subtract(Duration(minutes: remindBeforeMinutes));

  bool get isDue => DateTime.now().isAfter(reminderTriggerTime);
  bool get isReadyToStart =>
      DateTime.now().isAfter(departureTime) ||
      DateTime.now().isAtSameMomentAs(departureTime);
  bool get isPastDeparture => DateTime.now().isAfter(departureTime);

  Duration get timeUntilDeparture => departureTime.difference(DateTime.now());

  TripDepartureReminder copyWith({
    String? id,
    String? destination,
    String? startPoint,
    DateTime? departureTime,
    int? remindBeforeMinutes,
    bool? notified,
    bool? startNotified,
    String? vehicleType,
    String? status,
    List<String>? stops,
    double? distanceKm,
  }) {
    return TripDepartureReminder(
      id: id ?? this.id,
      destination: destination ?? this.destination,
      startPoint: startPoint ?? this.startPoint,
      departureTime: departureTime ?? this.departureTime,
      remindBeforeMinutes: remindBeforeMinutes ?? this.remindBeforeMinutes,
      notified: notified ?? this.notified,
      startNotified: startNotified ?? this.startNotified,
      vehicleType: vehicleType ?? this.vehicleType,
      status: status ?? this.status,
      stops: stops ?? this.stops,
      distanceKm: distanceKm ?? this.distanceKm,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'destination': destination,
        'startPoint': startPoint,
        'departureTime': departureTime.toIso8601String(),
        'remindBeforeMinutes': remindBeforeMinutes,
        'notified': notified,
        'startNotified': startNotified,
        'vehicleType': vehicleType,
        'status': status,
        'stops': stops,
        'distanceKm': distanceKm,
      };

  factory TripDepartureReminder.fromJson(Map<String, dynamic> json) =>
      TripDepartureReminder(
        id: json['id'] as String,
        destination: json['destination'] as String,
        startPoint: json['startPoint'] as String? ?? 'Home',
        departureTime: DateTime.parse(json['departureTime'] as String),
        remindBeforeMinutes: json['remindBeforeMinutes'] as int? ?? 30,
        notified: json['notified'] as bool? ?? false,
        startNotified: json['startNotified'] as bool? ?? false,
        vehicleType: json['vehicleType'] as String? ?? 'car',
        status: json['status'] as String? ?? 'CONFIRMED',
        stops: (json['stops'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0.0,
      );
}

/// Service to manage trip start confirmations, alerts, and notifications.
class TripReminderService {
  TripReminderService._();
  static final TripReminderService instance = TripReminderService._();

  static const MethodChannel _channel =
      MethodChannel('com.travelapp.notification');
  static const String _prefsKey = 'voyplan_departure_reminders_v1';

  final _reminderController =
      StreamController<TripDepartureReminder>.broadcast();
  Stream<TripDepartureReminder> get onReminderDue => _reminderController.stream;

  final _tripReadyController =
      StreamController<TripDepartureReminder>.broadcast();
  Stream<TripDepartureReminder> get onTripReadyToStart =>
      _tripReadyController.stream;

  Timer? _pollingTimer;
  bool _initialized = false;

  /// Initialize the service, listen for native notification taps, and check due alerts.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Listen for platform notification taps (Android / iOS)
    if (!kIsWeb) {
      try {
        _channel.setMethodCallHandler((call) async {
          if (call.method == 'onNotificationTapped') {
            final args =
                (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
            final tripId = args['tripId']?.toString() ?? '';
            if (tripId.isNotEmpty) {
              await handleNotificationTapped(tripId);
            }
          }
        });
        await _channel.invokeMethod('requestPermissions');
      } catch (_) {}
    }

    // Check on startup
    await checkDueReminders();

    // Check every 10 seconds while app is active
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      checkDueReminders();
    });
  }

  /// Schedule a confirmed trip's start time and departure reminders.
  Future<TripDepartureReminder> scheduleTripStart({
    required String tripId,
    required String destination,
    String startPoint = 'Home',
    required DateTime departureTime,
    List<String> stops = const [],
    double distanceKm = 0.0,
    String vehicleType = 'car',
    int remindBeforeMinutes = 30,
  }) async {
    // Cancel any old reminders/alarms for this trip
    await cancelTripStart(tripId);

    final now = DateTime.now();
    final bool isAlreadyDue = now.isAfter(departureTime) || now.isAtSameMomentAs(departureTime);

    final reminder = TripDepartureReminder(
      id: tripId,
      destination: destination,
      startPoint: startPoint,
      departureTime: departureTime,
      remindBeforeMinutes: remindBeforeMinutes,
      vehicleType: vehicleType,
      status: isAlreadyDue ? 'READY_TO_START' : 'CONFIRMED',
      stops: stops,
      distanceKm: distanceKm,
    );

    await _saveReminder(reminder);

    final secondsUntilStart = departureTime.difference(now).inSeconds;
    final preTrigger = reminder.reminderTriggerTime;
    final secondsUntilPre = preTrigger.difference(now).inSeconds;

    if (!kIsWeb) {
      // 1. Schedule 30-minute pre-trip reminder if departure is sufficiently ahead
      if (secondsUntilPre > 0) {
        try {
          await _channel.invokeMethod('scheduleReminder', {
            'id': 'reminder_$tripId',
            'tripId': tripId,
            'destination': destination,
            'actionType': 'reminder',
            'title': '🚗 Trip to $destination in $remindBeforeMinutes mins!',
            'body':
                'Departure set for ${TripDateTime.formatTimeDisplay(departureTime)}. Check vehicle & fuel!',
            'secondsFromNow': secondsUntilPre.toDouble(),
            'departureTime': departureTime.toIso8601String(),
          });
        } catch (_) {}
      }

      // 2. Schedule exact Start Notification / Alarm
      try {
        await _channel.invokeMethod('scheduleReminder', {
          'id': 'start_$tripId',
          'tripId': tripId,
          'destination': destination,
          'actionType': 'trip_start',
          'title': '🚗 Your trip to $destination is ready to start!',
          'body': 'Scheduled start time has arrived. Tap to start navigation.',
          'secondsFromNow': secondsUntilStart > 0 ? secondsUntilStart.toDouble() : 1.0,
          'departureTime': departureTime.toIso8601String(),
        });
      } catch (_) {}
    }

    // If trip start is due now, emit immediately for in-app popup
    if (isAlreadyDue) {
      _tripReadyController.add(reminder);
    } else if (secondsUntilPre <= 0 && !reminder.isPastDeparture) {
      _reminderController.add(reminder);
    }

    return reminder;
  }

  /// Postpone trip start time by a given duration (+15m, +30m, +1h, +2h, etc.).
  Future<TripDepartureReminder?> postponeTrip(
    String tripId,
    Duration duration,
  ) async {
    final list = await getReminders();
    final idx = list.indexWhere((r) => r.id == tripId);
    if (idx < 0) return null;
    final existing = list[idx];

    final now = DateTime.now();
    final base = now.isAfter(existing.departureTime) ? now : existing.departureTime;
    final newDepartureTime = base.add(duration);

    return await scheduleTripStart(
      tripId: existing.id,
      destination: existing.destination,
      startPoint: existing.startPoint,
      departureTime: newDepartureTime,
      stops: existing.stops,
      distanceKm: existing.distanceKm,
      vehicleType: existing.vehicleType,
      remindBeforeMinutes: existing.remindBeforeMinutes,
    );
  }

  /// Reschedule trip start time to a specific target DateTime.
  Future<TripDepartureReminder?> rescheduleTrip(
    String tripId,
    DateTime newDepartureTime,
  ) async {
    final list = await getReminders();
    final idx = list.indexWhere((r) => r.id == tripId);
    if (idx < 0) return null;
    final existing = list[idx];

    return await scheduleTripStart(
      tripId: existing.id,
      destination: existing.destination,
      startPoint: existing.startPoint,
      departureTime: newDepartureTime,
      stops: existing.stops,
      distanceKm: existing.distanceKm,
      vehicleType: existing.vehicleType,
      remindBeforeMinutes: existing.remindBeforeMinutes,
    );
  }

  /// Transition trip to IN_PROGRESS when user begins navigation.
  Future<void> startTrip(String tripId) async {
    final list = await getReminders();
    final idx = list.indexWhere((r) => r.id == tripId);
    if (idx >= 0) {
      list[idx] = list[idx].copyWith(status: 'IN_PROGRESS');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, jsonEncode(list.map((r) => r.toJson()).toList()));
    }
    // Cancel pending alarms for this trip
    await cancelAlarms(tripId);
  }

  /// Mark trip as completed.
  Future<void> completeTrip(String tripId) async {
    final list = await getReminders();
    final idx = list.indexWhere((r) => r.id == tripId);
    if (idx >= 0) {
      list[idx] = list[idx].copyWith(status: 'COMPLETED');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, jsonEncode(list.map((r) => r.toJson()).toList()));
    }
    await cancelAlarms(tripId);
  }

  /// Cancel trip start and remove its reminders/alarms.
  Future<void> cancelTripStart(String tripId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getReminders();
    list.removeWhere((r) => r.id == tripId);

    final jsonStr = jsonEncode(list.map((r) => r.toJson()).toList());
    await prefs.setString(_prefsKey, jsonStr);

    await cancelAlarms(tripId);
  }

  /// Helper to cancel native platform notification requests/alarms.
  Future<void> cancelAlarms(String tripId) async {
    if (!kIsWeb) {
      try {
        await _channel.invokeMethod('cancelReminder', {'id': 'reminder_$tripId'});
        await _channel.invokeMethod('cancelReminder', {'id': 'start_$tripId'});
      } catch (_) {}
    }
  }

  /// Backwards-compatible departure reminder method.
  Future<TripDepartureReminder> scheduleDepartureReminder({
    required String tripId,
    required String destination,
    String startPoint = 'Home',
    required DateTime departureTime,
    int remindBeforeMinutes = 30,
    String vehicleType = 'car',
  }) {
    return scheduleTripStart(
      tripId: tripId,
      destination: destination,
      startPoint: startPoint,
      departureTime: departureTime,
      vehicleType: vehicleType,
      remindBeforeMinutes: remindBeforeMinutes,
    );
  }

  /// Backwards-compatible cancel method.
  Future<void> cancelDepartureReminder(String tripId) {
    return cancelTripStart(tripId);
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
    final upcoming = list.where((r) =>
        r.status == 'CONFIRMED' && r.departureTime.isAfter(now)).toList();
    if (upcoming.isEmpty) return null;
    upcoming.sort((a, b) => a.departureTime.compareTo(b.departureTime));
    return upcoming.first;
  }

  /// Get any trip currently ready to start (including missed trips awaiting decision).
  Future<TripDepartureReminder?> getActiveReadyToStartTrip() async {
    final list = await getReminders();
    final ready = list.where((r) => r.status == 'READY_TO_START').toList();
    if (ready.isEmpty) return null;
    ready.sort((a, b) => b.departureTime.compareTo(a.departureTime));
    return ready.first;
  }

  /// Periodic due check: transitions CONFIRMED -> READY_TO_START when scheduled time arrives.
  Future<void> checkDueReminders() async {
    final list = await getReminders();
    bool updated = false;
    final now = DateTime.now();

    for (int i = 0; i < list.length; i++) {
      final r = list[i];

      // 1. Check for exact trip start: CONFIRMED -> READY_TO_START
      if (r.status == 'CONFIRMED' && (now.isAfter(r.departureTime) || now.isAtSameMomentAs(r.departureTime))) {
        final readyReminder = r.copyWith(
          status: 'READY_TO_START',
          startNotified: true,
        );
        list[i] = readyReminder;
        updated = true;
        _tripReadyController.add(readyReminder);
      }
      // 2. Keep missed trips as READY_TO_START until user makes a decision
      else if (r.status == 'READY_TO_START') {
        // Do not cancel automatically
      }
      // 3. Pre-trip 30m reminder alert
      else if (r.status == 'CONFIRMED' && !r.notified && r.isDue && !r.isPastDeparture) {
        _reminderController.add(r);
        list[i] = r.copyWith(notified: true);
        updated = true;
      }
    }

    if (updated) {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(list.map((r) => r.toJson()).toList());
      await prefs.setString(_prefsKey, jsonStr);
    }
  }

  /// Called when a notification is tapped natively.
  Future<void> handleNotificationTapped(String tripId) async {
    final list = await getReminders();
    // Match either exact tripId or strip 'start_' / 'reminder_' prefix
    final cleanId = tripId.replaceFirst('start_', '').replaceFirst('reminder_', '');
    final idx = list.indexWhere((r) => r.id == tripId || r.id == cleanId);
    if (idx >= 0) {
      final r = list[idx];
      final ready = r.copyWith(status: 'READY_TO_START');
      list[idx] = ready;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, jsonEncode(list.map((e) => e.toJson()).toList()));
      _tripReadyController.add(ready);
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
}
