import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travel_app/models/vehicles_data.dart';
import 'package:travel_app/services/destination_catalog_service.dart';
import 'package:travel_app/services/global_config_service.dart';

void main() {
  group('GlobalConfigService Unit Tests', () {
    test('Currency conversion and formatting', () {
      final config = GlobalConfigService.instance;
      config.setCurrency(Currency.usd);
      expect(config.currentCurrency, equals(Currency.usd));
      expect(config.formatMoney(86.5, decimals: 2), equals('\$1.00'));
      expect(config.formatMoney(86.5), equals('\$1'));

      config.setCurrency(Currency.eur);
      expect(config.formatMoney(93.0, decimals: 2), equals('€1.00'));

      config.setCurrency(Currency.inr);
      expect(config.formatMoney(500), equals('₹500'));
    });

    test('UnitSystem distance and speed formatting', () {
      final config = GlobalConfigService.instance;
      config.setUnitSystem(UnitSystem.metric);
      expect(config.formatDistance(100), equals('100 km'));
      expect(config.formatSpeed(80), equals('80 km/h'));

      config.setUnitSystem(UnitSystem.imperial);
      // 100 km in miles is ~62.1 mi
      expect(config.formatDistance(100), contains('mi'));
      expect(config.formatSpeed(100), contains('mph'));
    });

    test('Regional selection updates default currency and units', () async {
      final config = GlobalConfigService.instance;
      await config.setRegionById('US');
      expect(config.currentRegion.id, equals('US'));
      expect(config.currentCurrency, equals(Currency.usd));
      expect(config.currentUnitSystem, equals(UnitSystem.imperial));

      await config.setRegionById('IN');
      expect(config.currentRegion.id, equals('IN'));
      expect(config.currentCurrency, equals(Currency.inr));
      expect(config.currentUnitSystem, equals(UnitSystem.metric));
    });
  });

  group('DestinationCatalogService Unit Tests', () {
    test('Contains verified destinations across global regions', () {
      final catalog = DestinationCatalogService.instance;
      final inDests = catalog.getDestinationsForRegion('IN');
      expect(inDests.isNotEmpty, isTrue);
      expect(inDests.any((d) => d.name == 'Coorg'), isTrue);

      final usDests = catalog.getDestinationsForRegion('US');
      expect(usDests.isNotEmpty, isTrue);
      expect(usDests.any((d) => d.name.contains('Grand Canyon')), isTrue);

      final gbDests = catalog.getDestinationsForRegion('GB');
      expect(gbDests.isNotEmpty, isTrue);
      expect(gbDests.any((d) => d.name.contains('Lake District')), isTrue);

      final aeDests = catalog.getDestinationsForRegion('AE');
      expect(aeDests.isNotEmpty, isTrue);
      expect(aeDests.any((d) => d.name.contains('Dubai')), isTrue);

      final auDests = catalog.getDestinationsForRegion('AU');
      expect(auDests.isNotEmpty, isTrue);
      expect(auDests.any((d) => d.name.contains('Great Ocean Road')), isTrue);
    });

    test('Filters by category correctly', () {
      final catalog = DestinationCatalogService.instance;
      final mountainDests = catalog.getDestinationsForRegion('IN', category: 'mountains');
      expect(mountainDests.every((d) => d.category == 'mountains'), isTrue);
    });
  });

  group('VehicleModel icon mapping Unit Tests', () {
    test('Car, SUV, EV, Motorcycle, Van, and Truck icons resolve correctly', () {
      const car = VehicleModel(
        id: 'c1',
        name: 'Honda City',
        type: 'car',
        mileage: 18.0,
        tankCapacity: 40.0,
      );
      expect(car.icon, equals(Icons.directions_car_rounded));

      const suv = VehicleModel(
        id: 'c2',
        name: 'Mahindra XUV700',
        type: 'car',
        mileage: 14.0,
        tankCapacity: 60.0,
        bodyType: 'SUV',
      );
      expect(suv.icon, equals(Icons.directions_car_filled_rounded));

      const ev = VehicleModel(
        id: 'c3',
        name: 'Tata Nexon EV',
        type: 'car',
        mileage: 0.0,
        tankCapacity: 0.0,
        fuelType: 'ev',
      );
      expect(ev.icon, equals(Icons.electric_car_rounded));

      const bike = VehicleModel(
        id: 'b1',
        name: 'Royal Enfield Classic 350',
        type: 'motorcycle',
        mileage: 35.0,
        tankCapacity: 13.0,
      );
      expect(bike.icon, equals(Icons.two_wheeler_rounded));

      const evBike = VehicleModel(
        id: 'b2',
        name: 'Ather 450X',
        type: 'motorcycle',
        mileage: 0.0,
        tankCapacity: 0.0,
        fuelType: 'ev',
      );
      expect(evBike.icon, equals(Icons.electric_bike_rounded));

      const truck = VehicleModel(
        id: 't1',
        name: 'Tata Ace',
        type: 'car',
        mileage: 16.0,
        tankCapacity: 30.0,
        bodyType: 'Truck',
      );
      expect(truck.icon, equals(Icons.local_shipping_rounded));

      const van = VehicleModel(
        id: 'v1',
        name: 'Toyota Innova Crysta',
        type: 'car',
        mileage: 12.0,
        tankCapacity: 55.0,
        bodyType: 'MUV',
      );
      expect(van.icon, equals(Icons.airport_shuttle_rounded));
    });
  });
}
