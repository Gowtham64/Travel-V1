import 'dart:convert';
import 'trip_models.dart';

/// Supported expense categories matching VoyPlan trip budgeting & itinerary breaks
enum ExpenseCategory {
  food,
  breakfast,
  tea,
  coffee,
  snacks,
  lunch,
  dinner,
  fuel,
  toll,
  parking,
  accommodation,
  ticket,
  other;

  String get key => name;

  String get displayName {
    switch (this) {
      case ExpenseCategory.food:
        return 'Food & Dining';
      case ExpenseCategory.breakfast:
        return 'Breakfast';
      case ExpenseCategory.tea:
        return 'Tea';
      case ExpenseCategory.coffee:
        return 'Coffee';
      case ExpenseCategory.snacks:
        return 'Snacks';
      case ExpenseCategory.lunch:
        return 'Lunch';
      case ExpenseCategory.dinner:
        return 'Dinner';
      case ExpenseCategory.fuel:
        return 'Fuel';
      case ExpenseCategory.toll:
        return 'Toll';
      case ExpenseCategory.parking:
        return 'Parking';
      case ExpenseCategory.accommodation:
        return 'Accommodation';
      case ExpenseCategory.ticket:
        return 'Entry Ticket';
      case ExpenseCategory.other:
        return 'Other';
    }
  }

  static ExpenseCategory fromString(String? val) {
    if (val == null) return ExpenseCategory.other;
    final lower = val.toLowerCase().trim();
    for (final cat in ExpenseCategory.values) {
      if (cat.name == lower) return cat;
    }
    if (lower.contains('breakfast')) return ExpenseCategory.breakfast;
    if (lower.contains('lunch')) return ExpenseCategory.lunch;
    if (lower.contains('dinner')) return ExpenseCategory.dinner;
    if (lower.contains('tea')) return ExpenseCategory.tea;
    if (lower.contains('coffee')) return ExpenseCategory.coffee;
    if (lower.contains('snack')) return ExpenseCategory.snacks;
    if (lower.contains('fuel') || lower.contains('petrol') || lower.contains('diesel')) return ExpenseCategory.fuel;
    if (lower.contains('toll')) return ExpenseCategory.toll;
    if (lower.contains('park')) return ExpenseCategory.parking;
    if (lower.contains('hotel') || lower.contains('stay') || lower.contains('lodge')) return ExpenseCategory.accommodation;
    if (lower.contains('ticket') || lower.contains('entry') || lower.contains('monument')) return ExpenseCategory.ticket;
    return ExpenseCategory.other;
  }
}

/// A granular expense item tracking both Estimated and Actual costs.
class TripExpenseItem {
  final String id;
  final String tripId;
  final ExpenseCategory category;
  final String description;
  final double estimatedAmount;
  final double actualAmount;
  final String currency;
  final String currencySymbol;
  final String location;
  final DateTime dateTime;
  final String notes;
  final String? receiptNumber;
  final String paymentMethod; // Cash | FASTag | UPI | Card | Other
  final String? stopId;
  final String? stopName;

  // Fuel-specific details
  final String? stationName;
  final String? fuelType;
  final double? litres;
  final double? pricePerLitre;

  // Toll-specific details
  final String? tollPlazaId;
  final String? tollPlazaName;

  // Trip leg / direction: 'outbound' | 'return' | 'single'
  final String routeLeg;

  TripExpenseItem({
    required this.id,
    this.tripId = '',
    required this.category,
    required this.description,
    this.estimatedAmount = 0.0,
    this.actualAmount = 0.0,
    this.currency = 'INR',
    this.currencySymbol = '₹',
    this.location = '',
    DateTime? dateTime,
    this.notes = '',
    this.receiptNumber,
    this.paymentMethod = 'Cash',
    this.stopId,
    this.stopName,
    this.stationName,
    this.fuelType,
    this.litres,
    this.pricePerLitre,
    this.tollPlazaId,
    this.tollPlazaName,
    this.routeLeg = 'single',
  }) : dateTime = dateTime ?? DateTime.now();

  double get difference => actualAmount - estimatedAmount;
  bool get hasActual => actualAmount > 0;

  Map<String, dynamic> toJson() => {
    'id': id,
    'tripId': tripId,
    'category': category.name,
    'description': description,
    'estimatedAmount': estimatedAmount,
    'actualAmount': actualAmount,
    'currency': currency,
    'currencySymbol': currencySymbol,
    'location': location,
    'dateTime': dateTime.toIso8601String(),
    'notes': notes,
    'receiptNumber': receiptNumber,
    'paymentMethod': paymentMethod,
    'stopId': stopId,
    'stopName': stopName,
    'stationName': stationName,
    'fuelType': fuelType,
    'litres': litres,
    'pricePerLitre': pricePerLitre,
    'tollPlazaId': tollPlazaId,
    'tollPlazaName': tollPlazaName,
    'routeLeg': routeLeg,
  };

  factory TripExpenseItem.fromJson(Map<String, dynamic> json) => TripExpenseItem(
    id: json['id']?.toString() ?? '',
    tripId: json['tripId']?.toString() ?? '',
    category: ExpenseCategory.fromString(json['category']?.toString()),
    description: json['description']?.toString() ?? '',
    estimatedAmount: (json['estimatedAmount'] as num?)?.toDouble() ?? 0.0,
    actualAmount: (json['actualAmount'] as num?)?.toDouble() ?? 0.0,
    currency: json['currency']?.toString() ?? 'INR',
    currencySymbol: json['currencySymbol']?.toString() ?? '₹',
    location: json['location']?.toString() ?? '',
    dateTime: DateTime.tryParse(json['dateTime']?.toString() ?? '') ?? DateTime.now(),
    notes: json['notes']?.toString() ?? '',
    receiptNumber: json['receiptNumber']?.toString(),
    paymentMethod: json['paymentMethod']?.toString() ?? 'Cash',
    stopId: json['stopId']?.toString(),
    stopName: json['stopName']?.toString(),
    stationName: json['stationName']?.toString(),
    fuelType: json['fuelType']?.toString(),
    litres: (json['litres'] as num?)?.toDouble(),
    pricePerLitre: (json['pricePerLitre'] as num?)?.toDouble(),
    tollPlazaId: json['tollPlazaId']?.toString(),
    tollPlazaName: json['tollPlazaName']?.toString(),
    routeLeg: json['routeLeg']?.toString() ?? 'single',
  );

  TripExpenseItem copyWith({
    String? id,
    String? tripId,
    ExpenseCategory? category,
    String? description,
    double? estimatedAmount,
    double? actualAmount,
    String? currency,
    String? currencySymbol,
    String? location,
    DateTime? dateTime,
    String? notes,
    String? receiptNumber,
    String? paymentMethod,
    String? stopId,
    String? stopName,
    String? stationName,
    String? fuelType,
    double? litres,
    double? pricePerLitre,
    String? tollPlazaId,
    String? tollPlazaName,
    String? routeLeg,
  }) {
    return TripExpenseItem(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      category: category ?? this.category,
      description: description ?? this.description,
      estimatedAmount: estimatedAmount ?? this.estimatedAmount,
      actualAmount: actualAmount ?? this.actualAmount,
      currency: currency ?? this.currency,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      location: location ?? this.location,
      dateTime: dateTime ?? this.dateTime,
      notes: notes ?? this.notes,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      stopId: stopId ?? this.stopId,
      stopName: stopName ?? this.stopName,
      stationName: stationName ?? this.stationName,
      fuelType: fuelType ?? this.fuelType,
      litres: litres ?? this.litres,
      pricePerLitre: pricePerLitre ?? this.pricePerLitre,
      tollPlazaId: tollPlazaId ?? this.tollPlazaId,
      tollPlazaName: tollPlazaName ?? this.tollPlazaName,
      routeLeg: routeLeg ?? this.routeLeg,
    );
  }
}

/// Category comparison record
class CategoryExpenseSummary {
  final String categoryName;
  final double estimated;
  final double actual;
  final String currencySymbol;

  const CategoryExpenseSummary({
    required this.categoryName,
    required this.estimated,
    required this.actual,
    this.currencySymbol = '₹',
  });

  double get difference => actual - estimated;
  bool get isOverBudget => actual > estimated;
  double get savings => (estimated - actual).clamp(0, double.infinity);
}

/// Comprehensive Final Trip Expense Report
class TripExpenseReport {
  final String tripId;
  final String tripTitle;
  final String startAddress;
  final String endAddress;
  final double distanceKm;
  final int durationMinutes;
  final String currency;
  final String currencySymbol;
  final bool isRoundTrip;
  final DateTime completedAt;
  final bool routedThroughAllStops;
  final List<String> confirmedStops;

  // Fuel metrics
  final double fuelRequiredLiters;
  final double actualFuelPurchasedLiters;
  final double fuelPricePerLiter;
  final double estimatedFuelCost;
  final double actualFuelCost;
  final List<TripExpenseItem> fuelEntries;

  // Toll metrics
  final double estimatedTollTotal;
  final double actualTollTotal;
  final List<TripExpenseItem> tollEntries;

  // Meals & Breaks metrics
  final double estimatedBreakfast;
  final double actualBreakfast;
  final double estimatedLunch;
  final double actualLunch;
  final double estimatedTeaSnacks;
  final double actualTeaSnacks;
  final double estimatedDinner;
  final double actualDinner;
  final List<TripExpenseItem> mealEntries;

  // Other expenses metrics
  final double estimatedParking;
  final double actualParking;
  final double estimatedTickets;
  final double actualTickets;
  final double estimatedOther;
  final double actualOther;
  final List<TripExpenseItem> otherEntries;

  // Outbound vs Return metrics (for Round Trips)
  final double outboundEstimatedTotal;
  final double outboundActualTotal;
  final double returnEstimatedTotal;
  final double returnActualTotal;

  // Grand Totals
  final double totalEstimated;
  final double totalActual;

  const TripExpenseReport({
    required this.tripId,
    required this.tripTitle,
    required this.startAddress,
    required this.endAddress,
    required this.distanceKm,
    required this.durationMinutes,
    this.currency = 'INR',
    this.currencySymbol = '₹',
    this.isRoundTrip = false,
    required this.completedAt,
    this.routedThroughAllStops = true,
    this.confirmedStops = const [],
    required this.fuelRequiredLiters,
    required this.actualFuelPurchasedLiters,
    required this.fuelPricePerLiter,
    required this.estimatedFuelCost,
    required this.actualFuelCost,
    this.fuelEntries = const [],
    required this.estimatedTollTotal,
    required this.actualTollTotal,
    this.tollEntries = const [],
    required this.estimatedBreakfast,
    required this.actualBreakfast,
    required this.estimatedLunch,
    required this.actualLunch,
    required this.estimatedTeaSnacks,
    required this.actualTeaSnacks,
    required this.estimatedDinner,
    required this.actualDinner,
    this.mealEntries = const [],
    required this.estimatedParking,
    required this.actualParking,
    required this.estimatedTickets,
    required this.actualTickets,
    required this.estimatedOther,
    required this.actualOther,
    this.otherEntries = const [],
    this.outboundEstimatedTotal = 0.0,
    this.outboundActualTotal = 0.0,
    this.returnEstimatedTotal = 0.0,
    this.returnActualTotal = 0.0,
    required this.totalEstimated,
    required this.totalActual,
  });

  double get difference => totalActual - totalEstimated;
  bool get isOverBudget => totalActual > totalEstimated;
  double get totalSavings => (totalEstimated - totalActual).clamp(0, double.infinity);
  double get totalFoodEstimated => estimatedBreakfast + estimatedLunch + estimatedTeaSnacks + estimatedDinner;
  double get totalFoodActual => actualBreakfast + actualLunch + actualTeaSnacks + actualDinner;
  double get totalOtherEstimated => estimatedParking + estimatedTickets + estimatedOther;
  double get totalOtherActual => actualParking + actualTickets + actualOther;

  Map<String, dynamic> toJson() => {
    'tripId': tripId,
    'tripTitle': tripTitle,
    'startAddress': startAddress,
    'endAddress': endAddress,
    'distanceKm': distanceKm,
    'durationMinutes': durationMinutes,
    'currency': currency,
    'currencySymbol': currencySymbol,
    'isRoundTrip': isRoundTrip,
    'completedAt': completedAt.toIso8601String(),
    'routedThroughAllStops': routedThroughAllStops,
    'confirmedStops': confirmedStops,
    'fuelRequiredLiters': fuelRequiredLiters,
    'actualFuelPurchasedLiters': actualFuelPurchasedLiters,
    'fuelPricePerLiter': fuelPricePerLiter,
    'estimatedFuelCost': estimatedFuelCost,
    'actualFuelCost': actualFuelCost,
    'fuelEntries': fuelEntries.map((e) => e.toJson()).toList(),
    'estimatedTollTotal': estimatedTollTotal,
    'actualTollTotal': actualTollTotal,
    'tollEntries': tollEntries.map((e) => e.toJson()).toList(),
    'estimatedBreakfast': estimatedBreakfast,
    'actualBreakfast': actualBreakfast,
    'estimatedLunch': estimatedLunch,
    'actualLunch': actualLunch,
    'estimatedTeaSnacks': estimatedTeaSnacks,
    'actualTeaSnacks': actualTeaSnacks,
    'estimatedDinner': estimatedDinner,
    'actualDinner': actualDinner,
    'mealEntries': mealEntries.map((e) => e.toJson()).toList(),
    'estimatedParking': estimatedParking,
    'actualParking': actualParking,
    'estimatedTickets': estimatedTickets,
    'actualTickets': actualTickets,
    'estimatedOther': estimatedOther,
    'actualOther': actualOther,
    'otherEntries': otherEntries.map((e) => e.toJson()).toList(),
    'outboundEstimatedTotal': outboundEstimatedTotal,
    'outboundActualTotal': outboundActualTotal,
    'returnEstimatedTotal': returnEstimatedTotal,
    'returnActualTotal': returnActualTotal,
    'totalEstimated': totalEstimated,
    'totalActual': totalActual,
  };

  factory TripExpenseReport.fromJson(Map<String, dynamic> json) => TripExpenseReport(
    tripId: json['tripId']?.toString() ?? '',
    tripTitle: json['tripTitle']?.toString() ?? 'Trip Expense Report',
    startAddress: json['startAddress']?.toString() ?? '',
    endAddress: json['endAddress']?.toString() ?? '',
    distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0.0,
    durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
    currency: json['currency']?.toString() ?? 'INR',
    currencySymbol: json['currencySymbol']?.toString() ?? '₹',
    isRoundTrip: json['isRoundTrip'] as bool? ?? false,
    completedAt: DateTime.tryParse(json['completedAt']?.toString() ?? '') ?? DateTime.now(),
    routedThroughAllStops: json['routedThroughAllStops'] as bool? ?? true,
    confirmedStops: (json['confirmedStops'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    fuelRequiredLiters: (json['fuelRequiredLiters'] as num?)?.toDouble() ?? 0.0,
    actualFuelPurchasedLiters: (json['actualFuelPurchasedLiters'] as num?)?.toDouble() ?? 0.0,
    fuelPricePerLiter: (json['fuelPricePerLiter'] as num?)?.toDouble() ?? 0.0,
    estimatedFuelCost: (json['estimatedFuelCost'] as num?)?.toDouble() ?? 0.0,
    actualFuelCost: (json['actualFuelCost'] as num?)?.toDouble() ?? 0.0,
    fuelEntries: (json['fuelEntries'] as List?)
        ?.map((e) => TripExpenseItem.fromJson((e as Map).cast<String, dynamic>()))
        .toList() ?? const [],
    estimatedTollTotal: (json['estimatedTollTotal'] as num?)?.toDouble() ?? 0.0,
    actualTollTotal: (json['actualTollTotal'] as num?)?.toDouble() ?? 0.0,
    tollEntries: (json['tollEntries'] as List?)
        ?.map((e) => TripExpenseItem.fromJson((e as Map).cast<String, dynamic>()))
        .toList() ?? const [],
    estimatedBreakfast: (json['estimatedBreakfast'] as num?)?.toDouble() ?? 0.0,
    actualBreakfast: (json['actualBreakfast'] as num?)?.toDouble() ?? 0.0,
    estimatedLunch: (json['estimatedLunch'] as num?)?.toDouble() ?? 0.0,
    actualLunch: (json['actualLunch'] as num?)?.toDouble() ?? 0.0,
    estimatedTeaSnacks: (json['estimatedTeaSnacks'] as num?)?.toDouble() ?? 0.0,
    actualTeaSnacks: (json['actualTeaSnacks'] as num?)?.toDouble() ?? 0.0,
    estimatedDinner: (json['estimatedDinner'] as num?)?.toDouble() ?? 0.0,
    actualDinner: (json['actualDinner'] as num?)?.toDouble() ?? 0.0,
    mealEntries: (json['mealEntries'] as List?)
        ?.map((e) => TripExpenseItem.fromJson((e as Map).cast<String, dynamic>()))
        .toList() ?? const [],
    estimatedParking: (json['estimatedParking'] as num?)?.toDouble() ?? 0.0,
    actualParking: (json['actualParking'] as num?)?.toDouble() ?? 0.0,
    estimatedTickets: (json['estimatedTickets'] as num?)?.toDouble() ?? 0.0,
    actualTickets: (json['actualTickets'] as num?)?.toDouble() ?? 0.0,
    estimatedOther: (json['estimatedOther'] as num?)?.toDouble() ?? 0.0,
    actualOther: (json['actualOther'] as num?)?.toDouble() ?? 0.0,
    otherEntries: (json['otherEntries'] as List?)
        ?.map((e) => TripExpenseItem.fromJson((e as Map).cast<String, dynamic>()))
        .toList() ?? const [],
    outboundEstimatedTotal: (json['outboundEstimatedTotal'] as num?)?.toDouble() ?? 0.0,
    outboundActualTotal: (json['outboundActualTotal'] as num?)?.toDouble() ?? 0.0,
    returnEstimatedTotal: (json['returnEstimatedTotal'] as num?)?.toDouble() ?? 0.0,
    returnActualTotal: (json['returnActualTotal'] as num?)?.toDouble() ?? 0.0,
    totalEstimated: (json['totalEstimated'] as num?)?.toDouble() ?? 0.0,
    totalActual: (json['totalActual'] as num?)?.toDouble() ?? 0.0,
  );
}
