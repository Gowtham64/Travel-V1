import 'package:latlong2/latlong.dart';

class GeoPoint {
  final double lat;
  final double lng;

  const GeoPoint({required this.lat, required this.lng});

  factory GeoPoint.fromJson(Map<String, dynamic> json) =>
      GeoPoint(lat: (json['lat'] as num).toDouble(), lng: (json['lng'] as num).toDouble());

  LatLng toLatLng() => LatLng(lat, lng);
}

class Vehicle {
  final String type; // car | suv | motorcycle | bus | rv | truck2axle | truck3axle
  final double efficiencyKmPerLiter;
  final double tankCapacityLiters;
  final double currentFuelLiters;

  const Vehicle({
    required this.type,
    required this.efficiencyKmPerLiter,
    required this.tankCapacityLiters,
    required this.currentFuelLiters,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'efficiencyKmPerLiter': efficiencyKmPerLiter,
        'tankCapacityLiters': tankCapacityLiters,
        'currentFuelLiters': currentFuelLiters,
      };
}

class RefuelStop {
  final double lat;
  final double lng;
  final double distanceFromStartKm;

  const RefuelStop({required this.lat, required this.lng, required this.distanceFromStartKm});

  factory RefuelStop.fromJson(Map<String, dynamic> json) => RefuelStop(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        distanceFromStartKm: (json['distanceFromStartKm'] as num).toDouble(),
      );

  LatLng toLatLng() => LatLng(lat, lng);
}

class FuelPlan {
  final bool needsRefuel;
  final double totalDistanceKm;
  final List<RefuelStop> refuelStops;

  const FuelPlan({required this.needsRefuel, required this.totalDistanceKm, required this.refuelStops});

  factory FuelPlan.fromJson(Map<String, dynamic> json) => FuelPlan(
        needsRefuel: json['needsRefuel'] as bool,
        totalDistanceKm: (json['totalDistanceKm'] as num).toDouble(),
        refuelStops: (json['refuelStops'] as List)
            .map((e) => RefuelStop.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class TollEstimate {
  final bool hasTolls;
  final String currency;
  final double? minTollCost;
  final double? maxTollCost;
  final double? fuelCost;

  const TollEstimate({
    required this.hasTolls,
    required this.currency,
    this.minTollCost,
    this.maxTollCost,
    this.fuelCost,
  });

  factory TollEstimate.fromJson(Map<String, dynamic> json) => TollEstimate(
        hasTolls: json['hasTolls'] as bool? ?? false,
        currency: json['currency'] as String? ?? '',
        minTollCost: (json['minTollCost'] as num?)?.toDouble(),
        maxTollCost: (json['maxTollCost'] as num?)?.toDouble(),
        fuelCost: (json['fuelCost'] as num?)?.toDouble(),
      );
}

class PlaceOfInterest {
  final int id;
  final String name;
  final double lat;
  final double lng;
  final String? address;

  const PlaceOfInterest({required this.id, required this.name, required this.lat, required this.lng, this.address});

  factory PlaceOfInterest.fromJson(Map<String, dynamic> json) => PlaceOfInterest(
        id: json['id'] as int,
        name: json['name'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        address: json['address'] as String?,
      );

  LatLng toLatLng() => LatLng(lat, lng);
}

class TripPlan {
  final double distanceKm;
  final int durationMin;
  final List<GeoPoint> coordinates;
  final int estimatedDays;
  final FuelPlan fuel;
  final TollEstimate? toll;
  final Map<String, List<PlaceOfInterest>> places;

  const TripPlan({
    required this.distanceKm,
    required this.durationMin,
    required this.coordinates,
    required this.estimatedDays,
    required this.fuel,
    required this.toll,
    required this.places,
  });

  factory TripPlan.fromJson(Map<String, dynamic> json) {
    final route = json['route'] as Map<String, dynamic>;
    final placesJson = (json['places'] as Map<String, dynamic>? ?? {});

    return TripPlan(
      distanceKm: (route['distanceKm'] as num).toDouble(),
      durationMin: (route['durationMin'] as num).toInt(),
      coordinates: (route['coordinates'] as List)
          .map((e) => GeoPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      estimatedDays: json['estimatedDays'] as int,
      fuel: FuelPlan.fromJson(json['fuel'] as Map<String, dynamic>),
      toll: json['toll'] != null ? TollEstimate.fromJson(json['toll'] as Map<String, dynamic>) : null,
      places: placesJson.map(
        (key, value) => MapEntry(
          key,
          (value as List).map((e) => PlaceOfInterest.fromJson(e as Map<String, dynamic>)).toList(),
        ),
      ),
    );
  }
}
