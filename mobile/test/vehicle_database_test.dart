import 'package:flutter_test/flutter_test.dart';
import 'package:travel_app/models/vehicles_data.dart';
import 'package:travel_app/services/vehicle_database_service.dart';

void main() {
  group('Vehicle Database & Search Tests', () {
    final service = VehicleDatabaseService.instance;

    setUp(() async {
      await service.init();
    });

    test('Retrieves vehicle brands list', () async {
      final brands = await service.getBrands();
      expect(brands.isNotEmpty, true);
      final brandNames = brands.map((b) => b.name.toLowerCase()).toList();
      expect(brandNames.any((n) => n.contains('tata')), true);
      expect(brandNames.any((n) => n.contains('mahindra')), true);
      expect(brandNames.any((n) => n.contains('toyota')), true);
      expect(brandNames.any((n) => n.contains('hyundai')), true);
    });

    test('Searches vehicles dynamically by model name', () async {
      final innovaList = await service.searchVehicles('Innova');
      expect(innovaList.isNotEmpty, true);
      expect(innovaList.any((v) => v.name.contains('Innova')), true);

      final fortunerList = await service.searchVehicles('Fortuner');
      expect(fortunerList.isNotEmpty, true);
      expect(fortunerList.first.fuelType, 'diesel');
    });

    test('Filters vehicles by fuel type correctly', () async {
      final evList = await service.searchVehicles('', fuelType: 'ev');
      expect(evList.isNotEmpty, true);
      for (final ev in evList) {
        expect(ev.fuelType, 'ev');
      }

      final dieselList = await service.searchVehicles('', fuelType: 'diesel');
      expect(dieselList.isNotEmpty, true);
      for (final d in dieselList) {
        expect(d.fuelType, 'diesel');
      }
    });

    test('User custom mileage override works with high priority', () {
      const stockCar = VehicleModel(
        id: 'innova',
        name: 'Toyota Innova Crysta',
        type: 'car',
        mileage: 12.0,
        tankCapacity: 55.0,
        fuelType: 'diesel',
      );

      // Default should be stock mileage
      expect(stockCar.effectiveMileage, 12.0);
      expect(stockCar.isUserMileageOverride, false);

      // Apply user mileage override (e.g. 14.5 km/L)
      final overriddenCar = stockCar.copyWith(
        isUserMileageOverride: true,
        userCustomMileage: 14.5,
      );

      expect(overriddenCar.isUserMileageOverride, true);
      expect(overriddenCar.effectiveMileage, 14.5);
    });

    test('Serializes and deserializes VehicleModel with rich CarDekho fields', () {
      const original = VehicleModel(
        id: 'tata_nexon_ev',
        name: 'Tata Nexon.ev',
        type: 'car',
        mileage: 0.0,
        tankCapacity: 0.0,
        fuelType: 'ev',
        brandId: 'tata',
        brandName: 'Tata Motors',
        modelId: 'nexon_ev',
        modelName: 'Nexon.ev',
        variantId: 'empowered_plus',
        variantName: 'Empowered Plus 45 kWh Long Range',
        batteryCapacityKwh: 45.0,
        evRangeKm: 465,
        engine: '143 bhp PMSM',
        transmission: 'Single Speed Automatic',
        seatingCapacity: 5,
        bodyType: 'Compact SUV',
        priceRange: '₹14.49 - 19.49 Lakh',
        modelYear: 2026,
        source: 'CarDekho',
        dataVersion: '2026.3.1',
      );

      final json = original.toJson();
      final parsed = VehicleModel.fromJson(json);

      expect(parsed.id, original.id);
      expect(parsed.fuelType, 'ev');
      expect(parsed.batteryCapacityKwh, 45.0);
      expect(parsed.evRangeKm, 465);
      expect(parsed.brandName, 'Tata Motors');
      expect(parsed.source, 'CarDekho');
    });
  });
}
