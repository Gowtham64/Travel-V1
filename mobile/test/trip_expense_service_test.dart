import 'package:flutter_test/flutter_test.dart';
import 'package:travel_app/models/trip_expense_models.dart';
import 'package:travel_app/models/trip_models.dart';
import 'package:travel_app/services/trip_expense_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TripExpenseService & TripExpenseReport Tests', () {
    test('Initializes trip with separated fuel, tolls, and break expenses', () async {
      final plan = TripPlan.fromJson({
        'route': {
          'distanceKm': 145.0,
          'durationMin': 180,
          'coordinates': [
            {'lat': 12.9716, 'lng': 77.5946},
            {'lat': 12.2958, 'lng': 76.6394},
          ],
        },
        'places': {},
        'estimatedDays': 1,
        'fuel': {
          'fuelType': 'petrol',
          'refuelStops': [],
        },
        'budget': {
          'currency': 'INR',
          'days': 1,
          'nights': 0,
          'travellers': 1,
          'fuel': 1200,
          'tolls': 330,
          'stay': 0,
          'buffer': 200,
          'total': 2530,
          'perDay': 2530,
          'breakdown': {
            'breakfast': 200,
            'lunch': 400,
            'teaSnacks': 100,
            'dinner': 100,
            'food': 800,
            'other': 200,
          },
        },
        'fuelEstimate': {
          'distanceKm': 145.0,
          'vehicleEfficiency': 15.0,
          'fuelType': 'Petrol',
          'fuelRequired': 9.67,
          'pricePerUnit': 102.86,
          'totalCost': 994.66,
          'applicableLocation': 'Bangalore, Karnataka',
          'effectiveAt': '2026-09-04',
          'lastUpdated': '2026-09-04',
        },
        'toll': {
          'hasTolls': true,
          'minTollCost': 330.0,
          'fastagTollCost': 330.0,
          'tolls': [
            {
              'id': 'toll_1',
              'name': 'Sheshagirihalli Toll Plaza',
              'highway': 'NH 275',
              'latitude': 12.82,
              'longitude': 77.41,
              'amount': 165.0,
              'cashAmount': 330.0,
              'vehicleClass': 'car',
              'distanceAlongRouteKm': 32.0,
            },
            {
              'id': 'toll_2',
              'name': 'Gananguru Toll Plaza',
              'highway': 'NH 275',
              'latitude': 12.44,
              'longitude': 76.75,
              'amount': 165.0,
              'cashAmount': 330.0,
              'vehicleClass': 'car',
              'distanceAlongRouteKm': 110.0,
            },
          ],
        },
      });

      final vehicle = Vehicle(
        type: 'Car',
        efficiencyKmPerLiter: 15.0,
        tankCapacityLiters: 45.0,
        currentFuelLiters: 20.0,
      );

      await TripExpenseService.instance.initTrip(
        tripId: 'test_trip_1',
        plan: plan,
        vehicle: vehicle,
        startAddress: 'Bangalore',
        endAddress: 'Mysore',
        isRoundTrip: false,
        confirmedWaypoints: [
          const GeoPoint(lat: 12.6, lng: 77.0, name: 'Channapatna Toys'),
        ],
      );

      expect(TripExpenseService.instance.hasActiveTrip, isTrue);

      // Verify seeding
      final summaries = TripExpenseService.instance.getCategorySummaries();
      expect(summaries['fuel']!.estimated, greaterThan(900));
      expect(summaries['tolls']!.estimated, equals(330.0));
      expect(summaries['food']!.estimated, equals(800.0));

      // Record an actual refuel
      await TripExpenseService.instance.recordRefuel(
        stationName: 'Indian Oil Highway',
        location: 'NH 275, Ramanagara',
        fuelType: 'Petrol',
        litres: 10.0,
        pricePerLitre: 102.86,
      );

      // Record an actual toll
      await TripExpenseService.instance.recordTollPayment(
        tollPlazaId: 'toll_1',
        tollPlazaName: 'Sheshagirihalli Toll Plaza',
        actualAmount: 165.0,
        paymentMethod: 'FASTag',
      );

      // Record a break expense
      await TripExpenseService.instance.recordMealBreak(
        category: ExpenseCategory.breakfast,
        placeName: 'Kadu Mane Idli',
        actualAmount: 180.0,
      );

      // Generate Final 17-Question Report
      final report = TripExpenseService.instance.generateFinalReport(routedThroughAllStops: true);

      expect(report.tripId, equals('test_trip_1'));
      expect(report.distanceKm, equals(145.0));
      expect(report.routedThroughAllStops, isTrue);
      expect(report.confirmedStops, contains('Channapatna Toys'));
      expect(report.actualFuelCost, closeTo(1028.6, 1.0));
      expect(report.actualTollTotal, equals(165.0));
      expect(report.actualBreakfast, equals(180.0));
      expect(report.fuelPricePerLiter, closeTo(102.86, 0.1));
      expect(report.totalActual, greaterThan(0));
    });
  });
}
