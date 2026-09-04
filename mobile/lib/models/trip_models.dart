import 'package:latlong2/latlong.dart';

class GeoPoint {
  final double lat;
  final double lng;
  final String? name;

  const GeoPoint({required this.lat, required this.lng, this.name});

  factory GeoPoint.fromJson(Map<String, dynamic> json) =>
      GeoPoint(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        name: json['name'] as String?,
      );

  LatLng toLatLng() => LatLng(lat, lng);
}

class Vehicle {
  final String type; // car | suv | motorcycle | bus | rv | truck2axle | truck3axle
  final double efficiencyKmPerLiter;
  final double tankCapacityLiters;
  final double currentFuelLiters;
  final String fuelType; // petrol | diesel | cng | ev
  final bool isCustomEfficiency;

  const Vehicle({
    required this.type,
    required this.efficiencyKmPerLiter,
    required this.tankCapacityLiters,
    required this.currentFuelLiters,
    this.fuelType = 'petrol',
    this.isCustomEfficiency = false,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'efficiencyKmPerLiter': efficiencyKmPerLiter,
        'tankCapacityLiters': tankCapacityLiters,
        'currentFuelLiters': currentFuelLiters,
        'fuelType': fuelType,
        'isCustomEfficiency': isCustomEfficiency,
      };

  factory Vehicle.fromJson(Map<String, dynamic> json) => Vehicle(
        type: json['type'] as String? ?? 'car',
        efficiencyKmPerLiter:
            (json['efficiencyKmPerLiter'] as num?)?.toDouble() ?? 15.0,
        tankCapacityLiters:
            (json['tankCapacityLiters'] as num?)?.toDouble() ?? 45.0,
        currentFuelLiters:
            (json['currentFuelLiters'] as num?)?.toDouble() ?? 45.0,
        fuelType: json['fuelType'] as String? ?? 'petrol',
        isCustomEfficiency: json['isCustomEfficiency'] as bool? ?? false,
      );

  Vehicle copyWith({
    String? type,
    double? efficiencyKmPerLiter,
    double? tankCapacityLiters,
    double? currentFuelLiters,
    String? fuelType,
    bool? isCustomEfficiency,
  }) {
    return Vehicle(
      type: type ?? this.type,
      efficiencyKmPerLiter: efficiencyKmPerLiter ?? this.efficiencyKmPerLiter,
      tankCapacityLiters: tankCapacityLiters ?? this.tankCapacityLiters,
      currentFuelLiters: currentFuelLiters ?? this.currentFuelLiters,
      fuelType: fuelType ?? this.fuelType,
      isCustomEfficiency: isCustomEfficiency ?? this.isCustomEfficiency,
    );
  }
}

class RefuelStop {
  final double lat;
  final double lng;
  final double distanceFromStartKm;

  /// Name of the real fuel station this stop snaps to (empty for legacy/geometric stops).
  final String name;

  /// OSM id of the station, when snapped to a real pump.
  final int? stationId;

  /// How far this station sits off the driving route, in km.
  final double? offRouteKm;

  /// Estimated fuel left in the tank when arriving at this station, in litres.
  final double? fuelOnArrivalLiters;

  const RefuelStop({
    required this.lat,
    required this.lng,
    required this.distanceFromStartKm,
    this.name = '',
    this.stationId,
    this.offRouteKm,
    this.fuelOnArrivalLiters,
  });

  /// True when this stop is a real, named fuel station rather than a geometric marker.
  bool get isRealStation => name.isNotEmpty;

  factory RefuelStop.fromJson(Map<String, dynamic> json) => RefuelStop(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        distanceFromStartKm: (json['distanceFromStartKm'] as num).toDouble(),
        name: (json['name'] as String?) ?? '',
        stationId: (json['stationId'] as num?)?.toInt(),
        offRouteKm: (json['offRouteKm'] as num?)?.toDouble(),
        fuelOnArrivalLiters: (json['fuelOnArrivalLiters'] as num?)?.toDouble(),
      );

  LatLng toLatLng() => LatLng(lat, lng);
}

/// A hiking/trekking trail surfaced by the AllTrails-style discovery feature.
class Trek {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final double distanceFromSearchKm;
  final double? lengthKm;
  final String? difficulty;
  final String type;
  final String? description;
  final String? imageUrl;

  /// Ordered trail geometry (may be empty when OSM has no line for it).
  final List<LatLng> path;

  const Trek({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.distanceFromSearchKm,
    this.lengthKm,
    this.difficulty,
    this.type = 'trail',
    this.description,
    this.imageUrl,
    this.path = const [],
  });

  bool get hasPath => path.length > 1;

  LatLng toLatLng() => LatLng(lat, lng);
  GeoPoint toGeoPoint() => GeoPoint(lat: lat, lng: lng, name: name);

  factory Trek.fromJson(Map<String, dynamic> json) => Trek(
        id: json['id'] as String,
        name: json['name'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        distanceFromSearchKm: (json['distanceFromSearchKm'] as num?)?.toDouble() ?? 0,
        lengthKm: (json['lengthKm'] as num?)?.toDouble(),
        difficulty: json['difficulty'] as String?,
        type: (json['type'] as String?) ?? 'trail',
        description: json['description'] as String?,
        imageUrl: json['imageUrl'] as String?,
        path: (json['path'] as List? ?? [])
            .map((e) => LatLng(
                  ((e as Map)['lat'] as num).toDouble(),
                  (e['lng'] as num).toDouble(),
                ))
            .toList(),
      );
}

/// One time block in the smart AI itinerary timeline.
class TimelineBlock {
  String start;
  String end;
  final String type; // start|activity|travel|meal|coffee|rest|checkin|checkout|buffer|shopping|freetime|return
  String title;
  final String place;
  final int durationMin;
  final int travelMin;
  final double distanceKm;
  final String breakType; // breakfast|lunch|dinner|... (for meal/break blocks)
  final String reason;
  final String travelMode; // drive|flight|train|bus|ferry|walk (travel/return legs)
  final List<String> categories; // matched place categories
  final String whyIncluded; // explanation for why this stop was chosen

  TimelineBlock({
    required this.start,
    required this.end,
    required this.type,
    required this.title,
    this.place = '',
    this.durationMin = 0,
    this.travelMin = 0,
    this.distanceKm = 0,
    this.breakType = '',
    this.reason = '',
    this.travelMode = '',
    this.categories = const [],
    this.whyIncluded = '',
  });

  factory TimelineBlock.fromJson(Map<String, dynamic> j) => TimelineBlock(
        start: (j['start'] ?? '').toString(),
        end: (j['end'] ?? '').toString(),
        type: (j['type'] ?? 'activity').toString(),
        title: (j['title'] ?? '').toString(),
        place: (j['place'] ?? '').toString(),
        durationMin: (j['durationMin'] as num?)?.toInt() ?? 0,
        travelMin: (j['travelMin'] as num?)?.toInt() ?? 0,
        distanceKm: (j['distanceKm'] as num?)?.toDouble() ?? 0,
        breakType: (j['breakType'] ?? '').toString(),
        reason: (j['reason'] ?? '').toString(),
        travelMode: (j['travelMode'] ?? '').toString(),
        categories: (j['categories'] as List? ?? [])
            .map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .toList(),
        whyIncluded: (j['whyIncluded'] ?? '').toString(),
      );
}

class PlaceCategoryOption {
  final String id;
  final String label;
  final String icon;
  final String description;

  const PlaceCategoryOption({
    required this.id,
    required this.label,
    required this.icon,
    this.description = '',
  });
}

const List<PlaceCategoryOption> kPlaceCategories = [
  PlaceCategoryOption(id: 'temples', label: 'Temples & Religious Places', icon: '🛕', description: 'Sacred shrines, heritage temples & spiritual places'),
  PlaceCategoryOption(id: 'waterfalls_rivers', label: 'Rivers, Lakes & Waterfalls', icon: '🌊', description: 'Scenic falls, rivers, boating lakes & watersides'),
  PlaceCategoryOption(id: 'viewpoints', label: 'Viewpoints & Scenic Places', icon: '🌄', description: 'Panoramic vistas, valleys & sunrise/sunset spots'),
  PlaceCategoryOption(id: 'hills_mountains', label: 'Hills & Mountains', icon: '⛰️', description: 'Hill stations, mountain peaks & cool altitudes'),
  PlaceCategoryOption(id: 'historical_heritage', label: 'Historical & Heritage Places', icon: '🏛️', description: 'Ancient ruins, UNESCO sites & archaeological wonders'),
  PlaceCategoryOption(id: 'famous_places', label: 'Famous / Must-Visit Places', icon: '⭐', description: 'Top-rated bucket list landmarks & signature spots'),
  PlaceCategoryOption(id: 'forts_palaces', label: 'Forts & Palaces', icon: '🏰', description: 'Royal residences, hill forts & grand architecture'),
  PlaceCategoryOption(id: 'nature_forests', label: 'Nature & Forests', icon: '🌳', description: 'Botanical gardens, lush plantations & green trails'),
  PlaceCategoryOption(id: 'beaches', label: 'Beaches', icon: '🏖️', description: 'Golden sands, coastal shores & ocean viewpoints'),
  PlaceCategoryOption(id: 'wildlife_national_parks', label: 'Wildlife & National Parks', icon: '🐘', description: 'Animal sanctuaries, safari parks & reserves'),
  PlaceCategoryOption(id: 'monuments_landmarks', label: 'Monuments & Landmarks', icon: '🗿', description: 'Iconic statues, memorials & architectural pillars'),
  PlaceCategoryOption(id: 'city_attractions', label: 'Famous City Attractions', icon: '🏙️', description: 'Urban sights, city plazas & modern landmarks'),
  PlaceCategoryOption(id: 'bridges_dams', label: 'Famous Bridges / Dams', icon: '🌉', description: 'Mega reservoirs, scenic dams & historic bridges'),
  PlaceCategoryOption(id: 'markets_local', label: 'Famous Markets & Local Places', icon: '🛍️', description: 'Traditional bazaars, local craft streets & food lanes'),
  PlaceCategoryOption(id: 'cultural_places', label: 'Cultural Places', icon: '🎨', description: 'Art galleries, folk villages & cultural centers'),
  PlaceCategoryOption(id: 'photography_spots', label: 'Instagrammable / Photography Spots', icon: '📸', description: 'Aesthetic photo locations & picturesque backdrops'),
];

/// One day of the smart AI itinerary timeline.
class SmartDay {
  final int day;
  final String date;
  final String title;
  final List<TimelineBlock> blocks;

  SmartDay({required this.day, this.date = '', this.title = '', required this.blocks});

  factory SmartDay.fromJson(Map<String, dynamic> j) => SmartDay(
        day: (j['day'] as num?)?.toInt() ?? 1,
        date: (j['date'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        blocks: (j['blocks'] as List? ?? [])
            .map((e) => TimelineBlock.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class FuelPlan {
  final bool needsRefuel;
  final double totalDistanceKm;
  final List<RefuelStop> refuelStops;

  /// True when part of the route has no reachable fuel station on the current
  /// plan — the driver risks running dry and should carry extra fuel or reroute.
  final bool unreachable;

  const FuelPlan({
    required this.needsRefuel,
    required this.totalDistanceKm,
    required this.refuelStops,
    this.unreachable = false,
  });

  factory FuelPlan.fromJson(Map<String, dynamic> json) => FuelPlan(
        needsRefuel: json['needsRefuel'] as bool,
        totalDistanceKm: (json['totalDistanceKm'] as num).toDouble(),
        unreachable: (json['unreachable'] as bool?) ?? false,
        refuelStops: (json['refuelStops'] as List)
            .map((e) => RefuelStop.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class FuelPrice {
  final String country;
  final String countryCode;
  final String state;
  final String city;
  final String fuelType;
  final double price;
  final String currency;
  final String currencySymbol;
  final String unit;
  final String effectiveAt;
  final String lastUpdated;
  final String source;
  final String status; // 'live' | 'cached' | 'estimated' | 'unavailable'
  final String confidence; // 'high' | 'medium' | 'low'
  final Map<String, double> allPrices;

  const FuelPrice({
    required this.country,
    this.countryCode = 'IN',
    required this.state,
    required this.city,
    required this.fuelType,
    required this.price,
    this.currency = 'INR',
    this.currencySymbol = '₹',
    this.unit = 'litre',
    required this.effectiveAt,
    required this.lastUpdated,
    this.source = 'PPAC / Official OMC Daily RSP',
    this.status = 'live',
    this.confidence = 'high',
    this.allPrices = const {},
  });

  factory FuelPrice.fromJson(Map<String, dynamic> json) {
    final pricesMap = <String, double>{};
    if (json['allPrices'] is Map) {
      (json['allPrices'] as Map).forEach((k, v) {
        if (v is num) pricesMap[k.toString()] = v.toDouble();
      });
    }

    return FuelPrice(
      country: json['country'] as String? ?? 'India',
      countryCode: json['countryCode'] as String? ?? 'IN',
      state: json['state'] as String? ?? 'Karnataka',
      city: json['city'] as String? ?? 'Bengaluru',
      fuelType: json['fuelType'] as String? ?? 'petrol',
      price: (json['price'] as num?)?.toDouble() ?? 102.86,
      currency: json['currency'] as String? ?? 'INR',
      currencySymbol: json['currencySymbol'] as String? ?? '₹',
      unit: json['unit'] as String? ?? 'litre',
      effectiveAt: json['effectiveAt'] as String? ?? DateTime.now().toIso8601String(),
      lastUpdated: json['lastUpdated'] as String? ?? DateTime.now().toIso8601String(),
      source: json['source'] as String? ?? 'Official OMC Daily RSP',
      status: json['status'] as String? ?? 'live',
      confidence: json['confidence'] as String? ?? 'high',
      allPrices: pricesMap,
    );
  }

  Map<String, dynamic> toJson() => {
        'country': country,
        'countryCode': countryCode,
        'state': state,
        'city': city,
        'fuelType': fuelType,
        'price': price,
        'currency': currency,
        'currencySymbol': currencySymbol,
        'unit': unit,
        'effectiveAt': effectiveAt,
        'lastUpdated': lastUpdated,
        'source': source,
        'status': status,
        'confidence': confidence,
        'allPrices': allPrices,
      };

  bool get isRealTime => status == 'live';
  String get provider => source;
}

class FuelEstimate {
  final double distanceKm;
  final double vehicleEfficiency;
  final String fuelType;
  final double fuelRequired;
  final double pricePerUnit;
  final String currency;
  final String currencySymbol;
  final String unit;
  final double totalCost;
  final String startRegion;
  final String endRegion;
  final bool isMultiState;
  final bool isDefaultMileage;
  final String source;
  final String effectiveAt;
  final String lastUpdated;
  final String status;

  const FuelEstimate({
    required this.distanceKm,
    required this.vehicleEfficiency,
    required this.fuelType,
    required this.fuelRequired,
    required this.pricePerUnit,
    this.currency = 'INR',
    this.currencySymbol = '₹',
    this.unit = 'litre',
    required this.totalCost,
    this.startRegion = '',
    this.endRegion = '',
    this.isMultiState = false,
    this.isDefaultMileage = false,
    this.source = 'PPAC / Official OMC Daily RSP',
    required this.effectiveAt,
    required this.lastUpdated,
    this.status = 'live',
  });

  double get totalFuelCost => totalCost;
  double get fuelRequiredLiters => fuelRequired;
  double get appliedPricePerLiter => pricePerUnit;
  String get regionName => startRegion.isNotEmpty
      ? (endRegion.isNotEmpty && isMultiState ? '$startRegion ➔ $endRegion' : startRegion)
      : 'India';
  bool get isMultiRegionEstimate => isMultiState;
  String get dataSource => source;

  factory FuelEstimate.fromJson(Map<String, dynamic> json) => FuelEstimate(
        distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0.0,
        vehicleEfficiency: (json['vehicleEfficiency'] as num?)?.toDouble() ?? 15.0,
        fuelType: json['fuelType'] as String? ?? 'petrol',
        fuelRequired: (json['fuelRequired'] as num?)?.toDouble() ?? 0.0,
        pricePerUnit: (json['pricePerUnit'] as num?)?.toDouble() ?? 102.86,
        currency: json['currency'] as String? ?? 'INR',
        currencySymbol: json['currencySymbol'] as String? ?? '₹',
        unit: json['unit'] as String? ?? 'litre',
        totalCost: (json['totalCost'] as num?)?.toDouble() ?? 0.0,
        startRegion: json['startRegion'] as String? ?? '',
        endRegion: json['endRegion'] as String? ?? '',
        isMultiState: json['isMultiState'] as bool? ?? false,
        isDefaultMileage: json['isDefaultMileage'] as bool? ?? false,
        source: json['source'] as String? ?? 'Official OMC Daily RSP',
        effectiveAt: json['effectiveAt'] as String? ?? DateTime.now().toIso8601String(),
        lastUpdated: json['lastUpdated'] as String? ?? DateTime.now().toIso8601String(),
        status: json['status'] as String? ?? 'live',
      );

  Map<String, dynamic> toJson() => {
        'distanceKm': distanceKm,
        'vehicleEfficiency': vehicleEfficiency,
        'fuelType': fuelType,
        'fuelRequired': fuelRequired,
        'pricePerUnit': pricePerUnit,
        'currency': currency,
        'currencySymbol': currencySymbol,
        'unit': unit,
        'totalCost': totalCost,
        'startRegion': startRegion,
        'endRegion': endRegion,
        'isMultiState': isMultiState,
        'isDefaultMileage': isDefaultMileage,
        'source': source,
        'effectiveAt': effectiveAt,
        'lastUpdated': lastUpdated,
        'status': status,
      };
}

class TollPlaza {
  final String id;
  final String name;
  final String highway;
  final double latitude;
  final double longitude;
  final double amount;
  final double cashAmount;
  final String vehicleClass;
  final String direction;
  final double distanceAlongRouteKm;
  final int routeIndex;
  final bool isEstimated;
  final String dataSource;

  const TollPlaza({
    required this.id,
    required this.name,
    required this.highway,
    required this.latitude,
    required this.longitude,
    required this.amount,
    required this.cashAmount,
    required this.vehicleClass,
    this.direction = 'single',
    required this.distanceAlongRouteKm,
    this.routeIndex = 0,
    this.isEstimated = false,
    this.dataSource = 'NHAI Toll Information System (TIS)',
  });

  factory TollPlaza.fromJson(Map<String, dynamic> json) => TollPlaza(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Toll Plaza',
        highway: json['highway'] as String? ?? 'Highway',
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
        amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
        cashAmount: (json['cashAmount'] as num?)?.toDouble() ??
            ((json['amount'] as num?)?.toDouble() ?? 0.0) * 2,
        vehicleClass: json['vehicleClass'] as String? ?? 'car',
        direction: json['direction'] as String? ?? 'single',
        distanceAlongRouteKm:
            (json['distanceAlongRouteKm'] as num?)?.toDouble() ?? 0.0,
        routeIndex: json['routeIndex'] as int? ?? 0,
        isEstimated: json['isEstimated'] as bool? ?? false,
        dataSource: json['dataSource'] as String? ?? 'NHAI TIS',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'highway': highway,
        'latitude': latitude,
        'longitude': longitude,
        'amount': amount,
        'cashAmount': cashAmount,
        'vehicleClass': vehicleClass,
        'direction': direction,
        'distanceAlongRouteKm': distanceAlongRouteKm,
        'routeIndex': routeIndex,
        'isEstimated': isEstimated,
        'dataSource': dataSource,
      };
}

class TollEstimate {
  final bool hasTolls;
  final String currency;
  final double? minTollCost;
  final double? maxTollCost;
  final double? fastagTollCost;
  final double? cashTollCost;
  final double? fuelCost;
  final double? totalAmount;
  final int tollCount;
  final List<TollPlaza> tolls;
  final String? vehicleClass;
  final bool isEstimated;
  final String? dataSource;
  final String? lastUpdated;

  const TollEstimate({
    required this.hasTolls,
    required this.currency,
    this.minTollCost,
    this.maxTollCost,
    this.fastagTollCost,
    this.cashTollCost,
    this.fuelCost,
    this.totalAmount,
    this.tollCount = 0,
    this.tolls = const [],
    this.vehicleClass,
    this.isEstimated = false,
    this.dataSource,
    this.lastUpdated,
  });

  factory TollEstimate.fromJson(Map<String, dynamic> json) {
    final rawTolls = json['tolls'] as List<dynamic>? ?? [];
    final tollsList = rawTolls
        .map((e) => TollPlaza.fromJson(e as Map<String, dynamic>))
        .toList();
    final count = json['tollCount'] as int? ?? tollsList.length;
    final total = (json['totalAmount'] as num?)?.toDouble() ??
        (json['fastagTollCost'] as num?)?.toDouble() ??
        (tollsList.isNotEmpty
            ? tollsList.fold<double>(0.0, (sum, t) => sum + t.amount)
            : null);

    return TollEstimate(
      hasTolls: json['hasTolls'] as bool? ?? (count > 0 || (total != null && total > 0)),
      currency: json['currency'] as String? ?? 'INR',
      minTollCost: (json['minTollCost'] as num?)?.toDouble() ?? total,
      maxTollCost: (json['maxTollCost'] as num?)?.toDouble() ??
          (json['cashTollCost'] as num?)?.toDouble(),
      fastagTollCost: (json['fastagTollCost'] as num?)?.toDouble() ?? total,
      cashTollCost: (json['cashTollCost'] as num?)?.toDouble() ??
          (total != null ? total * 2 : null),
      fuelCost: (json['fuelCost'] as num?)?.toDouble(),
      totalAmount: total,
      tollCount: count,
      tolls: tollsList,
      vehicleClass: json['vehicleClass'] as String?,
      isEstimated: json['isEstimated'] as bool? ?? false,
      dataSource: json['dataSource'] as String?,
      lastUpdated: json['lastUpdated'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'hasTolls': hasTolls,
        'currency': currency,
        'minTollCost': minTollCost,
        'maxTollCost': maxTollCost,
        'fastagTollCost': fastagTollCost,
        'cashTollCost': cashTollCost,
        'fuelCost': fuelCost,
        'totalAmount': totalAmount,
        'tollCount': tollCount,
        'tolls': tolls.map((t) => t.toJson()).toList(),
        'vehicleClass': vehicleClass,
        'isEstimated': isEstimated,
        'dataSource': dataSource,
        'lastUpdated': lastUpdated,
      };
}

class PlaceOfInterest {
  final int id;
  final String name;
  final double lat;
  final double lng;
  final String? address;
  final double? rating;
  final int? reviewsCount;
  final String? deity;
  final String? timing;
  final String? highlights;
  final String? categoryType;

  const PlaceOfInterest({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.address,
    this.rating,
    this.reviewsCount,
    this.deity,
    this.timing,
    this.highlights,
    this.categoryType,
  });

  factory PlaceOfInterest.fromJson(Map<String, dynamic> json) => PlaceOfInterest(
        id: json['id'] as int,
        name: json['name'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        address: json['address'] as String?,
        rating: (json['rating'] as num?)?.toDouble(),
        reviewsCount: json['reviewsCount'] as int?,
        deity: json['deity'] as String?,
        timing: json['timing'] as String?,
        highlights: json['highlights'] as String?,
        categoryType: json['categoryType'] as String?,
      );

  LatLng toLatLng() => LatLng(lat, lng);
}

class WeatherPoint {
  final double lat;
  final double lng;
  final double distanceFromStartKm;
  final double? tempC;
  final String description;
  final String icon; // clear | partly_cloudy | cloudy | fog | drizzle | rain | snow | thunderstorm
  final int? windKph;
  final int? humidity;
  final int? rainChancePct;

  const WeatherPoint({
    required this.lat,
    required this.lng,
    required this.distanceFromStartKm,
    required this.tempC,
    required this.description,
    required this.icon,
    required this.windKph,
    required this.humidity,
    required this.rainChancePct,
  });

  factory WeatherPoint.fromJson(Map<String, dynamic> json) => WeatherPoint(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        distanceFromStartKm: (json['distanceFromStartKm'] as num?)?.toDouble() ?? 0,
        tempC: (json['tempC'] as num?)?.toDouble(),
        description: json['description'] as String? ?? 'Unknown',
        icon: json['icon'] as String? ?? 'cloudy',
        windKph: (json['windKph'] as num?)?.toInt(),
        humidity: (json['humidity'] as num?)?.toInt(),
        rainChancePct: (json['rainChancePct'] as num?)?.toInt(),
      );

  LatLng toLatLng() => LatLng(lat, lng);
}

class RouteWeather {
  final bool hasAlerts;
  final List<WeatherPoint> points;

  const RouteWeather({required this.hasAlerts, required this.points});

  factory RouteWeather.fromJson(Map<String, dynamic> json) => RouteWeather(
        hasAlerts: json['hasAlerts'] as bool? ?? false,
        points: (json['points'] as List? ?? [])
            .map((e) => WeatherPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class TripBudget {
  final String currency;
  final int days;
  final int nights;
  final int travellers;
  final bool international;
  final int fuel;
  final int tolls;
  final int transport; // flight/train/bus/ferry tickets
  final int localTransport; // destination taxis / local getting-around
  final int food;
  final int stay;
  final int buffer;
  final int total;
  final int perDay;

  const TripBudget({
    required this.currency,
    required this.days,
    required this.nights,
    required this.travellers,
    this.international = false,
    required this.fuel,
    required this.tolls,
    this.transport = 0,
    this.localTransport = 0,
    required this.food,
    required this.stay,
    required this.buffer,
    required this.total,
    required this.perDay,
  });

  factory TripBudget.fromJson(Map<String, dynamic> json) {
    final b = (json['breakdown'] as Map<String, dynamic>? ?? {});
    return TripBudget(
      currency: json['currency'] as String? ?? 'INR',
      days: (json['days'] as num?)?.toInt() ?? 1,
      nights: (json['nights'] as num?)?.toInt() ?? 0,
      travellers: (json['travellers'] as num?)?.toInt() ?? 1,
      international: json['international'] as bool? ?? false,
      fuel: (b['fuel'] as num?)?.toInt() ?? 0,
      tolls: (b['tolls'] as num?)?.toInt() ?? 0,
      transport: (b['transport'] as num?)?.toInt() ?? 0,
      localTransport: (b['localTransport'] as num?)?.toInt() ?? 0,
      food: (b['food'] as num?)?.toInt() ?? 0,
      stay: (b['stay'] as num?)?.toInt() ?? 0,
      buffer: (b['buffer'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      perDay: (json['perDay'] as num?)?.toInt() ?? 0,
    );
  }
}

class DepartureAdvice {
  final int bestOffsetHours;
  final String bestLabel;
  final int driestRainPct;
  final int nowRainPct;
  final String recommendation;

  const DepartureAdvice({
    required this.bestOffsetHours,
    required this.bestLabel,
    required this.driestRainPct,
    required this.nowRainPct,
    required this.recommendation,
  });

  factory DepartureAdvice.fromJson(Map<String, dynamic> json) => DepartureAdvice(
        bestOffsetHours: (json['bestOffsetHours'] as num?)?.toInt() ?? 0,
        bestLabel: json['bestLabel'] as String? ?? 'now',
        driestRainPct: (json['driestRainPct'] as num?)?.toInt() ?? 0,
        nowRainPct: (json['nowRainPct'] as num?)?.toInt() ?? 0,
        recommendation: json['recommendation'] as String? ?? '',
      );

  /// True when leaving later meaningfully reduces rain risk.
  bool get suggestsWaiting => bestOffsetHours > 0 && driestRainPct < nowRainPct - 15;
}

class RestBreak {
  final double afterHours;
  final double distanceFromStartKm;
  final double lat;
  final double lng;
  final String label;

  const RestBreak({
    required this.afterHours,
    required this.distanceFromStartKm,
    required this.lat,
    required this.lng,
    required this.label,
  });

  factory RestBreak.fromJson(Map<String, dynamic> json) => RestBreak(
        afterHours: (json['afterHours'] as num?)?.toDouble() ?? 0,
        distanceFromStartKm: (json['distanceFromStartKm'] as num?)?.toDouble() ?? 0,
        lat: (json['lat'] as num?)?.toDouble() ?? 0,
        lng: (json['lng'] as num?)?.toDouble() ?? 0,
        label: json['label'] as String? ?? 'Rest break',
      );

  LatLng toLatLng() => LatLng(lat, lng);
}

class DayPlan {
  final int day;
  final double fromKm;
  final double toKm;
  final double distanceKm;
  final double driveHours;
  final double endLat;
  final double endLng;
  final bool isFinal;

  const DayPlan({
    required this.day,
    required this.fromKm,
    required this.toKm,
    required this.distanceKm,
    required this.driveHours,
    required this.endLat,
    required this.endLng,
    required this.isFinal,
  });

  factory DayPlan.fromJson(Map<String, dynamic> json) => DayPlan(
        day: (json['day'] as num?)?.toInt() ?? 1,
        fromKm: (json['fromKm'] as num?)?.toDouble() ?? 0,
        toKm: (json['toKm'] as num?)?.toDouble() ?? 0,
        distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
        driveHours: (json['driveHours'] as num?)?.toDouble() ?? 0,
        endLat: (json['endLat'] as num?)?.toDouble() ?? 0,
        endLng: (json['endLng'] as num?)?.toDouble() ?? 0,
        isFinal: json['isFinal'] as bool? ?? false,
      );
}

class WikiAttraction {
  final int pageid;
  final String title;
  final double lat;
  final double lng;
  final int distanceMeters;
  final String summary;
  final String? thumbnailUrl;
  final String pageUrl;

  const WikiAttraction({
    required this.pageid,
    required this.title,
    required this.lat,
    required this.lng,
    required this.distanceMeters,
    required this.summary,
    this.thumbnailUrl,
    required this.pageUrl,
  });

  factory WikiAttraction.fromJson(Map<String, dynamic> json) => WikiAttraction(
        pageid: (json['pageid'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? 'Attraction',
        lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
        lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
        distanceMeters: (json['distanceMeters'] as num?)?.toInt() ?? 0,
        summary: json['summary'] as String? ?? '',
        thumbnailUrl: json['thumbnailUrl'] as String?,
        pageUrl: json['pageUrl'] as String? ?? '',
      );
}

class DestinationEvent {
  final String id;
  final String title;
  final String category;
  final String location;
  final String date;
  final String description;
  final String? url;

  const DestinationEvent({
    required this.id,
    required this.title,
    required this.category,
    required this.location,
    required this.date,
    required this.description,
    this.url,
  });

  factory DestinationEvent.fromJson(Map<String, dynamic> json) => DestinationEvent(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? 'Local Event',
        category: json['category'] as String? ?? 'General',
        location: json['location'] as String? ?? '',
        date: json['date'] as String? ?? 'Upcoming',
        description: json['description'] as String? ?? '',
        url: json['url'] as String?,
      );
}

class TripPlan {
  final double distanceKm;
  final int durationMin;
  final List<GeoPoint> coordinates;

  /// True when expressways/motorways were excluded from this route because the
  /// vehicle (2-/3-wheeler) is legally barred from them.
  final bool avoidedMotorways;
  final int estimatedDays;
  final FuelPlan fuel;
  final FuelEstimate? fuelEstimate;
  final TollEstimate? toll;
  final RouteWeather? weather;
  final DepartureAdvice? departureAdvice;
  final List<RestBreak> restStops;
  final List<DayPlan> itinerary;
  final TripBudget? budget;
  final Map<String, List<PlaceOfInterest>> places;
  final List<WikiAttraction> wikiAttractions;
  final List<DestinationEvent> events;

  const TripPlan({
    required this.distanceKm,
    required this.durationMin,
    required this.coordinates,
    this.avoidedMotorways = false,
    required this.estimatedDays,
    required this.fuel,
    this.fuelEstimate,
    required this.toll,
    required this.weather,
    required this.departureAdvice,
    required this.restStops,
    required this.itinerary,
    required this.budget,
    required this.places,
    this.wikiAttractions = const [],
    this.events = const [],
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
      avoidedMotorways: (route['avoidedMotorways'] as bool?) ?? false,
      estimatedDays: json['estimatedDays'] as int,
      fuel: FuelPlan.fromJson(json['fuel'] as Map<String, dynamic>),
      fuelEstimate: json['fuelEstimate'] != null
          ? FuelEstimate.fromJson(json['fuelEstimate'] as Map<String, dynamic>)
          : null,
      toll: json['toll'] != null ? TollEstimate.fromJson(json['toll'] as Map<String, dynamic>) : null,
      weather: json['weather'] != null ? RouteWeather.fromJson(json['weather'] as Map<String, dynamic>) : null,
      departureAdvice: json['departureAdvice'] != null
          ? DepartureAdvice.fromJson(json['departureAdvice'] as Map<String, dynamic>)
          : null,
      restStops: (json['restStops'] as List? ?? [])
          .map((e) => RestBreak.fromJson(e as Map<String, dynamic>))
          .toList(),
      itinerary: (json['itinerary'] as List? ?? [])
          .map((e) => DayPlan.fromJson(e as Map<String, dynamic>))
          .toList(),
      budget: json['budget'] != null ? TripBudget.fromJson(json['budget'] as Map<String, dynamic>) : null,
      places: placesJson.map(
        (key, value) => MapEntry(
          key,
          (value as List).map((e) => PlaceOfInterest.fromJson(e as Map<String, dynamic>)).toList(),
        ),
      ),
      wikiAttractions: (json['wikiAttractions'] as List? ?? [])
          .map((e) => WikiAttraction.fromJson(e as Map<String, dynamic>))
          .toList(),
      events: (json['events'] as List? ?? [])
          .map((e) => DestinationEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  TripPlan copyWith({
    double? distanceKm,
    int? durationMin,
    List<GeoPoint>? coordinates,
    bool? avoidedMotorways,
    int? estimatedDays,
    FuelPlan? fuel,
    FuelEstimate? fuelEstimate,
    TollEstimate? toll,
    RouteWeather? weather,
    DepartureAdvice? departureAdvice,
    List<RestBreak>? restStops,
    List<DayPlan>? itinerary,
    TripBudget? budget,
    Map<String, List<PlaceOfInterest>>? places,
    List<WikiAttraction>? wikiAttractions,
    List<DestinationEvent>? events,
  }) {
    return TripPlan(
      distanceKm: distanceKm ?? this.distanceKm,
      durationMin: durationMin ?? this.durationMin,
      coordinates: coordinates ?? this.coordinates,
      avoidedMotorways: avoidedMotorways ?? this.avoidedMotorways,
      estimatedDays: estimatedDays ?? this.estimatedDays,
      fuel: fuel ?? this.fuel,
      fuelEstimate: fuelEstimate ?? this.fuelEstimate,
      toll: toll ?? this.toll,
      weather: weather ?? this.weather,
      departureAdvice: departureAdvice ?? this.departureAdvice,
      restStops: restStops ?? this.restStops,
      itinerary: itinerary ?? this.itinerary,
      budget: budget ?? this.budget,
      places: places ?? this.places,
      wikiAttractions: wikiAttractions ?? this.wikiAttractions,
      events: events ?? this.events,
    );
  }
}
