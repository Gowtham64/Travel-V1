import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/vehicles_data.dart';

/// Persisted vehicle settings (Fuel in tank & Mileage)
class VehicleSettings {
  final String vehicleId;
  final double currentFuel;
  final double mileage;
  final String fuelType;

  const VehicleSettings({
    required this.vehicleId,
    required this.currentFuel,
    required this.mileage,
    required this.fuelType,
  });

  Map<String, dynamic> toJson() => {
    'vehicleId': vehicleId,
    'currentFuel': currentFuel,
    'mileage': mileage,
    'fuelType': fuelType,
  };

  factory VehicleSettings.fromJson(Map<String, dynamic> json) => VehicleSettings(
    vehicleId: json['vehicleId'] as String? ?? '',
    currentFuel: (json['currentFuel'] as num?)?.toDouble() ?? 0.0,
    mileage: (json['mileage'] as num?)?.toDouble() ?? 15.0,
    fuelType: json['fuelType'] as String? ?? 'petrol',
  );
}

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

  static const String _prefPrefix = 'voyplan_vehicle_settings_';
  final Map<String, VehicleSettings> _savedSettings = {};

  final List<VehicleBrand> _cachedBrands = [];
  final List<VehicleModel> _extendedVehicles = [];

  bool _initialized = false;

  /// Ensure catalog is initialized with default and backend vehicles
  Future<void> init() async {
    if (_initialized) return;
    _populateLocalCatalog();
    await _loadSavedSettings();
    _initialized = true;

    // Background asynchronous refresh from backend
    _fetchBrandsFromBackend().catchError((e) {
      debugPrint('Background vehicle brand fetch notice: $e');
      return <VehicleBrand>[];
    });
  }

  /// Synchronous retrieval of saved settings for a vehicle
  VehicleSettings? getVehicleSettings(String vehicleId) {
    return _savedSettings[vehicleId];
  }

  /// Persist vehicle settings (current fuel, mileage, fuelType) locally
  Future<void> saveVehicleSettings({
    required String vehicleId,
    required double currentFuel,
    required double mileage,
    required String fuelType,
  }) async {
    final settings = VehicleSettings(
      vehicleId: vehicleId,
      currentFuel: currentFuel,
      mileage: mileage,
      fuelType: fuelType,
    );
    _savedSettings[vehicleId] = settings;

    try {
      WidgetsFlutterBinding.ensureInitialized();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefPrefix$vehicleId', jsonEncode(settings.toJson()));
      final savedIds = prefs.getStringList('voyplan_saved_vehicle_ids') ?? [];
      if (!savedIds.contains(vehicleId)) {
        savedIds.add(vehicleId);
        await prefs.setStringList('voyplan_saved_vehicle_ids', savedIds);
      }
    } catch (e) {
      debugPrint('Error saving vehicle settings to SharedPreferences: $e');
    }
  }

  Future<void> _loadSavedSettings() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      final prefs = await SharedPreferences.getInstance();
      final savedIds = prefs.getStringList('voyplan_saved_vehicle_ids') ?? [];
      for (final id in savedIds) {
        final jsonStr = prefs.getString('$_prefPrefix$id');
        if (jsonStr != null && jsonStr.isNotEmpty) {
          try {
            final data = jsonDecode(jsonStr) as Map<String, dynamic>;
            _savedSettings[id] = VehicleSettings.fromJson(data);
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Error loading saved vehicle settings: $e');
    }
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

    // ── Motorcycles & Scooters ──────────────────────────────────────────────
    VehicleModel(
      id: 're_himalayan_450',
      name: 'Royal Enfield Himalayan 450',
      brandId: 'royal_enfield',
      brandName: 'Royal Enfield',
      modelId: 'himalayan',
      modelName: 'Himalayan 450',
      variantId: 'summit_hanle_black',
      variantName: 'Summit Hanle Black Tubeless',
      type: 'motorcycle',
      fuelType: 'petrol',
      mileage: 30.0,
      tankCapacity: 17.0,
      engine: '452 cc Sherpa Liquid-Cooled (40 bhp)',
      transmission: 'Manual 6-Speed',
      seatingCapacity: 2,
      bodyType: 'Adventure Tourer',
      priceRange: '₹2.85 - ₹2.98 Lakh',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 're_classic_350',
      name: 'Royal Enfield Classic 350',
      brandId: 'royal_enfield',
      brandName: 'Royal Enfield',
      modelId: 'classic_350',
      modelName: 'Classic 350 Reborn',
      variantId: 'stealth_black',
      variantName: 'Stealth Black Dual-Channel ABS',
      type: 'motorcycle',
      fuelType: 'petrol',
      mileage: 37.0,
      tankCapacity: 13.0,
      engine: '349 cc J-Series Air-Oil Cooled',
      transmission: 'Manual 5-Speed',
      seatingCapacity: 2,
      bodyType: 'Classic Cruiser',
      priceRange: '₹1.93 - ₹2.30 Lakh',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 're_hunter_350',
      name: 'Royal Enfield Hunter 350',
      brandId: 'royal_enfield',
      brandName: 'Royal Enfield',
      modelId: 'hunter_350',
      modelName: 'Hunter 350',
      variantId: 'rebel_red',
      variantName: 'Rebel Red Dual-Channel ABS',
      type: 'motorcycle',
      fuelType: 'petrol',
      mileage: 36.0,
      tankCapacity: 13.0,
      engine: '349 cc J-Series Air-Oil Cooled',
      transmission: 'Manual 5-Speed',
      seatingCapacity: 2,
      bodyType: 'Urban Roadster',
      priceRange: '₹1.75 Lakh',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 're_continental_gt_650',
      name: 'Royal Enfield Continental GT 650',
      brandId: 'royal_enfield',
      brandName: 'Royal Enfield',
      modelId: 'continental_gt_650',
      modelName: 'Continental GT 650',
      variantId: 'apex_grey',
      variantName: 'Apex Grey Cast Alloy Wheels',
      type: 'motorcycle',
      fuelType: 'petrol',
      mileage: 25.0,
      tankCapacity: 12.5,
      engine: '648 cc Parallel Twin (47 bhp)',
      transmission: 'Manual 6-Speed with Slipper Clutch',
      seatingCapacity: 2,
      bodyType: 'Cafe Racer',
      priceRange: '₹3.45 Lakh',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 'ktm_duke_390',
      name: 'KTM 390 Duke',
      brandId: 'ktm',
      brandName: 'KTM',
      modelId: 'duke_390',
      modelName: '390 Duke Gen 3',
      variantId: 'electronic_orange',
      variantName: 'Electronic Orange Launch Control',
      type: 'motorcycle',
      fuelType: 'petrol',
      mileage: 28.0,
      tankCapacity: 15.0,
      engine: '399 cc LC4c (46 PS / 39 Nm)',
      transmission: 'Manual 6-Speed with Quickshifter+',
      seatingCapacity: 2,
      bodyType: 'Naked Streetfighter',
      priceRange: '₹3.11 Lakh',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 'ktm_390_adv',
      name: 'KTM 390 Adventure',
      brandId: 'ktm',
      brandName: 'KTM',
      modelId: '390_adventure',
      modelName: '390 Adventure SW',
      variantId: 'spoke_wheels',
      variantName: 'SW Spoke Wheels WP Apex',
      type: 'motorcycle',
      fuelType: 'petrol',
      mileage: 28.5,
      tankCapacity: 14.5,
      engine: '373.2 cc Liquid-Cooled (43.5 PS)',
      transmission: 'Manual 6-Speed',
      seatingCapacity: 2,
      bodyType: 'Adventure Tourer',
      priceRange: '₹3.39 Lakh',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 'yamaha_r15_v4',
      name: 'Yamaha YZF-R15 V4',
      brandId: 'yamaha',
      brandName: 'Yamaha',
      modelId: 'r15',
      modelName: 'YZF-R15 V4',
      variantId: 'racing_blue',
      variantName: 'Racing Blue Traction Control',
      type: 'motorcycle',
      fuelType: 'petrol',
      mileage: 45.0,
      tankCapacity: 11.0,
      engine: '155 cc VVA Liquid-Cooled (18.4 PS)',
      transmission: 'Manual 6-Speed with Quickshifter',
      seatingCapacity: 2,
      bodyType: 'Supersport',
      priceRange: '₹1.87 Lakh',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 'yamaha_mt_15',
      name: 'Yamaha MT-15 V2',
      brandId: 'yamaha',
      brandName: 'Yamaha',
      modelId: 'mt_15',
      modelName: 'MT-15 V2',
      variantId: 'deluxe',
      variantName: 'Deluxe Cyber Green USD Forks',
      type: 'motorcycle',
      fuelType: 'petrol',
      mileage: 46.0,
      tankCapacity: 10.0,
      engine: '155 cc VVA Liquid-Cooled',
      transmission: 'Manual 6-Speed',
      seatingCapacity: 2,
      bodyType: 'Hyper Naked',
      priceRange: '₹1.68 Lakh',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 'honda_cb350',
      name: 'Honda H\'ness CB350',
      brandId: 'honda',
      brandName: 'Honda',
      modelId: 'cb350',
      modelName: 'H\'ness CB350',
      variantId: 'legacy_edition',
      variantName: 'Legacy Edition HSTC Slipper Clutch',
      type: 'motorcycle',
      fuelType: 'petrol',
      mileage: 38.0,
      tankCapacity: 15.0,
      engine: '348.36 cc SI Air-Cooled (21 PS)',
      transmission: 'Manual 5-Speed',
      seatingCapacity: 2,
      bodyType: 'Modern Classic',
      priceRange: '₹2.10 Lakh',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 'honda_activa_6g',
      name: 'Honda Activa 6G',
      brandId: 'honda',
      brandName: 'Honda',
      modelId: 'activa_6g',
      modelName: 'Activa 6G',
      variantId: 'dlx_h_smart',
      variantName: 'DLX H-Smart Key Digital',
      type: 'motorcycle',
      fuelType: 'petrol',
      mileage: 48.0,
      tankCapacity: 5.3,
      engine: '109.5 cc Fan-Cooled eSP PGM-FI',
      transmission: 'Automatic CVT',
      seatingCapacity: 2,
      bodyType: 'Scooter',
      priceRange: '₹79,000',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 'bajaj_pulsar_ns200',
      name: 'Bajaj Pulsar NS200',
      brandId: 'bajaj',
      brandName: 'Bajaj Auto',
      modelId: 'pulsar_ns200',
      modelName: 'Pulsar NS200',
      variantId: 'usd_forks',
      variantName: 'Dual Channel ABS Upside Down Forks',
      type: 'motorcycle',
      fuelType: 'petrol',
      mileage: 36.0,
      tankCapacity: 12.0,
      engine: '199.5 cc Triple Spark 4V (24.5 PS)',
      transmission: 'Manual 6-Speed',
      seatingCapacity: 2,
      bodyType: 'Naked Street',
      priceRange: '₹1.58 Lakh',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 'bajaj_dominar_400',
      name: 'Bajaj Dominar 400',
      brandId: 'bajaj',
      brandName: 'Bajaj Auto',
      modelId: 'dominar_400',
      modelName: 'Dominar 400 Touring',
      variantId: 'factory_touring',
      variantName: 'Factory Touring Edition Visor & Carrier',
      type: 'motorcycle',
      fuelType: 'petrol',
      mileage: 27.0,
      tankCapacity: 13.0,
      engine: '373.3 cc DOHC Liquid-Cooled (40 PS)',
      transmission: 'Manual 6-Speed with Slipper Clutch',
      seatingCapacity: 2,
      bodyType: 'Power Tourer',
      priceRange: '₹2.32 Lakh',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 'bajaj_freedom_125',
      name: 'Bajaj Freedom 125 CNG',
      brandId: 'bajaj',
      brandName: 'Bajaj Auto',
      modelId: 'freedom_125',
      modelName: 'Freedom 125 NG04',
      variantId: 'disc_led',
      variantName: 'NG04 Disc LED Dual Fuel (CNG + Petrol)',
      type: 'motorcycle',
      fuelType: 'cng',
      mileage: 102.0, // km/kg
      tankCapacity: 2.0, // 2kg CNG tank
      engine: '125 cc Dual-Fuel CNG-Petrol',
      transmission: 'Manual 5-Speed',
      seatingCapacity: 2,
      bodyType: 'CNG Commuter Bike',
      priceRange: '₹1.10 Lakh',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 'tvs_apache_rtr_310',
      name: 'TVS Apache RTR 310',
      brandId: 'tvs',
      brandName: 'TVS Motor',
      modelId: 'apache_rtr_310',
      modelName: 'Apache RTR 310',
      variantId: 'bto_dynamic',
      variantName: 'BTO Dynamic Pro Bi-directional Quickshifter',
      type: 'motorcycle',
      fuelType: 'petrol',
      mileage: 30.0,
      tankCapacity: 11.0,
      engine: '312.12 cc DOHC Liquid Cooled (35.6 bhp)',
      transmission: 'Manual 6-Speed',
      seatingCapacity: 2,
      bodyType: 'Streetfighter',
      priceRange: '₹2.43 - ₹2.64 Lakh',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 'tvs_ronin_225',
      name: 'TVS Ronin 225',
      brandId: 'tvs',
      brandName: 'TVS Motor',
      modelId: 'ronin',
      modelName: 'Ronin 225',
      variantId: 'td_special',
      variantName: 'TD Special Edition Dual-ABS',
      type: 'motorcycle',
      fuelType: 'petrol',
      mileage: 40.0,
      tankCapacity: 14.0,
      engine: '225.9 cc Oil Cooled 4V (20.4 PS)',
      transmission: 'Manual 5-Speed',
      seatingCapacity: 2,
      bodyType: 'Modern Retro Scrambler',
      priceRange: '₹1.69 Lakh',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 'hero_splendor_plus',
      name: 'Hero Splendor Plus XTEC',
      brandId: 'hero',
      brandName: 'Hero MotoCorp',
      modelId: 'splendor_plus',
      modelName: 'Splendor Plus',
      variantId: 'xtec_2_0',
      variantName: 'XTEC 2.0 Bluetooth Disc LED',
      type: 'motorcycle',
      fuelType: 'petrol',
      mileage: 65.0,
      tankCapacity: 9.8,
      engine: '97.2 cc Single Cylinder OHC',
      transmission: 'Manual 4-Speed',
      seatingCapacity: 2,
      bodyType: 'Commuter',
      priceRange: '₹79,000',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 'hero_xpulse_200_4v',
      name: 'Hero XPulse 200 4V',
      brandId: 'hero',
      brandName: 'Hero MotoCorp',
      modelId: 'xpulse_200',
      modelName: 'XPulse 200 4V',
      variantId: 'pro_edition',
      variantName: 'Pro Edition Fully Adjustable Suspension',
      type: 'motorcycle',
      fuelType: 'petrol',
      mileage: 38.0,
      tankCapacity: 13.0,
      engine: '199.6 cc 4V Oil-Cooled (19.1 PS)',
      transmission: 'Manual 5-Speed',
      seatingCapacity: 2,
      bodyType: 'Dual-Sport Adventure',
      priceRange: '₹1.54 Lakh',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 'triumph_speed_400',
      name: 'Triumph Speed 400',
      brandId: 'triumph',
      brandName: 'Triumph',
      modelId: 'speed_400',
      modelName: 'Speed 400',
      variantId: 'standard_abs',
      variantName: 'Roadster TR-Series 40 PS Traction Control',
      type: 'motorcycle',
      fuelType: 'petrol',
      mileage: 30.0,
      tankCapacity: 13.0,
      engine: '398.15 cc DOHC Liquid-Cooled (40 PS)',
      transmission: 'Manual 6-Speed with Assist Clutch',
      seatingCapacity: 2,
      bodyType: 'Modern Classic Roadster',
      priceRange: '₹2.34 Lakh',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 'bmw_g310_gs',
      name: 'BMW G 310 GS',
      brandId: 'bmw',
      brandName: 'BMW Motorrad',
      modelId: 'g310_gs',
      modelName: 'G 310 GS',
      variantId: 'rallye_style',
      variantName: 'Rallye Style Ride-by-Wire ABS',
      type: 'motorcycle',
      fuelType: 'petrol',
      mileage: 30.0,
      tankCapacity: 11.5,
      engine: '313 cc Water-Cooled Single (34 PS)',
      transmission: 'Manual 6-Speed with Anti-Hopping Clutch',
      seatingCapacity: 2,
      bodyType: 'Adventure Tourer',
      priceRange: '₹3.30 Lakh',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 'harley_davidson_x440',
      name: 'Harley-Davidson X440',
      brandId: 'harley_davidson',
      brandName: 'Harley-Davidson',
      modelId: 'x440',
      modelName: 'X440',
      variantId: 's_variant',
      variantName: 'Top S Variant Diamond Cut Alloys Connect',
      type: 'motorcycle',
      fuelType: 'petrol',
      mileage: 34.0,
      tankCapacity: 13.5,
      engine: '440 cc Single-Cylinder (27 bhp / 38 Nm)',
      transmission: 'Manual 6-Speed with Assist Clutch',
      seatingCapacity: 2,
      bodyType: 'Neo-Retro Roadster',
      priceRange: '₹2.80 Lakh',
      modelYear: 2026,
    ),
    VehicleModel(
      id: 'suzuki_access_125',
      name: 'Suzuki Access 125',
      brandId: 'suzuki',
      brandName: 'Suzuki',
      modelId: 'access_125',
      modelName: 'Access 125',
      variantId: 'ride_connect',
      variantName: 'Ride Connect Bluetooth Disc Alloy',
      type: 'motorcycle',
      fuelType: 'petrol',
      mileage: 48.0,
      tankCapacity: 5.0,
      engine: '124 cc Air-Cooled SEP',
      transmission: 'Automatic CVT',
      seatingCapacity: 2,
      bodyType: 'Scooter',
      priceRange: '₹90,500',
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

    // 1. High-performance, zero-latency local catalog search first (eliminates network calls)
    final localResults = _searchLocal(q, normFuel, type, limit);
    if (localResults.isNotEmpty || q.length < 3) {
      return localResults;
    }

    // 2. Fallback to backend search endpoint only if local catalog had no match for query >= 3 chars
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
      // Gracefully fall through
    }

    return localResults;
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
      VehicleBrand(id: 'ktm', name: 'KTM', country: 'Austria', type: 'motorcycle'),
      VehicleBrand(id: 'yamaha', name: 'Yamaha', country: 'Japan', type: 'motorcycle'),
      VehicleBrand(id: 'bajaj', name: 'Bajaj Auto', country: 'India', type: 'motorcycle'),
      VehicleBrand(id: 'tvs', name: 'TVS Motor', country: 'India', type: 'motorcycle'),
      VehicleBrand(id: 'hero', name: 'Hero MotoCorp', country: 'India', type: 'motorcycle'),
      VehicleBrand(id: 'honda_2w', name: 'Honda 2-Wheelers', country: 'Japan', type: 'motorcycle'),
      VehicleBrand(id: 'triumph', name: 'Triumph', country: 'UK', type: 'motorcycle'),
      VehicleBrand(id: 'harley_davidson', name: 'Harley-Davidson', country: 'USA', type: 'motorcycle'),
      VehicleBrand(id: 'suzuki_2w', name: 'Suzuki 2-Wheelers', country: 'Japan', type: 'motorcycle'),
      VehicleBrand(id: 'ola_electric', name: 'Ola Electric', country: 'India', type: 'motorcycle'),
      VehicleBrand(id: 'ather', name: 'Ather Energy', country: 'India', type: 'motorcycle'),
    ];
    if (type != null) {
      return all.where((b) => b.type == type).toList();
    }
    return all;
  }
}
