import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/trip_expense_models.dart';
import '../models/trip_models.dart';
import 'api_service.dart';

/// Centralized manager for active trip expense tracking, refuel records,
/// toll expenses, break expenses, offline persistence, and final trip expense report generation.
class TripExpenseService {
  TripExpenseService._();
  static final TripExpenseService instance = TripExpenseService._();

  final List<TripExpenseItem> _activeExpenses = [];
  String _currentTripId = '';
  TripPlan? _activePlan;
  Vehicle? _activeVehicle;
  String _startAddress = '';
  String _endAddress = '';
  bool _isRoundTrip = false;
  List<GeoPoint> _confirmedWaypoints = [];
  bool _isInitialized = false;

  List<TripExpenseItem> get expenses => List.unmodifiable(_activeExpenses);
  String get currentTripId => _currentTripId;
  bool get hasActiveTrip => _currentTripId.isNotEmpty;

  /// Initialize tracking for a trip
  Future<void> initTrip({
    required String tripId,
    required TripPlan plan,
    required Vehicle vehicle,
    required String startAddress,
    required String endAddress,
    bool isRoundTrip = false,
    List<GeoPoint> confirmedWaypoints = const [],
  }) async {
    _currentTripId = tripId;
    _activePlan = plan;
    _activeVehicle = vehicle;
    _startAddress = startAddress;
    _endAddress = endAddress;
    _isRoundTrip = isRoundTrip;
    _confirmedWaypoints = List.from(confirmedWaypoints);
    _activeExpenses.clear();

    // 1. Seed estimated fuel expense
    final fuelEst = plan.fuelEstimate;
    final currency = plan.budget?.currency ?? 'INR';
    final currencySymbol = fuelEst?.currencySymbol ?? '₹';

    if (fuelEst != null) {
      _activeExpenses.add(TripExpenseItem(
        id: 'est_fuel_$_currentTripId',
        tripId: _currentTripId,
        category: ExpenseCategory.fuel,
        description: 'Estimated Fuel (${fuelEst.formattedFuelRequired})',
        estimatedAmount: fuelEst.estimatedCost > 0 ? fuelEst.estimatedCost : fuelEst.totalCost,
        actualAmount: 0.0,
        currency: currency,
        currencySymbol: currencySymbol,
        fuelType: fuelEst.fuelType,
        litres: fuelEst.additionalFuelRequiredLiters > 0 ? fuelEst.additionalFuelRequiredLiters : fuelEst.fuelRequired,
        pricePerLitre: fuelEst.pricePerUnit,
        location: fuelEst.applicableLocation,
      ));
    }

    // 2. Seed estimated tolls from route
    final tolls = plan.toll?.tolls ?? [];
    for (int i = 0; i < tolls.length; i++) {
      final t = tolls[i];
      _activeExpenses.add(TripExpenseItem(
        id: 'est_toll_${t.id}_$_currentTripId',
        tripId: _currentTripId,
        category: ExpenseCategory.toll,
        description: t.name,
        estimatedAmount: t.amount,
        actualAmount: 0.0,
        currency: currency,
        currencySymbol: currencySymbol,
        tollPlazaId: t.id,
        tollPlazaName: t.name,
        location: '${t.highway} (${t.distanceAlongRouteKm.toStringAsFixed(1)} km)',
      ));
    }

    // 3. Seed estimated meals & breaks from budget
    final b = plan.budget;
    if (b != null) {
      if (b.breakfast > 0) {
        _activeExpenses.add(TripExpenseItem(
          id: 'est_breakfast_$_currentTripId',
          tripId: _currentTripId,
          category: ExpenseCategory.breakfast,
          description: 'Breakfast (${b.days} ${b.days > 1 ? "days" : "day"})',
          estimatedAmount: b.breakfast.toDouble(),
          actualAmount: 0.0,
          currency: currency,
          currencySymbol: currencySymbol,
        ));
      }
      if (b.lunch > 0) {
        _activeExpenses.add(TripExpenseItem(
          id: 'est_lunch_$_currentTripId',
          tripId: _currentTripId,
          category: ExpenseCategory.lunch,
          description: 'Lunch (${b.days} ${b.days > 1 ? "days" : "day"})',
          estimatedAmount: b.lunch.toDouble(),
          actualAmount: 0.0,
          currency: currency,
          currencySymbol: currencySymbol,
        ));
      }
      if (b.teaSnacks > 0) {
        _activeExpenses.add(TripExpenseItem(
          id: 'est_tea_$_currentTripId',
          tripId: _currentTripId,
          category: ExpenseCategory.tea,
          description: 'Tea & Snacks (${b.days} ${b.days > 1 ? "days" : "day"})',
          estimatedAmount: b.teaSnacks.toDouble(),
          actualAmount: 0.0,
          currency: currency,
          currencySymbol: currencySymbol,
        ));
      }
      if (b.dinner > 0) {
        _activeExpenses.add(TripExpenseItem(
          id: 'est_dinner_$_currentTripId',
          tripId: _currentTripId,
          category: ExpenseCategory.dinner,
          description: 'Dinner (${b.days} ${b.days > 1 ? "days" : "day"})',
          estimatedAmount: b.dinner.toDouble(),
          actualAmount: 0.0,
          currency: currency,
          currencySymbol: currencySymbol,
        ));
      }
      if (b.other > 0) {
        _activeExpenses.add(TripExpenseItem(
          id: 'est_other_$_currentTripId',
          tripId: _currentTripId,
          category: ExpenseCategory.other,
          description: 'Buffer & Miscellaneous',
          estimatedAmount: b.other.toDouble(),
          actualAmount: 0.0,
          currency: currency,
          currencySymbol: currencySymbol,
        ));
      }
    }

    // Load any offline persisted actuals for this trip
    await _loadFromLocal();
    _isInitialized = true;
  }

  /// Add or update an expense
  Future<void> addExpense(TripExpenseItem item) async {
    final idx = _activeExpenses.indexWhere((e) => e.id == item.id);
    if (idx >= 0) {
      _activeExpenses[idx] = item;
    } else {
      _activeExpenses.add(item);
    }
    await _saveToLocal();
    _syncToBackendBestEffort(item);
  }

  /// Record refuelling stop
  Future<void> recordRefuel({
    required String stationName,
    required String location,
    required String fuelType,
    required double litres,
    required double pricePerLitre,
    double? manualTotalAmount,
    String? receiptNumber,
    String? notes,
    String routeLeg = 'single',
  }) async {
    final calcTotal = litres * pricePerLitre;
    final total = manualTotalAmount != null && manualTotalAmount > 0 ? manualTotalAmount : calcTotal;

    final id = 'refuel_${DateTime.now().millisecondsSinceEpoch}';
    final currencySymbol = _activePlan?.fuelEstimate?.currencySymbol ?? '₹';
    final currency = _activePlan?.budget?.currency ?? 'INR';

    final item = TripExpenseItem(
      id: id,
      tripId: _currentTripId,
      category: ExpenseCategory.fuel,
      description: 'Refuel at $stationName',
      estimatedAmount: 0.0,
      actualAmount: total,
      currency: currency,
      currencySymbol: currencySymbol,
      location: location,
      notes: notes ?? '',
      receiptNumber: receiptNumber,
      paymentMethod: 'Card',
      stationName: stationName,
      fuelType: fuelType,
      litres: litres,
      pricePerLitre: pricePerLitre,
      routeLeg: routeLeg,
    );

    await addExpense(item);
  }

  /// Record toll plaza payment
  Future<void> recordTollPayment({
    required String tollPlazaId,
    required String tollPlazaName,
    required double actualAmount,
    double estimatedAmount = 0.0,
    String paymentMethod = 'FASTag',
    String? receiptNumber,
    String? notes,
    String routeLeg = 'single',
  }) async {
    final currencySymbol = _activePlan?.toll?.currency == 'USD' ? '\$' : '₹';
    final currency = _activePlan?.toll?.currency ?? 'INR';

    // Check if there is an existing estimated item for this toll
    final existingIdx = _activeExpenses.indexWhere((e) =>
      e.category == ExpenseCategory.toll &&
      (e.tollPlazaId == tollPlazaId || e.description == tollPlazaName)
    );

    if (existingIdx >= 0) {
      final existing = _activeExpenses[existingIdx];
      final updated = existing.copyWith(
        actualAmount: actualAmount,
        paymentMethod: paymentMethod,
        receiptNumber: receiptNumber,
        notes: notes,
        routeLeg: routeLeg,
      );
      _activeExpenses[existingIdx] = updated;
      await _saveToLocal();
      _syncToBackendBestEffort(updated);
    } else {
      final item = TripExpenseItem(
        id: 'toll_${DateTime.now().millisecondsSinceEpoch}',
        tripId: _currentTripId,
        category: ExpenseCategory.toll,
        description: tollPlazaName,
        estimatedAmount: estimatedAmount,
        actualAmount: actualAmount,
        currency: currency,
        currencySymbol: currencySymbol,
        tollPlazaId: tollPlazaId,
        tollPlazaName: tollPlazaName,
        paymentMethod: paymentMethod,
        receiptNumber: receiptNumber,
        notes: notes ?? '',
        routeLeg: routeLeg,
      );
      await addExpense(item);
    }
  }

  /// Record meal break expense
  Future<void> recordMealBreak({
    required ExpenseCategory category,
    required String placeName,
    required double actualAmount,
    double estimatedAmount = 0.0,
    String? notes,
    String? receiptNumber,
    String? stopId,
    String? stopName,
    String routeLeg = 'single',
  }) async {
    final currencySymbol = _activePlan?.fuelEstimate?.currencySymbol ?? '₹';
    final currency = _activePlan?.budget?.currency ?? 'INR';

    // Find if estimated entry exists for this category
    final existingIdx = _activeExpenses.indexWhere((e) =>
      e.category == category && e.id.startsWith('est_')
    );

    if (existingIdx >= 0) {
      final existing = _activeExpenses[existingIdx];
      final updated = existing.copyWith(
        actualAmount: (existing.actualAmount + actualAmount),
        notes: existing.notes.isNotEmpty ? '${existing.notes}; $placeName' : placeName,
        location: placeName,
        stopId: stopId,
        stopName: stopName,
        routeLeg: routeLeg,
      );
      _activeExpenses[existingIdx] = updated;
      await _saveToLocal();
      _syncToBackendBestEffort(updated);
    } else {
      final item = TripExpenseItem(
        id: 'meal_${DateTime.now().millisecondsSinceEpoch}',
        tripId: _currentTripId,
        category: category,
        description: '${category.displayName}: $placeName',
        estimatedAmount: estimatedAmount,
        actualAmount: actualAmount,
        currency: currency,
        currencySymbol: currencySymbol,
        location: placeName,
        notes: notes ?? '',
        receiptNumber: receiptNumber,
        stopId: stopId,
        stopName: stopName,
        routeLeg: routeLeg,
      );
      await addExpense(item);
    }
  }

  /// Category totals for live dashboard
  Map<String, CategoryExpenseSummary> getCategorySummaries() {
    final currencySymbol = _activePlan?.fuelEstimate?.currencySymbol ?? '₹';

    double estFuel = 0, actFuel = 0;
    double estToll = 0, actToll = 0;
    double estFood = 0, actFood = 0;
    double estParking = 0, actParking = 0;
    double estOther = 0, actOther = 0;

    for (final e in _activeExpenses) {
      switch (e.category) {
        case ExpenseCategory.fuel:
          estFuel += e.estimatedAmount;
          actFuel += e.actualAmount;
          break;
        case ExpenseCategory.toll:
          estToll += e.estimatedAmount;
          actToll += e.actualAmount;
          break;
        case ExpenseCategory.food:
        case ExpenseCategory.breakfast:
        case ExpenseCategory.lunch:
        case ExpenseCategory.tea:
        case ExpenseCategory.coffee:
        case ExpenseCategory.snacks:
        case ExpenseCategory.dinner:
          estFood += e.estimatedAmount;
          actFood += e.actualAmount;
          break;
        case ExpenseCategory.parking:
          estParking += e.estimatedAmount;
          actParking += e.actualAmount;
          break;
        case ExpenseCategory.accommodation:
        case ExpenseCategory.ticket:
        case ExpenseCategory.other:
          estOther += e.estimatedAmount;
          actOther += e.actualAmount;
          break;
      }
    }

    return {
      'fuel': CategoryExpenseSummary(categoryName: 'Fuel', estimated: estFuel, actual: actFuel, currencySymbol: currencySymbol),
      'tolls': CategoryExpenseSummary(categoryName: 'Tolls', estimated: estToll, actual: actToll, currencySymbol: currencySymbol),
      'food': CategoryExpenseSummary(categoryName: 'Food & Breaks', estimated: estFood, actual: actFood, currencySymbol: currencySymbol),
      'parking': CategoryExpenseSummary(categoryName: 'Parking', estimated: estParking, actual: actParking, currencySymbol: currencySymbol),
      'other': CategoryExpenseSummary(categoryName: 'Other', estimated: estOther, actual: actOther, currencySymbol: currencySymbol),
    };
  }

  /// Grand total estimated for active trip
  double getGrandTotalEstimated() {
    return _activeExpenses.fold(0.0, (sum, e) => sum + e.estimatedAmount);
  }

  /// Grand total actual spent for active trip
  double getGrandTotalActual() {
    return _activeExpenses.fold(0.0, (sum, e) => sum + e.actualAmount);
  }

  /// Generate comprehensive Final Trip Expense Report answering all 17 questions
  TripExpenseReport generateFinalReport({bool routedThroughAllStops = true}) {
    final fuelEst = _activePlan?.fuelEstimate;
    final currency = _activePlan?.budget?.currency ?? 'INR';
    final currencySymbol = fuelEst?.currencySymbol ?? '₹';

    final fuelItems = _activeExpenses.where((e) => e.category == ExpenseCategory.fuel).toList();
    final tollItems = _activeExpenses.where((e) => e.category == ExpenseCategory.toll).toList();
    final mealItems = _activeExpenses.where((e) =>
      e.category == ExpenseCategory.breakfast ||
      e.category == ExpenseCategory.lunch ||
      e.category == ExpenseCategory.tea ||
      e.category == ExpenseCategory.coffee ||
      e.category == ExpenseCategory.snacks ||
      e.category == ExpenseCategory.dinner
    ).toList();
    final otherItems = _activeExpenses.where((e) =>
      e.category == ExpenseCategory.parking ||
      e.category == ExpenseCategory.accommodation ||
      e.category == ExpenseCategory.ticket ||
      e.category == ExpenseCategory.other
    ).toList();

    // Fuel metrics
    final fuelRequiredLiters = fuelEst?.fuelRequired ??
      ((_activePlan?.distanceKm ?? 0) / (_activeVehicle?.efficiencyKmPerLiter ?? 15.0));
    final actualFuelPurchasedLiters = fuelItems.fold<double>(0.0, (sum, e) => sum + (e.litres ?? 0.0));
    final fuelPricePerLiter = fuelEst?.pricePerUnit ?? 102.45;
    final estimatedFuelCost = fuelEst?.estimatedCost ?? (fuelRequiredLiters * fuelPricePerLiter);
    final actualFuelCost = fuelItems.fold<double>(0.0, (sum, e) => sum + e.actualAmount);

    // Toll metrics
    final estimatedTollTotal = _activePlan?.toll?.fastagTollCost ??
      tollItems.fold<double>(0.0, (sum, e) => sum + e.estimatedAmount);
    final actualTollTotal = tollItems.fold<double>(0.0, (sum, e) => sum + e.actualAmount);

    // Meal metrics
    double estBreakfast = 0, actBreakfast = 0;
    double estLunch = 0, actLunch = 0;
    double estTea = 0, actTea = 0;
    double estDinner = 0, actDinner = 0;

    for (final m in mealItems) {
      if (m.category == ExpenseCategory.breakfast) {
        estBreakfast += m.estimatedAmount;
        actBreakfast += m.actualAmount;
      } else if (m.category == ExpenseCategory.lunch) {
        estLunch += m.estimatedAmount;
        actLunch += m.actualAmount;
      } else if (m.category == ExpenseCategory.dinner) {
        estDinner += m.estimatedAmount;
        actDinner += m.actualAmount;
      } else {
        estTea += m.estimatedAmount;
        actTea += m.actualAmount;
      }
    }

    // Other metrics
    double estParking = 0, actParking = 0;
    double estTickets = 0, actTickets = 0;
    double estOther = 0, actOther = 0;

    for (final o in otherItems) {
      if (o.category == ExpenseCategory.parking) {
        estParking += o.estimatedAmount;
        actParking += o.actualAmount;
      } else if (o.category == ExpenseCategory.ticket) {
        estTickets += o.estimatedAmount;
        actTickets += o.actualAmount;
      } else {
        estOther += o.estimatedAmount;
        actOther += o.actualAmount;
      }
    }

    // Leg totals for round trip
    double outEst = 0, outAct = 0;
    double retEst = 0, retAct = 0;

    for (final e in _activeExpenses) {
      if (e.routeLeg == 'return') {
        retEst += e.estimatedAmount;
        retAct += e.actualAmount;
      } else {
        outEst += e.estimatedAmount;
        outAct += e.actualAmount;
      }
    }

    final totalEst = estimatedFuelCost + estimatedTollTotal +
      (estBreakfast + estLunch + estTea + estDinner) +
      (estParking + estTickets + estOther);
    final totalAct = actualFuelCost + actualTollTotal +
      (actBreakfast + actLunch + actTea + actDinner) +
      (actParking + actTickets + actOther);

    return TripExpenseReport(
      tripId: _currentTripId,
      tripTitle: '$_startAddress → $_endAddress',
      startAddress: _startAddress,
      endAddress: _endAddress,
      distanceKm: _activePlan?.distanceKm ?? 0.0,
      durationMinutes: _activePlan?.durationMin ?? 0,
      currency: currency,
      currencySymbol: currencySymbol,
      isRoundTrip: _isRoundTrip,
      completedAt: DateTime.now(),
      routedThroughAllStops: routedThroughAllStops,
      confirmedStops: _confirmedWaypoints.map((w) => w.name ?? 'Waypoint').toList(),
      fuelRequiredLiters: double.parse(fuelRequiredLiters.toStringAsFixed(2)),
      actualFuelPurchasedLiters: double.parse(actualFuelPurchasedLiters.toStringAsFixed(2)),
      fuelPricePerLiter: double.parse(fuelPricePerLiter.toStringAsFixed(2)),
      estimatedFuelCost: double.parse(estimatedFuelCost.toStringAsFixed(2)),
      actualFuelCost: double.parse(actualFuelCost.toStringAsFixed(2)),
      fuelEntries: fuelItems,
      estimatedTollTotal: double.parse(estimatedTollTotal.toStringAsFixed(2)),
      actualTollTotal: double.parse(actualTollTotal.toStringAsFixed(2)),
      tollEntries: tollItems,
      estimatedBreakfast: double.parse(estBreakfast.toStringAsFixed(2)),
      actualBreakfast: double.parse(actBreakfast.toStringAsFixed(2)),
      estimatedLunch: double.parse(estLunch.toStringAsFixed(2)),
      actualLunch: double.parse(actLunch.toStringAsFixed(2)),
      estimatedTeaSnacks: double.parse(estTea.toStringAsFixed(2)),
      actualTeaSnacks: double.parse(actTea.toStringAsFixed(2)),
      estimatedDinner: double.parse(estDinner.toStringAsFixed(2)),
      actualDinner: double.parse(actDinner.toStringAsFixed(2)),
      mealEntries: mealItems,
      estimatedParking: double.parse(estParking.toStringAsFixed(2)),
      actualParking: double.parse(actParking.toStringAsFixed(2)),
      estimatedTickets: double.parse(estTickets.toStringAsFixed(2)),
      actualTickets: double.parse(actTickets.toStringAsFixed(2)),
      estimatedOther: double.parse(estOther.toStringAsFixed(2)),
      actualOther: double.parse(actOther.toStringAsFixed(2)),
      otherEntries: otherItems,
      outboundEstimatedTotal: double.parse(outEst.toStringAsFixed(2)),
      outboundActualTotal: double.parse(outAct.toStringAsFixed(2)),
      returnEstimatedTotal: double.parse(retEst.toStringAsFixed(2)),
      returnActualTotal: double.parse(retAct.toStringAsFixed(2)),
      totalEstimated: double.parse(totalEst.toStringAsFixed(2)),
      totalActual: double.parse(totalAct.toStringAsFixed(2)),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Local & Remote Persistence
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _saveToLocal() async {
    if (_currentTripId.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final listJson = _activeExpenses.map((e) => e.toJson()).toList();
      await sp.setString('trip_expenses_$_currentTripId', jsonEncode(listJson));
    } catch (e) {
      debugPrint('[EXPENSE] Local save failed: $e');
    }
  }

  Future<void> _loadFromLocal() async {
    if (_currentTripId.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final str = sp.getString('trip_expenses_$_currentTripId');
      if (str != null && str.isNotEmpty) {
        final List list = jsonDecode(str);
        for (final itemJson in list) {
          final item = TripExpenseItem.fromJson((itemJson as Map).cast<String, dynamic>());
          final idx = _activeExpenses.indexWhere((e) => e.id == item.id);
          if (idx >= 0) {
            _activeExpenses[idx] = item;
          } else {
            _activeExpenses.add(item);
          }
        }
      }
    } catch (e) {
      debugPrint('[EXPENSE] Local load failed: $e');
    }
  }

  Future<void> _syncToBackendBestEffort(TripExpenseItem item) async {
    try {
      final api = ApiService();
      await api.accountCreate('expenses', {
        'trip_id': item.tripId,
        'category': item.category.name,
        'amount': item.actualAmount > 0 ? item.actualAmount : item.estimatedAmount,
        'currency': item.currency,
        'note': '${item.description}${item.notes.isNotEmpty ? " · ${item.notes}" : ""}',
        'spent_at': item.dateTime.toIso8601String(),
      });
    } catch (e) {
      // Offline or unauthenticated; offline copy in SharedPreferences is preserved.
      debugPrint('[EXPENSE] Backend sync deferred (offline/guest): $e');
    }
  }
}
