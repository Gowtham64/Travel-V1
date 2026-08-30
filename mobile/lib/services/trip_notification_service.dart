import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'live_activity_service.dart';

/// Shows a live "trip in progress" notification while driving — an ongoing
/// progress notification on Android (lock screen + shade, like a food-delivery
/// tracker) and a best-effort local notification on iOS. On iOS it also drives
/// a native Live Activity (Dynamic Island + lock screen) when available.
///
/// A single sticky notification (fixed id) is updated in place as the drive
/// progresses, so it never stacks up.
class TripNotificationService {
  TripNotificationService._();
  static final TripNotificationService instance = TripNotificationService._();

  static const int _notifId = 4201;
  static const String _channelId = 'trip_progress';
  static const String _channelName = 'Trip progress';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _inited = false;
  bool _active = false;

  Future<void> _ensureInit() async {
    if (_inited || kIsWeb) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: darwin),
    );

    // Android 13+ needs runtime notification permission.
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();

    // iOS permission (also covered by the Darwin init above).
    final iosImpl = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await iosImpl?.requestPermissions(alert: true, badge: false, sound: false);

    _inited = true;
  }

  /// Begin the trip-progress notification. [destination] names the trip.
  Future<void> start({required String destination}) async {
    if (kIsWeb) return;
    await _ensureInit();
    _active = true;
    await update(
      destination: destination,
      etaText: 'Starting…',
      distanceLeftKm: 0,
      progressPercent: 0,
      speedKmh: 0,
    );
    // Kick off the iOS Live Activity (no-op on Android / older iOS).
    await LiveActivityService.instance.start(destination: destination);
  }

  /// Update the live notification with the latest ETA / distance / progress.
  Future<void> update({
    required String destination,
    required String etaText,
    required double distanceLeftKm,
    required double progressPercent, // 0..1
    required double speedKmh,
    bool arriving = false,
  }) async {
    if (kIsWeb || !_active) return;
    await _ensureInit();

    final pct = (progressPercent.clamp(0.0, 1.0) * 100).round();
    final title = arriving ? 'Arriving now' : 'Arriving in $etaText';
    final body = arriving
        ? 'You have reached $destination'
        : '${distanceLeftKm.toStringAsFixed(1)} km left · $pct% · ${speedKmh.round()} km/h';

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Live progress of your active trip',
      importance: Importance.low, // quiet: no sound/heads-up on every update
      priority: Priority.low,
      ongoing: !arriving, // sticky while driving; dismissible on arrival
      autoCancel: arriving,
      onlyAlertOnce: true,
      showProgress: !arriving,
      maxProgress: 100,
      progress: pct,
      category: AndroidNotificationCategory.navigation,
      subText: destination,
      visibility: NotificationVisibility.public, // show on lock screen
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: false,
      interruptionLevel: InterruptionLevel.passive,
    );

    await _plugin.show(
      _notifId,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );

    await LiveActivityService.instance.update(
      etaText: arriving ? 'Arrived' : etaText,
      distanceLeftKm: distanceLeftKm,
      progressPercent: progressPercent.clamp(0.0, 1.0),
      arriving: arriving,
    );
  }

  /// Clear the notification when navigation ends.
  Future<void> end() async {
    if (kIsWeb) return;
    _active = false;
    await _plugin.cancel(_notifId);
    await LiveActivityService.instance.end();
  }
}
