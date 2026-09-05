import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travel_app/utils/trip_date_time.dart';
import 'package:travel_app/services/trip_reminder_service.dart';
import 'package:travel_app/services/trip_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bug 1: Canonical DateTime & 12h <-> 24h Time Conversions', () {
    test('12:00 AM and 12:00 PM convert with strict mathematical correctness', () {
      expect(TripDateTime.to24Hour('12:00 AM'), '00:00');
      expect(TripDateTime.to24Hour('12:00 PM'), '12:00');
      expect(TripDateTime.to12Hour('00:00'), '12:00 AM');
      expect(TripDateTime.to12Hour('12:00'), '12:00 PM');
    });

    test('2:00 PM is NEVER converted to 2:00 AM', () {
      // 2:00 PM -> 14:00 (840 minutes)
      expect(TripDateTime.parseMinutes('2:00 PM'), 14 * 60);
      expect(TripDateTime.to24Hour('2:00 PM'), '14:00');
      expect(TripDateTime.to12Hour('14:00'), '2:00 PM');

      // 2:00 AM -> 02:00 (120 minutes)
      expect(TripDateTime.parseMinutes('2:00 AM'), 2 * 60);
      expect(TripDateTime.to24Hour('2:00 AM'), '02:00');
      expect(TripDateTime.to12Hour('02:00'), '2:00 AM');
      expect(TripDateTime.to12Hour('02:00 AM'), '2:00 AM');
      expect(TripDateTime.to12Hour('2:00 AM'), '2:00 AM');

      // CRITICAL: 02:00 PM or 2:00 PM input to to12Hour must NEVER produce 2:00 AM
      expect(TripDateTime.to12Hour('02:00 PM'), '2:00 PM');
      expect(TripDateTime.to12Hour('2:00 PM'), '2:00 PM');
      expect(TripDateTime.to12Hour('02:00 PM'), isNot('2:00 AM'));
      expect(TripDateTime.to12Hour('2:00 PM'), isNot('2:00 AM'));

      // Overloaded to24Hour(hour, minute)
      expect(TripDateTime.to24Hour(14, 0), '14:00');
      expect(TripDateTime.to24Hour(2, 0), '02:00');
      expect(TripDateTime.to12Hour(14, 0), '2:00 PM');
      expect(TripDateTime.to12Hour(2, 0), '2:00 AM');
    });

    test('All 24 hours round-trip through 12h and 24h correctly', () {
      for (int h = 0; h < 24; h++) {
        for (int m = 0; m < 60; m += 30) {
          final time24 = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
          final time12 = TripDateTime.to12Hour(time24);
          final back24 = TripDateTime.to24Hour(time12);
          expect(back24, time24, reason: 'Mismatch for hour $h:$m');
        }
      }
    });

    test('Day 1 itinerary re-anchoring accurately starts Day 1 at user start time', () {
      final mockDays = [
        {
          'day': 1,
          'title': 'Departure & Sightseeing',
          'activities': [
            {'part': 'morning', 'time': '08:00 AM', 'title': 'Breakfast', 'note': 'Quick bite'},
            {'part': 'morning', 'time': '10:00 AM', 'title': 'Start Driving', 'note': 'On the highway'},
          ]
        },
        {
          'day': 2,
          'title': 'Exploration',
          'activities': [
            {'part': 'morning', 'time': '09:00 AM', 'title': 'Temple Visit', 'note': 'Darshan'},
          ]
        }
      ];

      // User chooses 2:00 PM (14:00 = 840 minutes)
      final reanchored = TripDateTime.validateAndReanchorDays(mockDays, startMinutes: 14 * 60);
      expect(reanchored.length, 2);

      final day1Acts = reanchored[0]['activities'] as List;
      // First activity of Day 1 must match 2:00 PM
      expect(day1Acts[0]['time'], '2:00 PM');
      // Second activity spaced out
      expect(day1Acts[1]['time'], '3:30 PM');

      // Day 2 untouched
      final day2Acts = reanchored[1]['activities'] as List;
      expect(day2Acts[0]['time'], '09:00 AM');
    });
  });

  group('Bug 2: Trip Start Confirmation & Lifecycle State Machine', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Trip transition from CONFIRMED -> READY_TO_START when departure arrives', () async {
      final service = TripReminderService.instance;
      final pastDeparture = DateTime.now().subtract(const Duration(minutes: 5));

      // Schedule a trip whose time has already arrived
      final reminder = await service.scheduleTripStart(
        tripId: 'test_trip_1',
        destination: 'Mysuru',
        startPoint: 'Bengaluru',
        departureTime: pastDeparture,
        stops: ['Mandya'],
        distanceKm: 145.0,
      );

      expect(reminder.status, 'READY_TO_START');

      final active = await service.getActiveReadyToStartTrip();
      expect(active, isNotNull);
      expect(active!.id, 'test_trip_1');
      expect(active.status, 'READY_TO_START');
    });

    test('Postponing a trip updates departure time and resets status to CONFIRMED', () async {
      final service = TripReminderService.instance;
      final futureDeparture = DateTime.now().add(const Duration(minutes: 2));

      await service.scheduleTripStart(
        tripId: 'test_trip_postpone',
        destination: 'Ooty',
        departureTime: futureDeparture,
      );

      // Postpone by 30 mins
      final postponed = await service.postponeTrip('test_trip_postpone', const Duration(minutes: 30));
      expect(postponed, isNotNull);
      expect(postponed!.status, 'CONFIRMED');
      expect(postponed.departureTime.isAfter(futureDeparture), isTrue);
    });

    test('Starting navigation transitions trip to IN_PROGRESS', () async {
      final service = TripReminderService.instance;
      final departure = DateTime.now();

      await service.scheduleTripStart(
        tripId: 'test_trip_nav',
        destination: 'Coorg',
        departureTime: departure,
      );

      await service.startTrip('test_trip_nav');

      final reminders = await service.getReminders();
      final updated = reminders.firstWhere((r) => r.id == 'test_trip_nav');
      expect(updated.status, 'IN_PROGRESS');
    });
  });

  group('Bug 3: Deletion Tombstones and Push-Sync Protection', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Deleted trip ID and title are recorded in tombstone set and never resurrected', () async {
      final history = TripHistoryService.instance;

      final trip = TripHistoryItem(
        id: 'trip_to_delete_123',
        title: 'Bengaluru to Tirupati',
        startAddress: 'Bengaluru',
        endAddress: 'Tirupati',
        distanceKm: 250.0,
        durationMinutes: 300,
        vehicleType: 'car',
        fuelCost: 1500.0,
        tollCost: 350.0,
        totalCost: 1850.0,
        completedAt: DateTime.now(),
        isRoundTrip: false,
      );

      await history.saveTrip(trip);
      var items = await history.getHistory();
      expect(items.any((i) => i.id == 'trip_to_delete_123'), isTrue);

      // Delete the trip
      await history.deleteTrip('trip_to_delete_123', title: 'Bengaluru to Tirupati');

      final deletedIds = await history.getDeletedIds();
      expect(deletedIds.contains('trip_to_delete_123'), isTrue);
      expect(deletedIds.contains('bengaluru to tirupati'), isTrue);

      // Verify it is purged from local history
      items = await history.getHistory();
      expect(items.any((i) => i.id == 'trip_to_delete_123'), isFalse);
      expect(items.any((i) => i.title == 'Bengaluru to Tirupati'), isFalse);
    });
  });
}
