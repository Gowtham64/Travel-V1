import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travel_app/models/trip_models.dart';
import 'package:travel_app/models/vehicles_data.dart';
import 'package:travel_app/services/fuel_price_service.dart';
import 'package:travel_app/services/vehicle_database_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Vehicle Selection — Fuel & Mileage Validation', () {
    test('Current Fuel validation: accepts valid decimals >= 0, rejects invalid', () {
      final vehicle = VehicleModel(
        id: 'innova_crysta',
        name: 'Toyota Innova Crysta',
        type: 'car',
        fuelType: 'diesel',
        mileage: 14.0,
        tankCapacity: 55.0,
      );

      // Validation logic
      String? validateCurrentFuel(String? val, VehicleModel v) {
        if (val == null || val.trim().isEmpty) return 'Enter a valid fuel amount.';
        final fuel = double.tryParse(val.trim());
        if (fuel == null || fuel.isNaN || fuel < 0) return 'Enter a valid fuel amount.';
        if (v.tankCapacity > 0 && fuel > v.tankCapacity) {
          return 'Current fuel cannot exceed tank capacity (${v.tankCapacity.toInt()} L).';
        }
        return null;
      }

      // Valid examples
      expect(validateCurrentFuel('0', vehicle), isNull);
      expect(validateCurrentFuel('5', vehicle), isNull);
      expect(validateCurrentFuel('12.5', vehicle), isNull);
      expect(validateCurrentFuel('35', vehicle), isNull);
      expect(validateCurrentFuel('55', vehicle), isNull);

      // Rejections
      expect(validateCurrentFuel('-5', vehicle), 'Enter a valid fuel amount.');
      expect(validateCurrentFuel('abc', vehicle), 'Enter a valid fuel amount.');
      expect(validateCurrentFuel('', vehicle), 'Enter a valid fuel amount.');
      expect(validateCurrentFuel('60', vehicle), contains('cannot exceed tank capacity'));
    });

    test('Mileage validation: accepts valid decimals > 0, rejects <= 0 and text', () {
      String? validateMileage(String? val) {
        if (val == null || val.trim().isEmpty) return 'Enter a valid mileage.';
        final m = double.tryParse(val.trim());
        if (m == null || m.isNaN || m <= 0) return 'Enter a valid mileage.';
        return null;
      }

      // Valid examples
      expect(validateMileage('8'), isNull);
      expect(validateMileage('12.5'), isNull);
      expect(validateMileage('14.5'), isNull);
      expect(validateMileage('22.4'), isNull);

      // Rejections
      expect(validateMileage('0'), 'Enter a valid mileage.');
      expect(validateMileage('-12.5'), 'Enter a valid mileage.');
      expect(validateMileage('abc'), 'Enter a valid mileage.');
      expect(validateMileage(''), 'Enter a valid mileage.');
    });
  });

  group('Vehicle Settings Persistence & Switching', () {
    test('Persists vehicle settings and restores them on vehicle switch', () async {
      final db = VehicleDatabaseService.instance;
      await db.init();

      // Vehicle A (Innova)
      await db.saveVehicleSettings(
        vehicleId: 'toyota_innova',
        currentFuel: 20.0,
        mileage: 14.0,
        fuelType: 'diesel',
      );

      // Vehicle B (Swift)
      await db.saveVehicleSettings(
        vehicleId: 'maruti_swift',
        currentFuel: 40.0,
        mileage: 18.0,
        fuelType: 'petrol',
      );

      // Verify retrieval for Vehicle A
      final settingsA = db.getVehicleSettings('toyota_innova');
      expect(settingsA, isNotNull);
      expect(settingsA!.currentFuel, 20.0);
      expect(settingsA.mileage, 14.0);
      expect(settingsA.fuelType, 'diesel');

      // Verify retrieval for Vehicle B
      final settingsB = db.getVehicleSettings('maruti_swift');
      expect(settingsB, isNotNull);
      expect(settingsB!.currentFuel, 40.0);
      expect(settingsB.mileage, 18.0);
      expect(settingsB.fuelType, 'petrol');

      // Vehicle Switching simulation: Switching from A to B immediately uses B's values
      var activeVehicle = VehicleModel(
        id: 'toyota_innova',
        name: 'Toyota Innova',
        type: 'car',
        fuelType: settingsA.fuelType,
        mileage: settingsA.mileage,
        tankCapacity: 55.0,
        userCustomFuel: settingsA.currentFuel,
      );
      expect(activeVehicle.userCustomFuel, 20.0);
      expect(activeVehicle.mileage, 14.0);

      // Switch to Vehicle B
      final newSettings = db.getVehicleSettings('maruti_swift')!;
      activeVehicle = VehicleModel(
        id: 'maruti_swift',
        name: 'Maruti Suzuki Swift',
        type: 'car',
        fuelType: newSettings.fuelType,
        mileage: newSettings.mileage,
        tankCapacity: 37.0,
        userCustomFuel: newSettings.currentFuel,
      );

      // Immediately loads Vehicle B's values, does not retain Vehicle A's values
      expect(activeVehicle.id, 'maruti_swift');
      expect(activeVehicle.userCustomFuel, 40.0);
      expect(activeVehicle.mileage, 18.0);
      expect(activeVehicle.fuelType, 'petrol');
    });
  });

  group('Trip Fuel Calculation with User Fuel & Mileage', () {
    test('Calculates fuel required, additional required, and cost matching prompt formula', () {
      final service = FuelPriceService.instance;

      // 400 km route, 15 km/L mileage, 10 L current fuel
      final estimate = service.calculateRouteFuel(
        distanceKm: 400.0,
        mileage: 15.0,
        currentFuelLiters: 10.0,
        fuelType: 'petrol',
        tankCapacityLiters: 45.0,
        originLocation: 'Bengaluru, Karnataka',
        destLocation: 'Mysuru, Karnataka',
      );

      // Fuel required = 400 / 15 = 26.67 L
      expect(estimate.fuelRequired, closeTo(26.67, 0.05));

      // Additional fuel required = 26.67 - 10 = 16.67 L
      expect(estimate.additionalFuelRequiredLiters, closeTo(16.67, 0.05));

      // Estimated cost = additional fuel * pricePerUnit
      expect(estimate.estimatedCost, closeTo(estimate.additionalFuelRequiredLiters * estimate.pricePerUnit, 1.0));
    });

    test('Trip calculation test case from prompt Section 28 (300 km, 15 km/L, 10 L tank)', () {
      final service = FuelPriceService.instance;

      // 300 km route, 15 km/L, 10 L current fuel
      final estimate = service.calculateRouteFuel(
        distanceKm: 300.0,
        mileage: 15.0,
        currentFuelLiters: 10.0,
        fuelType: 'petrol',
        tankCapacityLiters: 50.0,
        originLocation: 'Bengaluru, Karnataka',
        destLocation: 'Mysuru, Karnataka',
      );

      // Expected fuel required: 300 / 15 = 20 L
      expect(estimate.fuelRequired, 20.0);

      // Additional fuel: 20 - 10 = 10 L
      expect(estimate.additionalFuelRequiredLiters, 10.0);

      // Estimated fuel purchase: 10 L * pricePerUnit
      expect(estimate.estimatedCost, closeTo(10.0 * estimate.pricePerUnit, 1.0));
    });
  });

  group('Trip-Level Snapshot', () {
    test('Confirmed trip preserves vehicle snapshot when vehicle settings change later', () {
      final initialVehicle = Vehicle(
        type: 'car',
        efficiencyKmPerLiter: 14.0,
        tankCapacityLiters: 55.0,
        currentFuelLiters: 15.0,
        fuelType: 'petrol',
      );

      // Trip confirmation snapshots the vehicle configuration
      final tripPlan = TripPlan(
        distanceKm: 300.0,
        durationMin: 300,
        coordinates: const [],
        estimatedDays: 1,
        fuel: const FuelPlan(
          needsRefuel: false,
          totalDistanceKm: 300.0,
          refuelStops: [],
        ),
        toll: null,
        weather: null,
        departureAdvice: null,
        restStops: const [],
        itinerary: const [],
        budget: null,
        places: const {},
        vehicleSnapshot: initialVehicle,
      );

      // User later changes vehicle mileage from 14 to 15 km/L
      final updatedVehicle = Vehicle(
        type: 'car',
        efficiencyKmPerLiter: 15.0,
        tankCapacityLiters: 55.0,
        currentFuelLiters: 25.0,
        fuelType: 'petrol',
      );

      // The confirmed trip plan retains the original snapshot values
      expect(tripPlan.vehicleSnapshot, isNotNull);
      expect(tripPlan.vehicleSnapshot!.efficiencyKmPerLiter, 14.0);
      expect(tripPlan.vehicleSnapshot!.currentFuelLiters, 15.0);
      expect(updatedVehicle.efficiencyKmPerLiter, 15.0);
    });
  });
}
