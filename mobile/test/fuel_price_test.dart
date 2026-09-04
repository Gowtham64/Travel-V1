import 'package:flutter_test/flutter_test.dart';
import 'package:travel_app/services/fuel_price_service.dart';
import 'package:travel_app/models/vehicles_data.dart';

void main() {
  group('FuelPriceService Tests', () {
    final service = FuelPriceService.instance;

    test('Resolves location by text correctly', () {
      final bglr = service.resolveLocation(locationName: 'Bengaluru, Karnataka');
      expect(bglr.state, 'karnataka');
      expect(bglr.city, 'bengaluru');

      final mys = service.resolveLocation(locationName: 'Mysuru Palace, Mysore');
      expect(mys.state, 'karnataka');
      expect(mys.city, 'mysuru');

      final mum = service.resolveLocation(locationName: 'Marine Drive, Mumbai');
      expect(mum.state, 'maharashtra');
      expect(mum.city, 'mumbai');

      final chn = service.resolveLocation(locationName: 'Marina Beach, Chennai');
      expect(chn.state, 'tamil_nadu');
      expect(chn.city, 'chennai');
    });

    test('Resolves location by coordinates correctly', () {
      // Bengaluru coordinates
      final loc = service.resolveLocation(lat: 12.9716, lng: 77.5946);
      expect(loc.state, 'karnataka');
      expect(loc.city, 'bengaluru');

      // Mumbai coordinates
      final locMum = service.resolveLocation(lat: 19.0760, lng: 72.8777);
      expect(locMum.state, 'maharashtra');
      expect(locMum.city, 'mumbai');
    });

    test('Returns location-specific Petrol and Diesel prices', () {
      final petrolBglr = service.getFuelPrice(locationName: 'Bengaluru', fuelType: 'petrol');
      final dieselBglr = service.getFuelPrice(locationName: 'Bengaluru', fuelType: 'diesel');

      expect(petrolBglr.price, 102.86);
      expect(dieselBglr.price, 88.94);
      expect(petrolBglr.currencySymbol, '₹');
      expect(petrolBglr.currency, 'INR');
      expect(petrolBglr.unit, '₹/L');

      final petrolMum = service.getFuelPrice(locationName: 'Mumbai', fuelType: 'petrol');
      final dieselMum = service.getFuelPrice(locationName: 'Mumbai', fuelType: 'diesel');

      expect(petrolMum.price, 104.21);
      expect(dieselMum.price, 92.15);
    });

    test('Calculates route fuel accurately based on distance, efficiency, and fuel type', () {
      // 150 km trip in Bengaluru with 15 km/L petrol car
      final petrolEst = service.calculateRouteFuel(
        distanceKm: 150.0,
        mileage: 15.0,
        fuelType: 'petrol',
        originLocation: 'Bengaluru',
        destLocation: 'Mysuru',
      );

      // Liters = 150 / 15 = 10 L
      expect(petrolEst.fuelRequiredLiters, 10.0);
      // Petrol price in Karnataka ~102.86 (or avg between Bengaluru 102.86 & Mysuru 102.34 = 102.60)
      expect(petrolEst.totalFuelCost, greaterThan(1020.0));
      expect(petrolEst.totalFuelCost, lessThan(1030.0));

      // Same trip with 10 km/L diesel SUV
      final dieselEst = service.calculateRouteFuel(
        distanceKm: 150.0,
        mileage: 10.0,
        fuelType: 'diesel',
        originLocation: 'Bengaluru',
        destLocation: 'Mysuru',
      );

      // Liters = 150 / 10 = 15 L
      expect(dieselEst.fuelRequiredLiters, 15.0);
      // Diesel price ~88.70 * 15 = ~1330.5
      expect(dieselEst.totalFuelCost, greaterThan(1320.0));
      expect(dieselEst.totalFuelCost, lessThan(1340.0));
    });

    test('Predefined vehicles have correct fuelType assigned', () {
      final fortuner = predefinedVehicles.firstWhere((v) => v.id == 'fortuner');
      expect(fortuner.fuelType, 'diesel');

      final innova = predefinedVehicles.firstWhere((v) => v.id == 'innova');
      expect(innova.fuelType, 'diesel');

      final harrier = predefinedVehicles.firstWhere((v) => v.id == 'harrier');
      expect(harrier.fuelType, 'diesel');

      final swift = predefinedVehicles.firstWhere((v) => v.id == 'swift');
      expect(swift.fuelType, 'petrol');
    });
  });
}
