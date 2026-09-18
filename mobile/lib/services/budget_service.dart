import 'dart:math' as math;

/// Single authoritative budget model and calculation engine for VoyPlan.
class TripBudget {
  final double fuelCost;
  final double tolls;
  final double accommodation;
  final double food;
  final double activities;
  final double parking;
  final double miscellaneous;
  final int travelers;
  final int days;
  final double distanceKm;
  final double fuelPrice;
  final double mileageKmPerLiter;
  final bool isFuelEstimated;
  final bool isTollsEstimated;
  final bool isAccommodationEstimated;

  const TripBudget({
    required this.fuelCost,
    required this.tolls,
    required this.accommodation,
    required this.food,
    required this.activities,
    required this.parking,
    required this.miscellaneous,
    required this.travelers,
    required this.days,
    required this.distanceKm,
    this.fuelPrice = 102.5,
    this.mileageKmPerLiter = 15.0,
    this.isFuelEstimated = false,
    this.isTollsEstimated = false,
    this.isAccommodationEstimated = false,
  });

  /// Total sum of all expense categories
  double get total =>
      fuelCost +
      tolls +
      accommodation +
      food +
      activities +
      parking +
      miscellaneous;

  /// Cost per traveler
  double get perTraveler =>
      travelers > 0 ? (total / travelers).roundToDouble() : total;

  /// Transportation total (fuel + tolls + parking)
  double get transportationTotal => fuelCost + tolls + parking;

  Map<String, dynamic> toJson() => {
        'fuelCost': fuelCost,
        'tolls': tolls,
        'accommodation': accommodation,
        'food': food,
        'activities': activities,
        'parking': parking,
        'miscellaneous': miscellaneous,
        'total': total,
        'perTraveler': perTraveler,
        'travelers': travelers,
        'days': days,
        'distanceKm': distanceKm,
      };

  factory TripBudget.fromJson(Map<String, dynamic> json) {
    return TripBudget(
      fuelCost: (json['fuelCost'] as num?)?.toDouble() ?? 0.0,
      tolls: (json['tolls'] as num?)?.toDouble() ?? 0.0,
      accommodation: (json['accommodation'] as num?)?.toDouble() ?? 0.0,
      food: (json['food'] as num?)?.toDouble() ?? 0.0,
      activities: (json['activities'] as num?)?.toDouble() ?? 0.0,
      parking: (json['parking'] as num?)?.toDouble() ?? 0.0,
      miscellaneous: (json['miscellaneous'] as num?)?.toDouble() ?? 0.0,
      travelers: (json['travelers'] as num?)?.toInt() ?? 1,
      days: (json['days'] as num?)?.toInt() ?? 1,
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class BudgetService {
  BudgetService._();
  static final BudgetService instance = BudgetService._();

  /// Authoritative calculation formula for VoyPlan
  TripBudget calculate({
    required double distanceKm,
    required int travelers,
    int days = 1,
    double mileage = 15.0,
    double fuelPrice = 102.5,
    double? customTolls,
    double? customStayNightly,
    double? customDailyFood,
    double? customActivitiesTotal,
    double? customDailyParking,
    double? customMiscPerPerson,
  }) {
    final validTravelers = math.max(1, travelers);
    final validDays = math.max(1, days);
    final validMileage = mileage > 0 ? mileage : 15.0;

    // 1. Fuel required & cost
    final fuelRequiredLiters = distanceKm > 0 ? (distanceKm / validMileage) : 0.0;
    final calculatedFuel = (fuelRequiredLiters * fuelPrice).roundToDouble();

    // 2. Tolls: If not provided, estimate based on national highway average (~₹1.8/km on highways)
    final calculatedTolls = customTolls ??
        (distanceKm > 60 ? (distanceKm * 1.65).roundToDouble() : 0.0);

    // 3. Accommodation: (Days - 1) nights * nightly rate per room (1 room per 2 travelers)
    final nights = math.max(0, validDays - 1);
    final rooms = (validTravelers / 2.0).ceil();
    final nightlyRate = customStayNightly ?? 2800.0;
    final calculatedStay = (nights * rooms * nightlyRate).roundToDouble();

    // 4. Food: daily estimate * travelers * days (₹550/day standard road trip meal rate)
    final dailyFood = customDailyFood ?? 550.0;
    final calculatedFood = (dailyFood * validTravelers * validDays).roundToDouble();

    // 5. Activities: Sum of activity tickets or default ₹400/person/day for sightseeing
    final calculatedActivities = customActivitiesTotal ??
        (validDays > 1 ? (350.0 * validTravelers * validDays).roundToDouble() : 250.0 * validTravelers);

    // 6. Parking: ₹150/day per vehicle
    final dailyParking = customDailyParking ?? 150.0;
    final calculatedParking = (dailyParking * validDays).roundToDouble();

    // 7. Miscellaneous: Emergency & incidentals (₹150/person/day)
    final miscPerPerson = customMiscPerPerson ?? 150.0;
    final calculatedMisc = (miscPerPerson * validTravelers * validDays).roundToDouble();

    return TripBudget(
      fuelCost: calculatedFuel,
      tolls: calculatedTolls,
      accommodation: calculatedStay,
      food: calculatedFood,
      activities: calculatedActivities,
      parking: calculatedParking,
      miscellaneous: calculatedMisc,
      travelers: validTravelers,
      days: validDays,
      distanceKm: distanceKm,
      fuelPrice: fuelPrice,
      mileageKmPerLiter: validMileage,
      isFuelEstimated: distanceKm <= 0,
      isTollsEstimated: customTolls == null,
      isAccommodationEstimated: customStayNightly == null && nights > 0,
    );
  }
}
