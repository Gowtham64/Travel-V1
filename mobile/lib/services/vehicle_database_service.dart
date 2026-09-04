import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/vehicles_data.dart';

/// Vehicle Brand entity
class VehicleBrand {
  final String id;
  final String name;
  final String country;
  final String type; // 'car' or 'motorcycle'
  final String? logo;

  const VehicleBrand({
    required this.id,
    required this.name,
    required this.country,
    required this.type,
    this.logo,
  });

  factory VehicleBrand.fromJson(Map<String, dynamic> json) {
    return VehicleBrand(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      country: json['country'] as String? ?? 'India',
      type: json['type'] as String? ?? 'car',
      logo: json['logo'] as String?,
    );
  }
}

/// Vehicle Model entity
class VehicleModelSummary {
  final String id;
  final String name;
  final String brandId;
  final String brandName;
  final String type;
  final String? bodyType;
  final List<String> fuelTypes;
  final String? priceRange;

  const VehicleModelSummary({
    required this.id,
    required this.name,
    required this.brandId,
    required this.brandName,
    required this.type,
    this.bodyType,
    this.fuelTypes = const [],
    this.priceRange,
  });

  factory VehicleModelSummary.fromJson(Map<String, dynamic> json) {
    return VehicleModelSummary(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      brandId: json['brandId'] as String? ?? '',
      brandName: json['brandName'] as String? ?? '',
      type: json['type'] as String? ?? 'car',
      bodyType: json['bodyType'] as String?,
      fuelTypes: (json['fuelTypes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      priceRange: json['priceRange'] as String?,
    );
  }
}

/// Centralized Vehicle Database Service for VoyPlan across Web, iOS, and Android.
/// Sourced via CarDekho / Authorized Provider with offline caching and instant fuzzy search.
class VehicleDatabaseService {
  VehicleDatabaseService._();
  static final VehicleDatabaseService instance = VehicleDatabaseService._();

  final List<VehicleBrand> _cachedBrands = [];
  final Map<String, List<VehicleModelSummary>> _cachedModels = {};
  final Map<String, List<VehicleModel>> _cachedVariants = {};
  final List<VehicleModel> _extendedVehicles = [];

  bool _initialized = false;

  /// Ensure catalog is initialized with default and backend vehicles
  Future<void> init() async {
    if (_initialized) return;
    _populateLocalCatalog();
    _initialized = true;

    // Background asynchronous refresh from backend
    _fetchBrandsFromBackend().catchError((e) {
      debugPrint('Background vehicle brand fetch notice: $e');
      return <VehicleBrand>[];
    });
  }

  void _populateLocalCatalog() {
    _extendedVehicles.clear();
    _extendedVehicles.addAll(predefinedVehicles);
    _extendedVehicles.addAll(_extraCatalogVehicles);
  }

  static const List<VehicleModel> _extraCatalogVehicles = [
    // ── Electric Vehicles (EV) ──────────────────────────────────────────────
    VehicleModel(
      id: 'tata_nexon_ev',
      name: 'Tata Nexon EV',
      brandId: 'tata',
      brandName: 'Tata Motors',
      modelId: 'nexon-ev',
      modelName: 'Nexon EV',
      variantId: 'empowered_plus',
      variantName: 'Empowered Plus 40.5kWh',
      type: 'car',
      fuelType: 'ev',
      mileage: 7.5, // ~7.5 km/kWh equivalent
      tankCapacity: 0.0,
      batteryCapacityKwh: 40.5,
      evRangeKm: 465,
      seatingCapacity: 5,
      bodyType: 'Compact SUV',
      transmission: 'Automatic',
      priceRange: '₹14.49 - ₹19.49 Lakh',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 'tata_punch_ev',
      name: 'Tata Punch EV',
      brandId: 'tata',
      brandName: 'Tata Motors',
      modelId: 'punch-ev',
      modelName: 'Punch EV',
      variantId: 'long_range_empowered',
      variantName: 'Empowered Plus LR 35kWh',
      type: 'car',
      fuelType: 'ev',
      mileage: 8.0,
      tankCapacity: 0.0,
      batteryCapacityKwh: 35.0,
      evRangeKm: 421,
      seatingCapacity: 5,
      bodyType: 'Micro SUV',
      transmission: 'Automatic',
      priceRange: '₹10.99 - ₹15.49 Lakh',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 'mg_zs_ev',
      name: 'MG ZS EV',
      brandId: 'mg',
      brandName: 'MG Motors',
      modelId: 'zs-ev',
      modelName: 'ZS EV',
      variantId: 'exclusive_plus',
      variantName: 'Exclusive Plus 50.3kWh',
      type: 'car',
      fuelType: 'ev',
      mileage: 6.8,
      tankCapacity: 0.0,
      batteryCapacityKwh: 50.3,
      evRangeKm: 461,
      seatingCapacity: 5,
      bodyType: 'SUV',
      transmission: 'Automatic',
      priceRange: '₹18.98 - ₹25.44 Lakh',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 'hyundai_ioniq5',
      name: 'Hyundai Ioniq 5',
      brandId: 'hyundai',
      brandName: 'Hyundai',
      modelId: 'ioniq-5',
      modelName: 'Ioniq 5',
      variantId: 'rwd',
      variantName: 'Long Range RWD 72.6kWh',
      type: 'car',
      fuelType: 'ev',
      mileage: 6.5,
      tankCapacity: 0.0,
      batteryCapacityKwh: 72.6,
      evRangeKm: 631,
      seatingCapacity: 5,
      bodyType: 'Crossover SUV',
      transmission: 'Automatic',
      priceRange: '₹46.05 Lakh',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 'ola_s1_pro',
      name: 'Ola S1 Pro Gen 2',
      brandId: 'ola',
      brandName: 'Ola Electric',
      modelId: 's1-pro',
      modelName: 'S1 Pro',
      type: 'motorcycle',
      fuelType: 'ev',
      mileage: 35.0,
      tankCapacity: 0.0,
      batteryCapacityKwh: 4.0,
      evRangeKm: 195,
      seatingCapacity: 2,
      bodyType: 'Electric Scooter',
      transmission: 'Automatic',
      priceRange: '₹1.29 Lakh',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 'ather_450x',
      name: 'Ather 450X',
      brandId: 'ather',
      brandName: 'Ather Energy',
      modelId: '450x',
      modelName: '450X Gen 3',
      type: 'motorcycle',
      fuelType: 'ev',
      mileage: 32.0,
      tankCapacity: 0.0,
      batteryCapacityKwh: 3.7,
      evRangeKm: 150,
      seatingCapacity: 2,
      bodyType: 'Electric Scooter',
      transmission: 'Automatic',
      priceRange: '₹1.40 Lakh',
      modelYear: 2026,
    ),

    // ── CNG Vehicles ────────────────────────────────────────────────────────
    VehicleModel(
      id: 'maruti_ertiga_cng',
      name: 'Maruti Suzuki Ertiga CNG',
      brandId: 'maruti',
      brandName: 'Maruti Suzuki',
      modelId: 'ertiga',
      modelName: 'Ertiga VXi CNG',
      type: 'car',
      fuelType: 'cng',
      mileage: 26.11, // km/kg
      tankCapacity: 60.0, // Water equivalent L (approx 9-10 kg CNG)
      engine: '1.5L K15C DualJet',
      seatingCapacity: 7,
      bodyType: 'MPV',
      transmission: 'Manual',
      priceRange: '₹10.78 - ₹11.88 Lakh',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 'tata_punch_cng',
      name: 'Tata Punch iCNG',
      brandId: 'tata',
      brandName: 'Tata Motors',
      modelId: 'punch',
      modelName: 'Punch Adventure iCNG',
      type: 'car',
      fuelType: 'cng',
      mileage: 26.99, // km/kg
      tankCapacity: 60.0,
      engine: '1.2L Revotron Twin-Cylinder',
      seatingCapacity: 5,
      bodyType: 'Micro SUV',
      transmission: 'Manual',
      priceRange: '₹7.23 - ₹9.85 Lakh',
      modelYear: 2026,
    ),

    // ── Strong Hybrid Vehicles ──────────────────────────────────────────────
    VehicleModel(
      id: 'toyota_hycross_hybrid',
      name: 'Toyota Innova Hycross Strong Hybrid',
      brandId: 'toyota',
      brandName: 'Toyota',
      modelId: 'innova-hycross',
      modelName: 'Innova Hycross ZX(O) Hybrid',
      type: 'car',
      fuelType: 'hybrid',
      mileage: 23.24,
      tankCapacity: 52.0,
      batteryCapacityKwh: 1.68,
      engine: '2.0L TNGA 5th Gen Self-Charging Hybrid',
      seatingCapacity: 7,
      bodyType: 'MPV',
      transmission: 'e-CVT',
      priceRange: '₹25.97 - ₹30.98 Lakh',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 'maruti_grand_vitara_hybrid',
      name: 'Maruti Suzuki Grand Vitara Strong Hybrid',
      brandId: 'maruti',
      brandName: 'Maruti Suzuki',
      modelId: 'grand-vitara',
      modelName: 'Grand Vitara Alpha+ Hybrid',
      type: 'car',
      fuelType: 'hybrid',
      mileage: 27.97,
      tankCapacity: 45.0,
      batteryCapacityKwh: 0.76,
      engine: '1.5L Intelligent Electric Hybrid',
      seatingCapacity: 5,
      bodyType: 'SUV',
      transmission: 'e-CVT',
      priceRange: '₹18.43 - ₹20.09 Lakh',
      modelYear: 2026,
    ),
  ];

  /// Get list of brands
  Future<List<VehicleBrand>> getBrands({String? type}) async {
    await init();
    if (_cachedBrands.isNotEmpty) {
      if (type != null) {
        return _cachedBrands.where((b) => b.type == type).toList();
      }
      return _cachedBrands;
    }

    final fetched = await _fetchBrandsFromBackend();
    if (fetched.isNotEmpty) {
      _cachedBrands.clear();
      _cachedBrands.addAll(fetched);
      if (type != null) {
        return _cachedBrands.where((b) => b.type == type).toList();
      }
      return _cachedBrands;
    }

    // Fallback static brands extracted from catalog
    return _getDefaultBrands(type: type);
  }

  /// Search vehicles dynamically by query string, fuelType filter, and vehicle type
  Future<List<VehicleModel>> searchVehicles(
    String query, {
    String? fuelType,
    String? type,
    int limit = 30,
  }) async {
    await init();
    final q = query.toLowerCase().trim();
    final normFuel = fuelType?.toLowerCase().trim();

    // 1. Try backend search endpoint if online
    try {
      final uri = Uri.parse('${AppConfig.backendUrl}/api/vehicles/search')
          .replace(queryParameters: {
        if (q.isNotEmpty) 'q': q,
        if (normFuel != null && normFuel != 'all') 'fuelType': normFuel,
        if (type != null && type != 'all') 'type': type,
        'limit': limit.toString(),
      });

      final res = await http.get(uri).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (data['vehicles'] as List<dynamic>?) ?? [];
        if (list.isNotEmpty) {
          final remoteVehicles = list
              .map((v) => VehicleModel.fromJson(v as Map<String, dynamic>))
              .where((v) {
                if (normFuel != null && normFuel != 'all' && v.fuelType.toLowerCase() != normFuel) {
                  return false;
                }
                if (type != null && type != 'all' && v.type.toLowerCase() != type) {
                  return false;
                }
                return true;
              })
              .toList();
          if (remoteVehicles.isNotEmpty) {
            return remoteVehicles;
          }
        }
      }
    } catch (_) {
      // Gracefully fall through to fast local catalog search
    }

    // 2. High-performance client-side search over catalog
    return _searchLocal(q, normFuel, type, limit);
  }

  List<VehicleModel> _searchLocal(String query, String? fuelType, String? type, int limit) {
    return _extendedVehicles.where((v) {
      if (fuelType != null && fuelType != 'all' && v.fuelType.toLowerCase() != fuelType) {
        return false;
      }
      if (type != null && type != 'all' && v.type.toLowerCase() != type) {
        return false;
      }
      if (query.isEmpty) return true;

      final matchText = '${v.brandName ?? ''} ${v.name} ${v.variantName ?? ''} ${v.fuelType} ${v.bodyType ?? ''}'.toLowerCase();
      final words = query.split(' ').where((w) => w.isNotEmpty);
      return words.every((w) => matchText.contains(w));
    }).take(limit).toList();
  }

  Future<List<VehicleBrand>> _fetchBrandsFromBackend() async {
    try {
      final uri = Uri.parse('${AppConfig.backendUrl}/api/vehicles/brands');
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (data['brands'] as List<dynamic>?) ?? [];
        return list.map((b) => VehicleBrand.fromJson(b as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  List<VehicleBrand> _getDefaultBrands({String? type}) {
    const all = [
      VehicleBrand(id: 'tata', name: 'Tata Motors', country: 'India', type: 'car'),
      VehicleBrand(id: 'mahindra', name: 'Mahindra', country: 'India', type: 'car'),
      VehicleBrand(id: 'toyota', name: 'Toyota', country: 'Japan', type: 'car'),
      VehicleBrand(id: 'hyundai', name: 'Hyundai', country: 'South Korea', type: 'car'),
      VehicleBrand(id: 'maruti_suzuki', name: 'Maruti Suzuki', country: 'India', type: 'car'),
      VehicleBrand(id: 'kia', name: 'Kia', country: 'South Korea', type: 'car'),
      VehicleBrand(id: 'honda', name: 'Honda', country: 'Japan', type: 'car'),
      VehicleBrand(id: 'skoda', name: 'Skoda', country: 'Czech Republic', type: 'car'),
      VehicleBrand(id: 'volkswagen', name: 'Volkswagen', country: 'Germany', type: 'car'),
      VehicleBrand(id: 'mg', name: 'MG Motor', country: 'UK', type: 'car'),
      VehicleBrand(id: 'bmw', name: 'BMW', country: 'Germany', type: 'car'),
      VehicleBrand(id: 'mercedes_benz', name: 'Mercedes-Benz', country: 'Germany', type: 'car'),
      VehicleBrand(id: 'royal_enfield', name: 'Royal Enfield', country: 'India', type: 'motorcycle'),
      VehicleBrand(id: 'hero', name: 'Hero MotoCorp', country: 'India', type: 'motorcycle'),
      VehicleBrand(id: 'bajaj', name: 'Bajaj Auto', country: 'India', type: 'motorcycle'),
      VehicleBrand(id: 'tvs', name: 'TVS Motor', country: 'India', type: 'motorcycle'),
      VehicleBrand(id: 'ktm', name: 'KTM', country: 'Austria', type: 'motorcycle'),
      VehicleBrand(id: 'ola_electric', name: 'Ola Electric', country: 'India', type: 'motorcycle'),
    ];
    if (type != null) {
      return all.where((b) => b.type == type).toList();
    }
    return all;
  }
}
