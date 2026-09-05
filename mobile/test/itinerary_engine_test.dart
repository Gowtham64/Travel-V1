import 'package:flutter_test/flutter_test.dart';
import 'package:travel_app/models/trip_models.dart';
import 'package:travel_app/utils/trip_date_time.dart';

void main() {
  group('TimelineBlock Model & Coordinate Grounding', () {
    test('TimelineBlock deserializes and serializes with complete verified GPS metadata', () {
      final json = {
        'id': 'blk_123',
        'start': '14:00',
        'end': '15:30',
        'type': 'activity',
        'title': 'Mysore Palace',
        'place': 'Sayyaji Rao Rd, Agrahara, Chamrajpura, Mysuru',
        'lat': 12.3051,
        'lng': 76.6551,
        'address': 'Sayyaji Rao Rd, Mysuru',
        'city': 'Mysuru',
        'state': 'Karnataka',
        'country': 'India',
        'durationMin': 90,
        'travelMin': 0,
        'distanceKm': 0.0,
        'breakType': '',
        'reason': 'Historical royal palace',
        'travelMode': 'drive',
        'categories': ['Historical & Heritage', 'Famous Places'],
        'whyIncluded': 'Top historical monument in Mysuru',
        'openingHours': '10:00 AM - 05:30 PM',
        'day': 1,
        'sequence': 2,
        'isFuelStop': false,
        'isConfirmed': true,
      };

      final block = TimelineBlock.fromJson(json);
      expect(block.id, 'blk_123');
      expect(block.lat, 12.3051);
      expect(block.lng, 76.6551);
      expect(block.city, 'Mysuru');
      expect(block.durationMin, 90);
      expect(block.isConfirmed, true);
      expect(block.openingHours, '10:00 AM - 05:30 PM');

      final serialized = block.toJson();
      expect(serialized['lat'], 12.3051);
      expect(serialized['lng'], 76.6551);
      expect(serialized['city'], 'Mysuru');
      expect(serialized['isConfirmed'], true);
    });

    test('TimelineBlock supports fuel stop metadata', () {
      final fuelBlock = TimelineBlock(
        start: '12:00',
        end: '12:15',
        type: 'fuel',
        title: 'Shell Fuel Station - Mandya Highway',
        lat: 12.5200,
        lng: 76.9000,
        durationMin: 15,
        isFuelStop: true,
      );

      expect(fuelBlock.type, 'fuel');
      expect(fuelBlock.isFuelStop, true);
      expect(fuelBlock.toJson()['isFuelStop'], true);
    });
  });

  group('SmartDay Serialization & Trip Structure', () {
    test('SmartDay serializes to and from JSON preserving block order and coordinates', () {
      final day = SmartDay(
        day: 1,
        title: 'Bengaluru to Mysuru Heritage Circuit',
        date: '05/09/2026',
        blocks: [
          TimelineBlock(
            start: '14:00',
            end: '14:00',
            type: 'start',
            title: 'Depart Bengaluru',
            lat: 12.9716,
            lng: 77.5946,
          ),
          TimelineBlock(
            start: '14:00',
            end: '16:30',
            type: 'travel',
            title: 'Drive to Mysuru',
            travelMin: 150,
            distanceKm: 145.0,
          ),
          TimelineBlock(
            start: '16:30',
            end: '18:00',
            type: 'activity',
            title: 'Mysore Palace',
            lat: 12.3051,
            lng: 76.6551,
            durationMin: 90,
          ),
        ],
      );

      final json = day.toJson();
      expect(json['day'], 1);
      expect((json['blocks'] as List).length, 3);

      final restored = SmartDay.fromJson(json);
      expect(restored.day, 1);
      expect(restored.blocks[0].lat, 12.9716);
      expect(restored.blocks[2].lat, 12.3051);
    });
  });

  group('Continuous Timeline Math & Dynamic Re-anchoring', () {
    test('Modifying duration of a stop maintains unbroken, non-overlapping timeline', () {
      final blocks = [
        TimelineBlock(
          start: '14:00',
          end: '16:00',
          type: 'travel',
          title: 'Drive',
          travelMin: 120,
        ),
        TimelineBlock(
          start: '16:00',
          end: '17:30',
          type: 'activity',
          title: 'Palace Visit',
          durationMin: 90,
        ),
        TimelineBlock(
          start: '17:30',
          end: '18:15',
          type: 'coffee',
          title: 'High Tea',
          durationMin: 45,
        ),
      ];

      // User increases Palace Visit duration by +30 min (90 -> 120 min)
      blocks[1].durationMin += 30;

      // Re-anchor timeline from Day 1 start (14:00 = 840 min)
      int curMin = 14 * 60;
      for (final b in blocks) {
        final dur = (b.type == 'travel' || b.type == 'return')
            ? (b.travelMin > 0 ? b.travelMin : 30)
            : (b.durationMin > 0 ? b.durationMin : 45);
        b.start = TripDateTime.formatMinutes(curMin);
        b.end = TripDateTime.formatMinutes(curMin + dur);
        curMin += dur;
      }

      expect(blocks[0].start, '2:00 PM');
      expect(blocks[0].end, '4:00 PM');
      expect(blocks[1].start, '4:00 PM');
      expect(blocks[1].end, '6:00 PM'); // extended by 30 min
      expect(blocks[2].start, '6:00 PM'); // pushed forward smoothly
      expect(blocks[2].end, '6:45 PM');
    });

    test('Removing a stop eliminates gaps without overlapping timings', () {
      final blocks = [
        TimelineBlock(
          start: '08:30',
          end: '09:30',
          type: 'activity',
          title: 'Stop A',
          durationMin: 60,
        ),
        TimelineBlock(
          start: '09:30',
          end: '10:30',
          type: 'activity',
          title: 'Stop B',
          durationMin: 60,
        ),
        TimelineBlock(
          start: '10:30',
          end: '11:30',
          type: 'activity',
          title: 'Stop C',
          durationMin: 60,
        ),
      ];

      // Remove Stop B
      blocks.removeAt(1);
      expect(blocks.length, 2);

      // Re-anchor from 08:30
      int curMin = 8 * 60 + 30;
      for (final b in blocks) {
        final dur = b.durationMin > 0 ? b.durationMin : 45;
        b.start = TripDateTime.formatMinutes(curMin);
        b.end = TripDateTime.formatMinutes(curMin + dur);
        curMin += dur;
      }

      expect(blocks[0].title, 'Stop A');
      expect(blocks[0].start, '8:30 AM');
      expect(blocks[0].end, '9:30 AM');

      expect(blocks[1].title, 'Stop C');
      expect(blocks[1].start, '9:30 AM');
      expect(blocks[1].end, '10:30 AM');
    });
  });

  group('Trip Type Coordinate Extraction for Navigation', () {
    test('Around trip roots start and end at the same origin coordinate', () {
      final blocks = [
        TimelineBlock(
          start: '14:00',
          end: '14:00',
          type: 'start',
          title: 'Bengaluru',
          lat: 12.9716,
          lng: 77.5946,
        ),
        TimelineBlock(
          start: '16:30',
          end: '18:00',
          type: 'activity',
          title: 'Mysore Palace',
          lat: 12.3051,
          lng: 76.6551,
        ),
        TimelineBlock(
          start: '18:30',
          end: '19:30',
          type: 'activity',
          title: 'Chamundi Hills',
          lat: 12.2753,
          lng: 76.6701,
        ),
        TimelineBlock(
          start: '22:00',
          end: '22:00',
          type: 'return',
          title: 'Bengaluru',
          lat: 12.9716,
          lng: 77.5946,
        ),
      ];

      const tripType = 'around';
      GeoPoint? startCoord;
      GeoPoint? endCoord;
      final waypoints = <GeoPoint>[];

      for (final b in blocks) {
        if (b.lat != null && b.lng != null && (b.lat != 0.0 || b.lng != 0.0)) {
          final pt = GeoPoint(lat: b.lat!, lng: b.lng!, name: b.title);
          if (startCoord == null) {
            startCoord = pt;
          } else {
            waypoints.add(pt);
          }
        }
      }

      if (tripType == 'around' && startCoord != null) {
        endCoord = startCoord;
      }

      expect(startCoord!.lat, 12.9716);
      expect(startCoord.lng, 77.5946);
      expect(endCoord!.lat, 12.9716);
      expect(endCoord.lng, 77.5946);
      expect(waypoints.any((w) => w.name == 'Mysore Palace'), true);
    });

    test('One-way trip terminates at the destination coordinate', () {
      final blocks = [
        TimelineBlock(
          start: '08:00',
          end: '08:00',
          type: 'start',
          title: 'Bengaluru',
          lat: 12.9716,
          lng: 77.5946,
        ),
        TimelineBlock(
          start: '11:00',
          end: '12:30',
          type: 'activity',
          title: 'Shravanabelagola',
          lat: 12.8576,
          lng: 76.4862,
        ),
        TimelineBlock(
          start: '15:00',
          end: '15:00',
          type: 'activity',
          title: 'Chikmagalur',
          lat: 13.3161,
          lng: 75.7720,
        ),
      ];

      const tripType = 'oneway';
      GeoPoint? startCoord;
      GeoPoint? endCoord;
      final waypoints = <GeoPoint>[];

      for (final b in blocks) {
        if (b.lat != null && b.lng != null && (b.lat != 0.0 || b.lng != 0.0)) {
          final pt = GeoPoint(lat: b.lat!, lng: b.lng!, name: b.title);
          if (startCoord == null) {
            startCoord = pt;
          } else {
            waypoints.add(pt);
          }
        }
      }

      if (tripType == 'oneway' && waypoints.isNotEmpty) {
        endCoord = waypoints.removeLast();
      }

      expect(startCoord!.name, 'Bengaluru');
      expect(endCoord!.name, 'Chikmagalur');
      expect(endCoord.lat, 13.3161);
      expect(waypoints.length, 1);
      expect(waypoints.first.name, 'Shravanabelagola');
    });

    test('Smart AI Planner around trip extracts origin as start and end, with destination waypoints', () {
      final blocks = [
        TimelineBlock(
          start: '14:00',
          end: '14:00',
          type: 'start',
          title: 'Chennai',
          lat: 13.0827,
          lng: 80.2707,
        ),
        TimelineBlock(
          start: '18:00',
          end: '19:30',
          type: 'activity',
          title: 'Rockfort Temple (Corridor)',
          lat: 10.8282,
          lng: 78.6970,
        ),
        TimelineBlock(
          start: '21:00',
          end: '22:30',
          type: 'activity',
          title: 'Meenakshi Temple (Madurai)',
          lat: 9.9195,
          lng: 78.1193,
        ),
        TimelineBlock(
          start: '23:30',
          end: '23:30',
          type: 'return',
          title: 'Chennai',
          lat: 13.0827,
          lng: 80.2707,
        ),
      ];

      GeoPoint? startCoord;
      GeoPoint? endCoord;
      final waypoints = <GeoPoint>[];

      for (final b in blocks) {
        if (b.lat != null && b.lng != null && (b.lat != 0.0 || b.lng != 0.0)) {
          final pt = GeoPoint(lat: b.lat!, lng: b.lng!, name: b.title);
          if (startCoord == null) {
            startCoord = pt;
          } else {
            waypoints.add(pt);
          }
        }
      }

      if (startCoord != null) {
        endCoord = startCoord;
      }

      expect(startCoord!.name, 'Chennai');
      expect(endCoord!.name, 'Chennai');
      expect(endCoord!.lat, 13.0827);
      expect(waypoints.any((w) => (w.name ?? '').contains('Madurai')), true);
    });
  });
}
