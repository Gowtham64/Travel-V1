import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:travel_app/models/trip_models.dart';

void main() {
  group('Fuel Navigation & Stop Verification Tests', () {
    test('RefuelStop converts to GeoPoint marked as isFuelStop with exact coordinates', () {
      const stop = RefuelStop(
        lat: 12.9716,
        lng: 77.5946,
        name: 'Indian Oil Petrol Pump',
        distanceFromStartKm: 145.2,
        offRouteKm: 0.12,
        refillLiters: 28.5,
        estimatedCost: 2900.0,
        pricePerUnit: 101.5,
        currencySymbol: '₹',
        fuelType: 'petrol',
      );

      final geoPoint = stop.toGeoPoint();
      expect(geoPoint.lat, equals(12.9716));
      expect(geoPoint.lng, equals(77.5946));
      expect(geoPoint.name, equals('Indian Oil Petrol Pump'));
      expect(geoPoint.isFuelStop, isTrue);
      expect(geoPoint.refuelStop, isNotNull);
      expect(geoPoint.refuelStop?.refillLiters, equals(28.5));
      expect(stop.distanceFromRoute, equals(0.12));
    });

    test('TripPlan.fromJson parses navigationWaypoints and refuelStops correctly', () {
      final json = {
        'route': {
          'coordinates': [
            {'lat': 12.9716, 'lng': 77.5946},
            {'lat': 12.5000, 'lng': 77.0000},
            {'lat': 12.2958, 'lng': 76.6394},
          ],
          'distanceKm': 150.0,
          'durationMin': 180,
        },
        'estimatedDays': 1,
        'fuel': {
          'totalCost': 1500.0,
          'fuelNeeded': 25.0,
          'refuelStops': [
            {
              'id': 'fuel_stop_1',
              'name': 'Shell Fuel Station',
              'latitude': 12.5000,
              'longitude': 77.0000,
              'fuelType': 'petrol',
              'distanceFromRoute': 0.05,
              'distanceFromStartKm': 75.0,
              'refillLiters': 20.0,
              'estimatedCost': 2040.0,
              'pricePerUnit': 102.0,
              'currency': 'INR',
              'currencySymbol': '₹',
              'isSystemGenerated': true,
              'legIndex': 0,
            }
          ]
        },
        'navigationWaypoints': [
          {
            'lat': 12.5000,
            'lng': 77.0000,
            'name': 'Shell Fuel Station',
            'isFuelStop': true,
          }
        ]
      };

      final plan = TripPlan.fromJson(json);
      expect(plan.fuel.refuelStops.length, equals(1));
      final fs = plan.fuel.refuelStops.first;
      expect(fs.id, equals('fuel_stop_1'));
      expect(fs.name, equals('Shell Fuel Station'));
      expect(fs.lat, equals(12.5000));
      expect(fs.lng, equals(77.0000));
      expect(fs.refillLiters, equals(20.0));

      expect(plan.navigationWaypoints.length, equals(1));
      expect(plan.navigationWaypoints.first.isFuelStop, isTrue);
      expect(plan.navigationWaypoints.first.name, equals('Shell Fuel Station'));
    });

    test('Distance calculation correctly identifies arrival at fuel pump within 75 meters', () {
      const distCalc = Distance();
      const stationCoord = LatLng(12.50000, 77.00000);
      // Vehicle ~33 meters away
      const vehicleNearby = LatLng(12.50030, 77.00000);
      final distMeters = distCalc.as(LengthUnit.Meter, vehicleNearby, stationCoord);

      expect(distMeters, lessThanOrEqualTo(75.0));

      // Tank top-up logic simulation
      const car = Vehicle(
        type: 'car',
        efficiencyKmPerLiter: 15.0,
        tankCapacityLiters: 45.0,
        currentFuelLiters: 12.0,
      );

      final refueledCar = car.copyWith(currentFuelLiters: car.tankCapacityLiters);
      expect(refueledCar.currentFuelLiters, equals(45.0));
    });
  });
}
