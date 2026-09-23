import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Supported Global Currencies
enum Currency {
  inr(code: 'INR', symbol: '₹', name: 'Indian Rupee', rateToInr: 1.0),
  usd(code: 'USD', symbol: '\$', name: 'US Dollar', rateToInr: 86.5),
  eur(code: 'EUR', symbol: '€', name: 'Euro', rateToInr: 93.0),
  gbp(code: 'GBP', symbol: '£', name: 'British Pound', rateToInr: 110.0),
  aed(code: 'AED', symbol: 'AED', name: 'UAE Dirham', rateToInr: 23.5),
  aud(code: 'AUD', symbol: 'A\$', name: 'Australian Dollar', rateToInr: 56.0),
  jpy(code: 'JPY', symbol: '¥', name: 'Japanese Yen', rateToInr: 0.58),
  cad(code: 'CAD', symbol: 'C\$', name: 'Canadian Dollar', rateToInr: 61.5),
  sgd(code: 'SGD', symbol: 'S\$', name: 'Singapore Dollar', rateToInr: 65.0);

  final String code;
  final String symbol;
  final String name;
  final double rateToInr;

  const Currency({
    required this.code,
    required this.symbol,
    required this.name,
    required this.rateToInr,
  });

  static Currency fromCode(String code) {
    return Currency.values.firstWhere(
      (c) => c.code.toUpperCase() == code.toUpperCase(),
      orElse: () => Currency.inr,
    );
  }
}

/// Supported Unit Systems
enum UnitSystem {
  metric(distanceUnit: 'km', speedUnit: 'km/h', fuelEfficiencyUnit: 'km/L'),
  imperial(distanceUnit: 'mi', speedUnit: 'mph', fuelEfficiencyUnit: 'MPG');

  final String distanceUnit;
  final String speedUnit;
  final String fuelEfficiencyUnit;

  const UnitSystem({
    required this.distanceUnit,
    required this.speedUnit,
    required this.fuelEfficiencyUnit,
  });

  static UnitSystem fromString(String val) {
    return val.toLowerCase() == 'imperial' ? UnitSystem.imperial : UnitSystem.metric;
  }
}

/// Global Region Definition
class GlobalRegion {
  final String id;
  final String name;
  final String flag;
  final Currency defaultCurrency;
  final UnitSystem defaultUnitSystem;
  final String defaultOrigin;
  final double defaultLat;
  final double defaultLng;

  const GlobalRegion({
    required this.id,
    required this.name,
    required this.flag,
    required this.defaultCurrency,
    required this.defaultUnitSystem,
    required this.defaultOrigin,
    required this.defaultLat,
    required this.defaultLng,
  });
}

/// Central service managing global currency, unit formatting, and regional preferences.
class GlobalConfigService extends ChangeNotifier {
  GlobalConfigService._();
  static final GlobalConfigService instance = GlobalConfigService._();

  static const List<GlobalRegion> supportedRegions = [
    GlobalRegion(
      id: 'IN',
      name: 'India',
      flag: '🇮🇳',
      defaultCurrency: Currency.inr,
      defaultUnitSystem: UnitSystem.metric,
      defaultOrigin: 'Bengaluru, Karnataka',
      defaultLat: 12.9716,
      defaultLng: 77.5946,
    ),
    GlobalRegion(
      id: 'US',
      name: 'United States',
      flag: '🇺🇸',
      defaultCurrency: Currency.usd,
      defaultUnitSystem: UnitSystem.imperial,
      defaultOrigin: 'San Francisco, CA',
      defaultLat: 37.7749,
      defaultLng: -122.4194,
    ),
    GlobalRegion(
      id: 'GB',
      name: 'United Kingdom',
      flag: '🇬🇧',
      defaultCurrency: Currency.gbp,
      defaultUnitSystem: UnitSystem.imperial,
      defaultOrigin: 'London, England',
      defaultLat: 51.5074,
      defaultLng: -0.1278,
    ),
    GlobalRegion(
      id: 'AE',
      name: 'United Arab Emirates',
      flag: '🇦🇪',
      defaultCurrency: Currency.aed,
      defaultUnitSystem: UnitSystem.metric,
      defaultOrigin: 'Dubai, UAE',
      defaultLat: 25.2048,
      defaultLng: 55.2708,
    ),
    GlobalRegion(
      id: 'EU',
      name: 'Europe',
      flag: '🇪🇺',
      defaultCurrency: Currency.eur,
      defaultUnitSystem: UnitSystem.metric,
      defaultOrigin: 'Paris, France',
      defaultLat: 48.8566,
      defaultLng: 2.3522,
    ),
    GlobalRegion(
      id: 'AU',
      name: 'Australia',
      flag: '🇦🇺',
      defaultCurrency: Currency.aud,
      defaultUnitSystem: UnitSystem.metric,
      defaultOrigin: 'Sydney, NSW',
      defaultLat: -33.8688,
      defaultLng: 151.2093,
    ),
  ];

  GlobalRegion _currentRegion = supportedRegions.first;
  Currency _currentCurrency = Currency.inr;
  UnitSystem _currentUnitSystem = UnitSystem.metric;
  bool _initialized = false;

  GlobalRegion get currentRegion => _currentRegion;
  Currency get currentCurrency => _currentCurrency;
  UnitSystem get currentUnitSystem => _currentUnitSystem;
  bool get isImperial => _currentUnitSystem == UnitSystem.imperial;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final regionCode = prefs.getString('voyplan_region_code');
      if (regionCode != null) {
        final r = supportedRegions.firstWhere(
          (reg) => reg.id == regionCode,
          orElse: () => supportedRegions.first,
        );
        _currentRegion = r;
      }

      final currCode = prefs.getString('voyplan_currency_code');
      if (currCode != null) {
        _currentCurrency = Currency.fromCode(currCode);
      } else {
        _currentCurrency = _currentRegion.defaultCurrency;
      }

      final unitStr = prefs.getString('voyplan_unit_system');
      if (unitStr != null) {
        _currentUnitSystem = UnitSystem.fromString(unitStr);
      } else {
        _currentUnitSystem = _currentRegion.defaultUnitSystem;
      }
    } catch (e) {
      debugPrint('GlobalConfigService init note: $e');
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> setRegion(GlobalRegion region, {bool updateDefaults = true}) async {
    _currentRegion = region;
    if (updateDefaults) {
      _currentCurrency = region.defaultCurrency;
      _currentUnitSystem = region.defaultUnitSystem;
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('voyplan_region_code', region.id);
      await prefs.setString('voyplan_currency_code', _currentCurrency.code);
      await prefs.setString('voyplan_unit_system', _currentUnitSystem.name);
    } catch (_) {}
  }

  Future<void> setRegionById(String regionId, {bool updateDefaults = true}) async {
    final region = supportedRegions.firstWhere(
      (r) => r.id.toUpperCase() == regionId.toUpperCase(),
      orElse: () => supportedRegions.first,
    );
    await setRegion(region, updateDefaults: updateDefaults);
  }

  Future<void> setCurrency(Currency currency) async {
    _currentCurrency = currency;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('voyplan_currency_code', currency.code);
    } catch (_) {}
  }

  Future<void> setUnitSystem(UnitSystem unitSystem) async {
    _currentUnitSystem = unitSystem;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('voyplan_unit_system', unitSystem.name);
    } catch (_) {}
  }

  /// Formats amount in INR base to the currently active currency.
  String formatMoney(double amountInInr, {bool includeSymbol = true, int decimals = 0}) {
    final converted = amountInInr / _currentCurrency.rateToInr;
    final valStr = decimals > 0
        ? converted.toStringAsFixed(decimals)
        : converted.round().toString();
    if (!includeSymbol) return valStr;
    if (_currentCurrency.symbol.length > 1) {
      return '${_currentCurrency.symbol} $valStr';
    }
    return '${_currentCurrency.symbol}$valStr';
  }

  /// Formats distance in km to current unit system (km or mi).
  String formatDistance(double distanceInKm, {int decimals = 0}) {
    if (_currentUnitSystem == UnitSystem.imperial) {
      final miles = distanceInKm * 0.621371;
      return '${miles.toStringAsFixed(decimals)} mi';
    }
    return '${distanceInKm.toStringAsFixed(decimals)} km';
  }

  /// Formats speed in km/h to current unit system (km/h or mph).
  String formatSpeed(double speedInKmh, {int decimals = 0}) {
    if (_currentUnitSystem == UnitSystem.imperial) {
      final mph = speedInKmh * 0.621371;
      return '${mph.toStringAsFixed(decimals)} mph';
    }
    return '${speedInKmh.toStringAsFixed(decimals)} km/h';
  }
}
