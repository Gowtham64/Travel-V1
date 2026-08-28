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
      );
}

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

class TollEstimate {
  final bool hasTolls;
  final String currency;
  final double? minTollCost;
  final double? maxTollCost;
  final double? fastagTollCost;
  final double? cashTollCost;
  final double? fuelCost;

  const TollEstimate({
    required this.hasTolls,
    required this.currency,
    this.minTollCost,
    this.maxTollCost,
    this.fastagTollCost,
    this.cashTollCost,
    this.fuelCost,
  });

  factory TollEstimate.fromJson(Map<String, dynamic> json) => TollEstimate(
        hasTolls: json['hasTolls'] as bool? ?? false,
        currency: json['currency'] as String? ?? '',
        minTollCost: (json['minTollCost'] as num?)?.toDouble(),
        maxTollCost: (json['maxTollCost'] as num?)?.toDouble(),
        fastagTollCost: (json['fastagTollCost'] as num?)?.toDouble(),
        cashTollCost: (json['cashTollCost'] as num?)?.toDouble(),
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
  final int fuel;
  final int tolls;
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
    required this.fuel,
    required this.tolls,
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
      fuel: (b['fuel'] as num?)?.toInt() ?? 0,
      tolls: (b['tolls'] as num?)?.toInt() ?? 0,
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
}
