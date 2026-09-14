import 'package:flutter_test/flutter_test.dart';
import 'package:travel_app/data/venue_database.dart';
import 'package:travel_app/models/trip_models.dart';
import 'package:travel_app/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dynamic Distance Resolution & Curated Venues (Flutter Mobile)', () {
    test('VenueDatabase returns authentic curated Goa venues instead of synthesized dummy', () {
      final lunch = VenueDatabase.getBestVenue(destination: 'Goa', type: 'lunch');
      expect(lunch.name, contains('Ritz Classic'));
      expect(lunch.rating, greaterThanOrEqualTo(4.7));

      final hotel = VenueDatabase.getBestVenue(destination: 'Goa', type: 'hotel');
      expect(hotel.name, contains('Taj Fort Aguada'));
      expect(hotel.priceRange, equals('₹₹₹'));

      final dinner = VenueDatabase.getBestVenue(destination: 'Goa', type: 'dinner');
      expect(dinner.name, contains("Fisherman's Wharf"));
    });

    test('aiSmartItinerary calculates realistic ~560 km distance for Maddur to Goa (NOT 145 km)', () async {
      final apiService = ApiService();
      final res = await apiService.aiSmartItinerary(
        destination: 'Goa',
        startLocation: 'Main Road 57, Maddur, 571419, India',
        places: ['Calangute Beach', 'Fort Aguada'],
        durationDays: 2,
        startTime: '06:00',
      );

      expect(res.days, isNotEmpty);
      final day1 = res.days.first;
      expect(day1.blocks, isNotEmpty);

      final travelBlock = day1.blocks.firstWhere((b) => b.type == 'travel');
      expect(travelBlock.travelMode, equals('drive'));
      expect(travelBlock.distanceKm, isNotNull);
      expect(travelBlock.distanceKm!, greaterThan(500));
      expect(travelBlock.distanceKm!, lessThan(600));
      expect(travelBlock.distanceKm!, isNot(equals(145.0)));

      // Paced highway morning drive segment (capped before lunch at 300 mins), definitely not dummy 145 mins
      expect(travelBlock.durationMin, greaterThanOrEqualTo(300));
      expect(travelBlock.durationMin, isNot(equals(145)));
    });

    test('aiSmartItinerary calculates realistic ~70 km distance for Maddur to Mysuru (NOT 145 km)', () async {
      final apiService = ApiService();
      final res = await apiService.aiSmartItinerary(
        destination: 'Mysuru',
        startLocation: 'Maddur',
        places: ['Mysore Palace'],
        durationDays: 1,
        startTime: '07:00',
      );

      final day1 = res.days.first;
      final travelBlock = day1.blocks.firstWhere((b) => b.type == 'travel');
      expect(travelBlock.distanceKm, isNotNull);
      expect(travelBlock.distanceKm!, greaterThan(55));
      expect(travelBlock.distanceKm!, lessThan(85));
      expect(travelBlock.distanceKm!, isNot(equals(145.0)));
    });

    test('VenueDatabase returns authentic curated Mumbai venues instead of synthesized dummy', () {
      final lunch = VenueDatabase.getBestVenue(destination: 'Mumbai, Maharashtra, India', type: 'lunch');
      expect(lunch.name, contains('Shree Thaker Bhojanalay'));
      expect(lunch.rating, greaterThanOrEqualTo(4.7));

      final hotel = VenueDatabase.getBestVenue(destination: 'Mumbai, Maharashtra, India', type: 'hotel');
      expect(hotel.name, contains('The Taj Mahal Palace'));
      expect(hotel.priceRange, equals('₹₹₹'));

      final dinner = VenueDatabase.getBestVenue(destination: 'Mumbai, Maharashtra, India', type: 'dinner');
      expect(dinner.name, contains('Mahesh Lunch Home'));
    });

    test('aiSmartItinerary calculates realistic ~1020 km distance for Maddur to Mumbai (NOT 145 km)', () async {
      final apiService = ApiService();
      final res = await apiService.aiSmartItinerary(
        destination: 'Mumbai, Maharashtra, India',
        startLocation: 'Main Road 57, Maddur, 571419, India',
        places: ['Gateway of India', 'Marine Drive'],
        durationDays: 3,
        startTime: '08:00',
      );

      expect(res.days, isNotEmpty);
      final day1 = res.days.first;
      expect(day1.blocks, isNotEmpty);

      final travelBlock = day1.blocks.firstWhere((b) => b.type == 'travel');
      expect(travelBlock.travelMode, equals('drive'));
      expect(travelBlock.distanceKm, isNotNull);
      // Maddur to Mumbai is ~980 to 1100 km, definitely NOT 145.0 km
      expect(travelBlock.distanceKm!, greaterThan(900));
      expect(travelBlock.distanceKm!, lessThan(1200));
      expect(travelBlock.distanceKm!, isNot(equals(145.0)));

      // Day 1 Drive duration is paced and definitely NOT 145 mins
      expect(travelBlock.durationMin, isNot(equals(145)));
    });

    test('aiSmartItinerary detects overseas route (India to Philippines) as flight > 4,500 km', () async {
      final apiService = ApiService();
      final res = await apiService.aiSmartItinerary(
        destination: 'Goa, Camarines Sur, Philippines',
        startLocation: 'Main Road 57, Maddur, 571419, India',
        places: [],
        durationDays: 2,
        startTime: '06:00',
      );

      final day1 = res.days.first;
      final travelBlock = day1.blocks.firstWhere((b) => b.type == 'travel');
      expect(travelBlock.travelMode, equals('flight'));
      expect(travelBlock.title, contains('Flight'));
      expect(travelBlock.distanceKm, isNotNull);
      expect(travelBlock.distanceKm!, greaterThan(4500));
      expect(travelBlock.distanceKm!, lessThan(5500));
      expect(travelBlock.distanceKm!, isNot(equals(145.0)));
    });
  });
}
