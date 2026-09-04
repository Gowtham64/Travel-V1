import 'package:flutter_test/flutter_test.dart';
import 'package:travel_app/models/trip_models.dart';
import 'package:travel_app/services/toll_calculation_service.dart';

void main() {
  test('Toll calculation for Bengaluru to Mysuru (NH-275)', () {
    final tollService = TollCalculationService.instance;
    final blrMysCoords = [
      const GeoPoint(lat: 12.9716, lng: 77.5946), // Bangalore
      const GeoPoint(lat: 12.8300, lng: 77.4200), // Kaniminike
      const GeoPoint(lat: 12.6000, lng: 77.0500), // Maddur
      const GeoPoint(lat: 12.4300, lng: 76.7300), // Gananguru
      const GeoPoint(lat: 12.2958, lng: 76.6394), // Mysuru
    ];

    final carToll = tollService.calculateTolls(
      start: blrMysCoords.first,
      end: blrMysCoords.last,
      vehicleType: 'car',
      routeCoordinates: blrMysCoords,
    );

    expect(carToll.hasTolls, true);
    expect(carToll.tollCount, 2);
    expect(carToll.fastagTollCost, 320.0); // 165 + 155
    expect(carToll.cashTollCost, 640.0);
    expect(carToll.tolls.first.name, 'Kaniminike Toll Plaza');
    expect(carToll.tolls.last.name, 'Gananguru Toll Plaza');

    final busToll = tollService.calculateTolls(
      start: blrMysCoords.first,
      end: blrMysCoords.last,
      vehicleType: 'bus',
      routeCoordinates: blrMysCoords,
    );
    expect(busToll.fastagTollCost, 1090.0); // 565 + 525

    final bikeToll = tollService.calculateTolls(
      start: blrMysCoords.first,
      end: blrMysCoords.last,
      vehicleType: 'bike',
      routeCoordinates: blrMysCoords,
    );
    expect(bikeToll.fastagTollCost, 0.0);
  });

  test('Local city trip has 0 tolls', () {
    final tollService = TollCalculationService.instance;
    final localCityCoords = [
      const GeoPoint(lat: 12.9716, lng: 77.5946),
      const GeoPoint(lat: 12.9352, lng: 77.6245),
      const GeoPoint(lat: 12.9141, lng: 77.6411),
    ];
    final cityToll = tollService.calculateTolls(
      start: localCityCoords.first,
      end: localCityCoords.last,
      vehicleType: 'car',
      routeCoordinates: localCityCoords,
    );
    expect(cityToll.hasTolls, false);
    expect(cityToll.tollCount, 0);
    expect(cityToll.fastagTollCost, 0.0);
  });

  test('Multi-leg around trip accumulates return crossing', () {
    final tollService = TollCalculationService.instance;
    final leg1 = [
      const GeoPoint(lat: 12.9716, lng: 77.5946),
      const GeoPoint(lat: 12.8300, lng: 77.4200),
      const GeoPoint(lat: 12.4300, lng: 76.7300),
      const GeoPoint(lat: 12.2958, lng: 76.6394),
    ];
    final leg2 = [
      const GeoPoint(lat: 12.2958, lng: 76.6394),
      const GeoPoint(lat: 12.4300, lng: 76.7300),
      const GeoPoint(lat: 12.8300, lng: 77.4200),
      const GeoPoint(lat: 12.9716, lng: 77.5946),
    ];

    final aroundTrip = tollService.calculateMultiLegTolls(
      allStops: [leg1.first, leg1.last, leg2.last],
      vehicleType: 'car',
      legCoordinates: [leg1, leg2],
    );

    expect(aroundTrip.hasTolls, true);
    expect(aroundTrip.tollCount, 4); // 2 outbound + 2 return
    expect(aroundTrip.fastagTollCost, 640.0); // 320 + 320
  });
}
