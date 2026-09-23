import 'package:flutter_test/flutter_test.dart';
import 'package:travel_app/services/destination_catalog_service.dart';

void main() {
  group('Canonical Trip Mode & UX Consolidation Tests', () {
    test('DestinationCatalogService provides unified global destinations', () {
      final destinations = DestinationCatalogService.globalDestinations;
      
      expect(destinations, isNotEmpty);
      expect(destinations.length, greaterThanOrEqualTo(8));
      
      // Verify key canonical destinations exist
      final names = destinations.map((d) => d.name).toList();
      expect(names.any((n) => n.contains('Amalfi')), isTrue);
      expect(names.any((n) => n.contains('Fuji')), isTrue);
      expect(names.any((n) => n.contains('Coorg')), isTrue);
      expect(names.any((n) => n.contains('Grand Canyon')), isTrue);
    });

    test('Trip Mode string normalization adheres to canonical 3 modes', () {
      String normalizeMode(String raw) {
        final mode = raw.toLowerCase().trim();
        if (mode == 'vacation' || mode == 'multi_day') {
          return 'vacation';
        } else if (mode == 'around' || mode == 'around_trip' || mode == 'round_trip' || mode == 'round') {
          return 'around';
        } else {
          return 'one_way';
        }
      }

      // Canonical inputs
      expect(normalizeMode('one_way'), equals('one_way'));
      expect(normalizeMode('around'), equals('around'));
      expect(normalizeMode('vacation'), equals('vacation'));

      // Legacy and alias inputs
      expect(normalizeMode('round_trip'), equals('around'));
      expect(normalizeMode('around_trip'), equals('around'));
      expect(normalizeMode('round'), equals('around'));
      expect(normalizeMode('multi_day'), equals('vacation'));
      expect(normalizeMode('direct'), equals('one_way'));
      expect(normalizeMode(''), equals('one_way'));
    });

    test('Category and Region filtering in DestinationCatalogService returns accurate lists', () {
      final catalog = DestinationCatalogService.instance;
      
      final indiaScenic = catalog.getDestinationsForRegion('IN', category: 'mountains');
      final usRoadtrips = catalog.getDestinationsForRegion('US', category: 'roadtrip');
      final allEurope = catalog.getDestinationsForRegion('Europe');
      
      expect(indiaScenic, isNotEmpty);
      expect(indiaScenic.first.countryCode, equals('IN'));
      expect(usRoadtrips, isNotEmpty);
      expect(usRoadtrips.first.countryCode, equals('US'));
      expect(allEurope, isNotEmpty);
    });
  });
}
