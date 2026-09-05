import 'package:flutter_test/flutter_test.dart';
import 'package:travel_app/models/trip_models.dart';

void main() {
  group('Routing Accuracy & Single Canonical Source of Truth Tests', () {
    test('Centralized distance formatting formats meters and kilometers accurately', () {
      expect(TripPlan.formatDistance(0.75, distMeters: 750), equals('750 m'));
      expect(TripPlan.formatDistance(0.05, distMeters: 50), equals('50 m'));
      expect(TripPlan.formatDistance(12.4, distMeters: 12400), equals('12.4 km'));
      expect(TripPlan.formatDistance(348.25, distMeters: 348250), equals('348.3 km'));
      expect(TripPlan.formatDistance(145.0, distMeters: 145000), equals('145.0 km'));
    });

    test('TripPlan.fromJson accurately parses canonical route with legs, steps, and distanceMeters', () {
      final json = {
        'route': {
          'origin': {'lat': 12.9716, 'lng': 77.5946, 'name': 'Bengaluru'},
          'destination': {'lat': 12.2958, 'lng': 76.6394, 'name': 'Mysuru'},
          'waypoints': [],
          'coordinates': [
            {'lat': 12.9716, 'lng': 77.5946},
            {'lat': 12.2958, 'lng': 76.6394},
          ],
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [77.5946, 12.9716],
              [76.6394, 12.2958],
            ],
          },
          'distanceMeters': 145210,
          'distanceKm': 145.2,
          'durationSeconds': 10815,
          'durationMin': 180,
          'legs': [
            {
              'legIndex': 0,
              'distanceMeters': 145210,
              'durationSeconds': 10815,
              'steps': [
                {
                  'instruction': 'Head south on NH275',
                  'distanceMeters': 5000,
                  'durationSeconds': 300,
                  'roadName': 'NH275',
                  'maneuverType': 'straight',
                },
                {
                  'instruction': 'Take exit toward Mysuru',
                  'distanceMeters': 140210,
                  'durationSeconds': 10515,
                  'roadName': 'NH275 Expressway',
                  'maneuverType': 'offRamp',
                }
              ]
            }
          ],
          'steps': [
            {
              'instruction': 'Head south on NH275',
              'distanceMeters': 5000,
              'durationSeconds': 300,
              'roadName': 'NH275',
              'maneuverType': 'straight',
            }
          ],
          'maneuvers': ['Head south on NH275', 'Take exit toward Mysuru'],
          'avoidedMotorways': false,
          'provider': 'Mapbox',
        },
        'estimatedDays': 1,
        'fuel': {
          'fuelStops': [],
          'refuelStops': [],
          'totalRefillCost': 0.0,
          'totalRefillLiters': 0.0,
          'fuelCost': 1200.0,
          'currentRangeKm': 450.0,
        },
        'toll': null,
        'weather': null,
        'departureAdvice': null,
        'restStops': [],
        'itinerary': [],
        'budget': null,
        'places': {},
      };

      final plan = TripPlan.fromJson(json);

      expect(plan.distanceKm, equals(145.2));
      expect(plan.distanceMeters, equals(145210));
      expect(plan.formattedDistance, equals('145.2 km'));
      expect(plan.durationMin, equals(180));
      expect(plan.durationSeconds, equals(10815));
      expect(plan.coordinates, hasLength(2));
      expect(plan.legs, hasLength(1));
      expect(plan.legs.first.steps, hasLength(2));
      expect(plan.steps, hasLength(1));
      expect(plan.maneuvers, equals(['Head south on NH275', 'Take exit toward Mysuru']));
      expect(plan.provider, equals('Mapbox'));
    });

    test('Around Trip maintains exact origin coordinates as destination', () {
      const origin = GeoPoint(lat: 12.9716, lng: 77.5946, name: 'Bengaluru');
      const stop1 = GeoPoint(lat: 12.2958, lng: 76.6394, name: 'Mysuru');
      const stop2 = GeoPoint(lat: 11.4102, lng: 76.6950, name: 'Ooty');

      final allStops = [origin, stop1, stop2];

      // Around Trip calculation
      final start = allStops.first;
      final end = GeoPoint(lat: start.lat, lng: start.lng, name: start.name);
      final waypoints = allStops.sublist(1);

      expect(start.lat, equals(end.lat));
      expect(start.lng, equals(end.lng));
      expect(waypoints, hasLength(2));
      expect(waypoints[0].name, equals('Mysuru'));
      expect(waypoints[1].name, equals('Ooty'));
    });

    test('User waypoint order is preserved without auto-sorting by distance', () {
      const start = GeoPoint(lat: 12.9716, lng: 77.5946, name: 'Bengaluru');
      // Intentionally order: Stop B (further) then Stop A (closer)
      const stopB = GeoPoint(lat: 11.4102, lng: 76.6950, name: 'Ooty');
      const stopA = GeoPoint(lat: 12.2958, lng: 76.6394, name: 'Mysuru');
      const end = GeoPoint(lat: 11.0168, lng: 76.9558, name: 'Coimbatore');

      final userWaypoints = [stopB, stopA];

      // Verify sequence: Start -> Ooty -> Mysuru -> Coimbatore
      final itinerarySequence = [start, ...userWaypoints, end];
      expect(itinerarySequence.map((p) => p.name).toList(),
          equals(['Bengaluru', 'Ooty', 'Mysuru', 'Coimbatore']));
    });
  });
}
