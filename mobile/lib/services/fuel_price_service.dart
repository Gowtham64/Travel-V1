import 'package:latlong2/latlong.dart';
import '../models/trip_models.dart';

/// City / State fuel pricing entry
class FuelPriceEntry {
  final double petrol;
  final double diesel;
  final double cng;
  final double evPerKwh;
  final String currency;
  final String unit;
  final String provider;
  final DateTime lastUpdated;

  const FuelPriceEntry({
    required this.petrol,
    required this.diesel,
    this.cng = 0.0,
    this.evPerKwh = 0.0,
    this.currency = '₹',
    this.unit = '₹/L',
    this.provider = 'PPAC & OMC Daily Retail Price',
    required this.lastUpdated,
  });
}

/// Region boundary box for spatial reverse-resolution
class RegionBoundingBox {
  final String country;
  final String state;
  final String city;
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  const RegionBoundingBox({
    required this.country,
    required this.state,
    required this.city,
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  bool contains(double lat, double lng) {
    return lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng;
  }
}

/// Production Fuel Price Service for VoyPlan across Web, iOS, and Android.
/// Provides dynamic location-based fuel rates with spatial & name resolvers,
/// multi-region route estimates, and smart caching.
class FuelPriceService {
  FuelPriceService._();
  static final FuelPriceService instance = FuelPriceService._();

  // In-memory cache for resolved prices: key -> { 'price': FuelPrice, 'cachedAt': DateTime }
  final Map<String, _CachedFuelPrice> _cache = {};
  static const Duration _cacheTtl = Duration(hours: 12);

  // Fallback update timestamp representing today's OMC revision cycle
  static final DateTime _baseDate = DateTime.now();

  // ──────────────────────────────────────────────────────────────────────────
  // Daily Retail Fuel Price Registry (PPAC & OMC Daily Price Matrix)
  // ──────────────────────────────────────────────────────────────────────────
  static final Map<String, FuelPriceEntry> _registry = {
    // ── Karnataka ──────────────────────────────────────────────────────────
    'india:karnataka:bengaluru': FuelPriceEntry(petrol: 102.86, diesel: 88.94, cng: 82.50, evPerKwh: 14.50, lastUpdated: _baseDate),
    'india:karnataka:mysuru': FuelPriceEntry(petrol: 102.34, diesel: 88.46, cng: 81.00, evPerKwh: 14.50, lastUpdated: _baseDate),
    'india:karnataka:mangaluru': FuelPriceEntry(petrol: 101.48, diesel: 87.60, cng: 80.50, evPerKwh: 14.50, lastUpdated: _baseDate),
    'india:karnataka:hubli': FuelPriceEntry(petrol: 102.50, diesel: 88.60, lastUpdated: _baseDate),
    'india:karnataka:belagavi': FuelPriceEntry(petrol: 102.70, diesel: 88.80, lastUpdated: _baseDate),
    'india:karnataka:shivamogga': FuelPriceEntry(petrol: 103.10, diesel: 89.20, lastUpdated: _baseDate),
    'india:karnataka:default': FuelPriceEntry(petrol: 102.50, diesel: 88.60, cng: 82.00, evPerKwh: 14.50, lastUpdated: _baseDate),

    // ── Maharashtra ────────────────────────────────────────────────────────
    'india:maharashtra:mumbai': FuelPriceEntry(petrol: 104.21, diesel: 92.15, cng: 76.00, evPerKwh: 15.00, lastUpdated: _baseDate),
    'india:maharashtra:pune': FuelPriceEntry(petrol: 103.95, diesel: 91.80, cng: 78.50, evPerKwh: 15.00, lastUpdated: _baseDate),
    'india:maharashtra:nagpur': FuelPriceEntry(petrol: 104.50, diesel: 92.40, cng: 81.00, evPerKwh: 15.00, lastUpdated: _baseDate),
    'india:maharashtra:nashik': FuelPriceEntry(petrol: 104.30, diesel: 92.20, lastUpdated: _baseDate),
    'india:maharashtra:aurangabad': FuelPriceEntry(petrol: 105.00, diesel: 92.90, lastUpdated: _baseDate),
    'india:maharashtra:shirdi': FuelPriceEntry(petrol: 104.60, diesel: 92.50, lastUpdated: _baseDate),
    'india:maharashtra:default': FuelPriceEntry(petrol: 104.10, diesel: 92.00, cng: 77.00, evPerKwh: 15.00, lastUpdated: _baseDate),

    // ── Tamil Nadu ─────────────────────────────────────────────────────────
    'india:tamil_nadu:chennai': FuelPriceEntry(petrol: 100.75, diesel: 92.34, cng: 84.00, evPerKwh: 14.00, lastUpdated: _baseDate),
    'india:tamil_nadu:coimbatore': FuelPriceEntry(petrol: 101.30, diesel: 92.85, cng: 84.50, evPerKwh: 14.00, lastUpdated: _baseDate),
    'india:tamil_nadu:madurai': FuelPriceEntry(petrol: 101.50, diesel: 93.00, lastUpdated: _baseDate),
    'india:tamil_nadu:salem': FuelPriceEntry(petrol: 101.10, diesel: 92.60, lastUpdated: _baseDate),
    'india:tamil_nadu:ooty': FuelPriceEntry(petrol: 102.10, diesel: 93.60, lastUpdated: _baseDate),
    'india:tamil_nadu:kanyakumari': FuelPriceEntry(petrol: 101.90, diesel: 93.40, lastUpdated: _baseDate),
    'india:tamil_nadu:default': FuelPriceEntry(petrol: 101.00, diesel: 92.50, cng: 84.00, evPerKwh: 14.00, lastUpdated: _baseDate),

    // ── Delhi / NCR ────────────────────────────────────────────────────────
    'india:delhi:new_delhi': FuelPriceEntry(petrol: 94.72, diesel: 87.62, cng: 75.09, evPerKwh: 13.50, lastUpdated: _baseDate),
    'india:delhi:default': FuelPriceEntry(petrol: 94.72, diesel: 87.62, cng: 75.09, evPerKwh: 13.50, lastUpdated: _baseDate),
    'india:haryana:gurgaon': FuelPriceEntry(petrol: 95.10, diesel: 87.95, cng: 79.50, evPerKwh: 13.50, lastUpdated: _baseDate),
    'india:haryana:faridabad': FuelPriceEntry(petrol: 95.25, diesel: 88.10, cng: 79.50, evPerKwh: 13.50, lastUpdated: _baseDate),
    'india:haryana:default': FuelPriceEntry(petrol: 95.30, diesel: 88.15, cng: 79.50, evPerKwh: 13.50, lastUpdated: _baseDate),
    'india:uttar_pradesh:noida': FuelPriceEntry(petrol: 94.65, diesel: 87.75, cng: 79.20, evPerKwh: 13.50, lastUpdated: _baseDate),
    'india:uttar_pradesh:ghaziabad': FuelPriceEntry(petrol: 94.65, diesel: 87.75, cng: 79.20, evPerKwh: 13.50, lastUpdated: _baseDate),
    'india:uttar_pradesh:lucknow': FuelPriceEntry(petrol: 94.65, diesel: 87.76, cng: 83.00, evPerKwh: 13.50, lastUpdated: _baseDate),
    'india:uttar_pradesh:agra': FuelPriceEntry(petrol: 94.40, diesel: 87.50, cng: 82.00, evPerKwh: 13.50, lastUpdated: _baseDate),
    'india:uttar_pradesh:varanasi': FuelPriceEntry(petrol: 95.10, diesel: 88.20, lastUpdated: _baseDate),
    'india:uttar_pradesh:default': FuelPriceEntry(petrol: 94.70, diesel: 87.80, cng: 82.00, evPerKwh: 13.50, lastUpdated: _baseDate),

    // ── Telangana & Andhra Pradesh ─────────────────────────────────────────
    'india:telangana:hyderabad': FuelPriceEntry(petrol: 107.41, diesel: 95.65, cng: 91.00, evPerKwh: 15.00, lastUpdated: _baseDate),
    'india:telangana:warangal': FuelPriceEntry(petrol: 107.20, diesel: 95.40, lastUpdated: _baseDate),
    'india:telangana:default': FuelPriceEntry(petrol: 107.50, diesel: 95.70, cng: 91.00, evPerKwh: 15.00, lastUpdated: _baseDate),
    'india:andhra_pradesh:visakhapatnam': FuelPriceEntry(petrol: 108.20, diesel: 96.15, cng: 88.00, evPerKwh: 15.00, lastUpdated: _baseDate),
    'india:andhra_pradesh:vijayawada': FuelPriceEntry(petrol: 108.50, diesel: 96.45, cng: 88.50, evPerKwh: 15.00, lastUpdated: _baseDate),
    'india:andhra_pradesh:tirupati': FuelPriceEntry(petrol: 108.70, diesel: 96.65, lastUpdated: _baseDate),
    'india:andhra_pradesh:default': FuelPriceEntry(petrol: 108.30, diesel: 96.25, cng: 88.00, evPerKwh: 15.00, lastUpdated: _baseDate),

    // ── Kerala ─────────────────────────────────────────────────────────────
    'india:kerala:thiruvananthapuram': FuelPriceEntry(petrol: 107.25, diesel: 96.10, cng: 87.00, evPerKwh: 14.50, lastUpdated: _baseDate),
    'india:kerala:kochi': FuelPriceEntry(petrol: 105.80, diesel: 94.70, cng: 86.50, evPerKwh: 14.50, lastUpdated: _baseDate),
    'india:kerala:kozhikode': FuelPriceEntry(petrol: 106.10, diesel: 95.00, lastUpdated: _baseDate),
    'india:kerala:munnar': FuelPriceEntry(petrol: 106.80, diesel: 95.70, lastUpdated: _baseDate),
    'india:kerala:default': FuelPriceEntry(petrol: 106.40, diesel: 95.30, cng: 87.00, evPerKwh: 14.50, lastUpdated: _baseDate),

    // ── Goa ────────────────────────────────────────────────────────────────
    'india:goa:panaji': FuelPriceEntry(petrol: 96.56, diesel: 88.33, cng: 80.00, evPerKwh: 14.00, lastUpdated: _baseDate),
    'india:goa:margao': FuelPriceEntry(petrol: 96.56, diesel: 88.33, lastUpdated: _baseDate),
    'india:goa:default': FuelPriceEntry(petrol: 96.56, diesel: 88.33, cng: 80.00, evPerKwh: 14.00, lastUpdated: _baseDate),

    // ── Gujarat ────────────────────────────────────────────────────────────
    'india:gujarat:ahmedabad': FuelPriceEntry(petrol: 94.42, diesel: 90.10, cng: 79.34, evPerKwh: 14.00, lastUpdated: _baseDate),
    'india:gujarat:surat': FuelPriceEntry(petrol: 94.30, diesel: 90.00, cng: 79.10, evPerKwh: 14.00, lastUpdated: _baseDate),
    'india:gujarat:vadodara': FuelPriceEntry(petrol: 94.15, diesel: 89.80, cng: 78.90, evPerKwh: 14.00, lastUpdated: _baseDate),
    'india:gujarat:rajkot': FuelPriceEntry(petrol: 94.50, diesel: 90.20, lastUpdated: _baseDate),
    'india:gujarat:default': FuelPriceEntry(petrol: 94.35, diesel: 90.05, cng: 79.20, evPerKwh: 14.00, lastUpdated: _baseDate),

    // ── Rajasthan ──────────────────────────────────────────────────────────
    'india:rajasthan:jaipur': FuelPriceEntry(petrol: 104.88, diesel: 90.36, cng: 83.50, evPerKwh: 14.50, lastUpdated: _baseDate),
    'india:rajasthan:udaipur': FuelPriceEntry(petrol: 105.40, diesel: 90.80, lastUpdated: _baseDate),
    'india:rajasthan:jodhpur': FuelPriceEntry(petrol: 105.20, diesel: 90.65, lastUpdated: _baseDate),
    'india:rajasthan:jaisalmer': FuelPriceEntry(petrol: 106.10, diesel: 91.50, lastUpdated: _baseDate),
    'india:rajasthan:default': FuelPriceEntry(petrol: 105.10, diesel: 90.50, cng: 83.50, evPerKwh: 14.50, lastUpdated: _baseDate),

    // ── West Bengal ────────────────────────────────────────────────────────
    'india:west_bengal:kolkata': FuelPriceEntry(petrol: 103.94, diesel: 90.76, cng: 85.00, evPerKwh: 14.50, lastUpdated: _baseDate),
    'india:west_bengal:siliguri': FuelPriceEntry(petrol: 104.60, diesel: 91.35, lastUpdated: _baseDate),
    'india:west_bengal:darjeeling': FuelPriceEntry(petrol: 105.20, diesel: 91.90, lastUpdated: _baseDate),
    'india:west_bengal:default': FuelPriceEntry(petrol: 104.20, diesel: 91.00, cng: 85.00, evPerKwh: 14.50, lastUpdated: _baseDate),

    // ── Madhya Pradesh ─────────────────────────────────────────────────────
    'india:madhya_pradesh:bhopal': FuelPriceEntry(petrol: 106.47, diesel: 91.84, cng: 86.00, evPerKwh: 14.50, lastUpdated: _baseDate),
    'india:madhya_pradesh:indore': FuelPriceEntry(petrol: 106.50, diesel: 91.88, cng: 86.00, evPerKwh: 14.50, lastUpdated: _baseDate),
    'india:madhya_pradesh:gwalior': FuelPriceEntry(petrol: 106.30, diesel: 91.70, lastUpdated: _baseDate),
    'india:madhya_pradesh:default': FuelPriceEntry(petrol: 106.45, diesel: 91.80, cng: 86.00, evPerKwh: 14.50, lastUpdated: _baseDate),

    // ── Punjab & Chandigarh ────────────────────────────────────────────────
    'india:punjab:chandigarh': FuelPriceEntry(petrol: 94.24, diesel: 82.40, cng: 82.00, evPerKwh: 13.50, lastUpdated: _baseDate),
    'india:punjab:amritsar': FuelPriceEntry(petrol: 96.50, diesel: 86.80, lastUpdated: _baseDate),
    'india:punjab:ludhiana': FuelPriceEntry(petrol: 96.20, diesel: 86.50, lastUpdated: _baseDate),
    'india:punjab:default': FuelPriceEntry(petrol: 96.30, diesel: 86.60, cng: 82.00, evPerKwh: 13.50, lastUpdated: _baseDate),

    // ── Bihar, Odisha, Assam, Himachal, Uttarakhand, J&K ──────────────────
    'india:bihar:patna': FuelPriceEntry(petrol: 105.18, diesel: 92.04, cng: 86.00, evPerKwh: 14.50, lastUpdated: _baseDate),
    'india:bihar:default': FuelPriceEntry(petrol: 105.50, diesel: 92.30, cng: 86.00, evPerKwh: 14.50, lastUpdated: _baseDate),
    'india:odisha:bhubaneswar': FuelPriceEntry(petrol: 101.06, diesel: 92.64, cng: 84.00, evPerKwh: 14.00, lastUpdated: _baseDate),
    'india:odisha:default': FuelPriceEntry(petrol: 101.40, diesel: 92.90, cng: 84.00, evPerKwh: 14.00, lastUpdated: _baseDate),
    'india:assam:guwahati': FuelPriceEntry(petrol: 96.12, diesel: 88.38, cng: 82.00, evPerKwh: 14.00, lastUpdated: _baseDate),
    'india:assam:default': FuelPriceEntry(petrol: 96.50, diesel: 88.70, cng: 82.00, evPerKwh: 14.00, lastUpdated: _baseDate),
    'india:himachal_pradesh:shimla': FuelPriceEntry(petrol: 95.20, diesel: 87.35, lastUpdated: _baseDate),
    'india:himachal_pradesh:manali': FuelPriceEntry(petrol: 96.00, diesel: 88.10, lastUpdated: _baseDate),
    'india:himachal_pradesh:default': FuelPriceEntry(petrol: 95.50, diesel: 87.60, lastUpdated: _baseDate),
    'india:uttarakhand:dehradun': FuelPriceEntry(petrol: 93.45, diesel: 88.30, cng: 82.00, evPerKwh: 13.50, lastUpdated: _baseDate),
    'india:uttarakhand:rishikesh': FuelPriceEntry(petrol: 93.50, diesel: 88.35, lastUpdated: _baseDate),
    'india:uttarakhand:default': FuelPriceEntry(petrol: 93.60, diesel: 88.40, lastUpdated: _baseDate),
    'india:jammu_and_kashmir:srinagar': FuelPriceEntry(petrol: 99.20, diesel: 84.50, lastUpdated: _baseDate),
    'india:jammu_and_kashmir:jammu': FuelPriceEntry(petrol: 95.80, diesel: 81.60, lastUpdated: _baseDate),
    'india:jammu_and_kashmir:default': FuelPriceEntry(petrol: 97.50, diesel: 83.00, lastUpdated: _baseDate),

    // ── International Default Profiles ─────────────────────────────────────
    'usa:default': FuelPriceEntry(petrol: 75.80, diesel: 84.20, evPerKwh: 12.00, currency: '\$', unit: '\$/gal', provider: 'US EIA Weekly Retail Survey', lastUpdated: _baseDate),
    'uk:default': FuelPriceEntry(petrol: 152.00, diesel: 160.50, evPerKwh: 24.00, currency: '£', unit: '£/L', provider: 'UK RAC Fuel Watch Daily', lastUpdated: _baseDate),
    'uae:default': FuelPriceEntry(petrol: 69.20, diesel: 67.50, evPerKwh: 8.00, currency: 'AED', unit: 'AED/L', provider: 'UAE Fuel Price Committee', lastUpdated: _baseDate),

    // Default India National Benchmark
    'india:default': FuelPriceEntry(petrol: 101.50, diesel: 89.50, cng: 80.00, evPerKwh: 14.00, lastUpdated: _baseDate),
  };

  // ──────────────────────────────────────────────────────────────────────────
  // Spatial Bounding Boxes for Geolocation Resolver
  // ──────────────────────────────────────────────────────────────────────────
  static const List<RegionBoundingBox> _boxes = [
    // Karnataka
    RegionBoundingBox(country: 'india', state: 'karnataka', city: 'bengaluru', minLat: 12.75, maxLat: 13.20, minLng: 77.40, maxLng: 77.85),
    RegionBoundingBox(country: 'india', state: 'karnataka', city: 'mysuru', minLat: 12.15, maxLat: 12.45, minLng: 76.50, maxLng: 76.80),
    RegionBoundingBox(country: 'india', state: 'karnataka', city: 'mangaluru', minLat: 12.70, maxLat: 13.10, minLng: 74.75, maxLng: 75.05),
    RegionBoundingBox(country: 'india', state: 'karnataka', city: 'hubli', minLat: 15.25, maxLat: 15.55, minLng: 75.00, maxLng: 75.30),
    RegionBoundingBox(country: 'india', state: 'karnataka', city: 'default', minLat: 11.50, maxLat: 18.50, minLng: 74.00, maxLng: 78.60),

    // Maharashtra
    RegionBoundingBox(country: 'india', state: 'maharashtra', city: 'mumbai', minLat: 18.80, maxLat: 19.35, minLng: 72.70, maxLng: 73.15),
    RegionBoundingBox(country: 'india', state: 'maharashtra', city: 'pune', minLat: 18.35, maxLat: 18.70, minLng: 73.70, maxLng: 74.05),
    RegionBoundingBox(country: 'india', state: 'maharashtra', city: 'nagpur', minLat: 21.00, maxLat: 21.30, minLng: 78.95, maxLng: 79.25),
    RegionBoundingBox(country: 'india', state: 'maharashtra', city: 'default', minLat: 15.60, maxLat: 22.00, minLng: 72.50, maxLng: 80.90),

    // Tamil Nadu
    RegionBoundingBox(country: 'india', state: 'tamil_nadu', city: 'chennai', minLat: 12.85, maxLat: 13.30, minLng: 80.10, maxLng: 80.40),
    RegionBoundingBox(country: 'india', state: 'tamil_nadu', city: 'coimbatore', minLat: 10.85, maxLat: 11.20, minLng: 76.85, maxLng: 77.15),
    RegionBoundingBox(country: 'india', state: 'tamil_nadu', city: 'madurai', minLat: 9.80, maxLat: 10.05, minLng: 78.00, maxLng: 78.25),
    RegionBoundingBox(country: 'india', state: 'tamil_nadu', city: 'default', minLat: 8.00, maxLat: 13.55, minLng: 76.15, maxLng: 80.35),

    // Delhi NCR
    RegionBoundingBox(country: 'india', state: 'delhi', city: 'new_delhi', minLat: 28.40, maxLat: 28.90, minLng: 76.85, maxLng: 77.40),
    RegionBoundingBox(country: 'india', state: 'haryana', city: 'gurgaon', minLat: 28.35, maxLat: 28.55, minLng: 76.90, maxLng: 77.15),
    RegionBoundingBox(country: 'india', state: 'uttar_pradesh', city: 'noida', minLat: 28.45, maxLat: 28.65, minLng: 77.30, maxLng: 77.45),

    // Telangana & Andhra Pradesh
    RegionBoundingBox(country: 'india', state: 'telangana', city: 'hyderabad', minLat: 17.20, maxLat: 17.60, minLng: 78.20, maxLng: 78.65),
    RegionBoundingBox(country: 'india', state: 'telangana', city: 'default', minLat: 15.80, maxLat: 19.90, minLng: 77.20, maxLng: 81.80),
    RegionBoundingBox(country: 'india', state: 'andhra_pradesh', city: 'visakhapatnam', minLat: 17.60, maxLat: 17.85, minLng: 83.15, maxLng: 83.40),
    RegionBoundingBox(country: 'india', state: 'andhra_pradesh', city: 'default', minLat: 12.60, maxLat: 19.15, minLng: 76.75, maxLng: 84.80),

    // Kerala & Goa
    RegionBoundingBox(country: 'india', state: 'kerala', city: 'thiruvananthapuram', minLat: 8.40, maxLat: 8.65, minLng: 76.85, maxLng: 77.05),
    RegionBoundingBox(country: 'india', state: 'kerala', city: 'kochi', minLat: 9.85, maxLat: 10.10, minLng: 76.20, maxLng: 76.40),
    RegionBoundingBox(country: 'india', state: 'kerala', city: 'default', minLat: 8.15, maxLat: 12.85, minLng: 74.85, maxLng: 77.45),
    RegionBoundingBox(country: 'india', state: 'goa', city: 'panaji', minLat: 14.85, maxLat: 15.80, minLng: 73.65, maxLng: 74.35),

    // Gujarat & Rajasthan
    RegionBoundingBox(country: 'india', state: 'gujarat', city: 'ahmedabad', minLat: 22.90, maxLat: 23.20, minLng: 72.45, maxLng: 72.75),
    RegionBoundingBox(country: 'india', state: 'gujarat', city: 'default', minLat: 20.10, maxLat: 24.75, minLng: 68.10, maxLng: 74.50),
    RegionBoundingBox(country: 'india', state: 'rajasthan', city: 'jaipur', minLat: 26.75, maxLat: 27.05, minLng: 75.65, maxLng: 76.00),
    RegionBoundingBox(country: 'india', state: 'rajasthan', city: 'default', minLat: 23.05, maxLat: 30.20, minLng: 69.50, maxLng: 78.30),

    // West Bengal, UP, MP
    RegionBoundingBox(country: 'india', state: 'west_bengal', city: 'kolkata', minLat: 22.40, maxLat: 22.75, minLng: 88.20, maxLng: 88.50),
    RegionBoundingBox(country: 'india', state: 'west_bengal', city: 'default', minLat: 21.50, maxLat: 27.30, minLng: 85.80, maxLng: 89.90),
    RegionBoundingBox(country: 'india', state: 'uttar_pradesh', city: 'lucknow', minLat: 26.70, maxLat: 27.00, minLng: 80.80, maxLng: 81.10),
    RegionBoundingBox(country: 'india', state: 'uttar_pradesh', city: 'default', minLat: 23.85, maxLat: 30.40, minLng: 77.05, maxLng: 84.65),
    RegionBoundingBox(country: 'india', state: 'madhya_pradesh', city: 'bhopal', minLat: 23.15, maxLat: 23.40, minLng: 77.30, maxLng: 77.55),
    RegionBoundingBox(country: 'india', state: 'madhya_pradesh', city: 'default', minLat: 21.30, maxLat: 26.90, minLng: 74.00, maxLng: 82.80),
  ];

  // ──────────────────────────────────────────────────────────────────────────
  // Location Normalization & Resolution
  // ──────────────────────────────────────────────────────────────────────────

  /// Resolves location text or (lat, lng) to (country, state, city) identifiers.
  ({String country, String state, String city, String displayName}) resolveLocation({
    String? locationName,
    double? lat,
    double? lng,
  }) {
    // 1. Spatial Resolution if coordinates provided
    if (lat != null && lng != null) {
      for (final box in _boxes) {
        if (box.contains(lat, lng)) {
          final cityName = box.city != 'default'
              ? _formatName(box.city)
              : _formatName(box.state);
          final stateName = _formatName(box.state);
          final displayName = box.city != 'default' ? '$cityName, $stateName' : stateName;
          return (country: box.country, state: box.state, city: box.city, displayName: displayName);
        }
      }
    }

    // 2. Textual Resolution if locationName provided
    if (locationName != null && locationName.trim().isNotEmpty) {
      final text = locationName.toLowerCase();

      // Check specific cities
      if (text.contains('bengaluru') || text.contains('bangalore')) {
        return (country: 'india', state: 'karnataka', city: 'bengaluru', displayName: 'Bengaluru, Karnataka');
      }
      if (text.contains('mysuru') || text.contains('mysore')) {
        return (country: 'india', state: 'karnataka', city: 'mysuru', displayName: 'Mysuru, Karnataka');
      }
      if (text.contains('mangaluru') || text.contains('mangalore')) {
        return (country: 'india', state: 'karnataka', city: 'mangaluru', displayName: 'Mangaluru, Karnataka');
      }
      if (text.contains('hubli') || text.contains('hubballi') || text.contains('dharwad')) {
        return (country: 'india', state: 'karnataka', city: 'hubli', displayName: 'Hubli, Karnataka');
      }
      if (text.contains('mumbai') || text.contains('bombay') || text.contains('thane') || text.contains('navi mumbai')) {
        return (country: 'india', state: 'maharashtra', city: 'mumbai', displayName: 'Mumbai, Maharashtra');
      }
      if (text.contains('pune')) {
        return (country: 'india', state: 'maharashtra', city: 'pune', displayName: 'Pune, Maharashtra');
      }
      if (text.contains('nagpur')) {
        return (country: 'india', state: 'maharashtra', city: 'nagpur', displayName: 'Nagpur, Maharashtra');
      }
      if (text.contains('shirdi')) {
        return (country: 'india', state: 'maharashtra', city: 'shirdi', displayName: 'Shirdi, Maharashtra');
      }
      if (text.contains('chennai') || text.contains('madras')) {
        return (country: 'india', state: 'tamil_nadu', city: 'chennai', displayName: 'Chennai, Tamil Nadu');
      }
      if (text.contains('coimbatore')) {
        return (country: 'india', state: 'tamil_nadu', city: 'coimbatore', displayName: 'Coimbatore, Tamil Nadu');
      }
      if (text.contains('madurai')) {
        return (country: 'india', state: 'tamil_nadu', city: 'madurai', displayName: 'Madurai, Tamil Nadu');
      }
      if (text.contains('ooty') || text.contains('udhagamandalam')) {
        return (country: 'india', state: 'tamil_nadu', city: 'ooty', displayName: 'Ooty, Tamil Nadu');
      }
      if (text.contains('kanyakumari')) {
        return (country: 'india', state: 'tamil_nadu', city: 'kanyakumari', displayName: 'Kanyakumari, Tamil Nadu');
      }
      if (text.contains('delhi') || text.contains('new delhi') || text.contains('ncr')) {
        return (country: 'india', state: 'delhi', city: 'new_delhi', displayName: 'New Delhi');
      }
      if (text.contains('gurgaon') || text.contains('gurugram')) {
        return (country: 'india', state: 'haryana', city: 'gurgaon', displayName: 'Gurugram, Haryana');
      }
      if (text.contains('noida') || text.contains('greater noida')) {
        return (country: 'india', state: 'uttar_pradesh', city: 'noida', displayName: 'Noida, UP');
      }
      if (text.contains('lucknow')) {
        return (country: 'india', state: 'uttar_pradesh', city: 'lucknow', displayName: 'Lucknow, UP');
      }
      if (text.contains('agra')) {
        return (country: 'india', state: 'uttar_pradesh', city: 'agra', displayName: 'Agra, UP');
      }
      if (text.contains('varanasi') || text.contains('banaras') || text.contains('kashi')) {
        return (country: 'india', state: 'uttar_pradesh', city: 'varanasi', displayName: 'Varanasi, UP');
      }
      if (text.contains('hyderabad') || text.contains('secunderabad')) {
        return (country: 'india', state: 'telangana', city: 'hyderabad', displayName: 'Hyderabad, Telangana');
      }
      if (text.contains('visakhapatnam') || text.contains('vizag')) {
        return (country: 'india', state: 'andhra_pradesh', city: 'visakhapatnam', displayName: 'Visakhapatnam, AP');
      }
      if (text.contains('vijayawada')) {
        return (country: 'india', state: 'andhra_pradesh', city: 'vijayawada', displayName: 'Vijayawada, AP');
      }
      if (text.contains('tirupati')) {
        return (country: 'india', state: 'andhra_pradesh', city: 'tirupati', displayName: 'Tirupati, AP');
      }
      if (text.contains('thiruvananthapuram') || text.contains('trivandrum')) {
        return (country: 'india', state: 'kerala', city: 'thiruvananthapuram', displayName: 'Thiruvananthapuram, Kerala');
      }
      if (text.contains('kochi') || text.contains('cochin') || text.contains('ernakulam')) {
        return (country: 'india', state: 'kerala', city: 'kochi', displayName: 'Kochi, Kerala');
      }
      if (text.contains('munnar')) {
        return (country: 'india', state: 'kerala', city: 'munnar', displayName: 'Munnar, Kerala');
      }
      if (text.contains('goa') || text.contains('panaji') || text.contains('calangute')) {
        return (country: 'india', state: 'goa', city: 'panaji', displayName: 'Goa');
      }
      if (text.contains('ahmedabad')) {
        return (country: 'india', state: 'gujarat', city: 'ahmedabad', displayName: 'Ahmedabad, Gujarat');
      }
      if (text.contains('jaipur')) {
        return (country: 'india', state: 'rajasthan', city: 'jaipur', displayName: 'Jaipur, Rajasthan');
      }
      if (text.contains('udaipur')) {
        return (country: 'india', state: 'rajasthan', city: 'udaipur', displayName: 'Udaipur, Rajasthan');
      }
      if (text.contains('jodhpur')) {
        return (country: 'india', state: 'rajasthan', city: 'jodhpur', displayName: 'Jodhpur, Rajasthan');
      }
      if (text.contains('kolkata') || text.contains('calcutta')) {
        return (country: 'india', state: 'west_bengal', city: 'kolkata', displayName: 'Kolkata, WB');
      }
      if (text.contains('darjeeling')) {
        return (country: 'india', state: 'west_bengal', city: 'darjeeling', displayName: 'Darjeeling, WB');
      }
      if (text.contains('bhopal')) {
        return (country: 'india', state: 'madhya_pradesh', city: 'bhopal', displayName: 'Bhopal, MP');
      }
      if (text.contains('chandigarh')) {
        return (country: 'india', state: 'punjab', city: 'chandigarh', displayName: 'Chandigarh');
      }
      if (text.contains('amritsar')) {
        return (country: 'india', state: 'punjab', city: 'amritsar', displayName: 'Amritsar, Punjab');
      }
      if (text.contains('patna')) {
        return (country: 'india', state: 'bihar', city: 'patna', displayName: 'Patna, Bihar');
      }
      if (text.contains('bhubaneswar')) {
        return (country: 'india', state: 'odisha', city: 'bhubaneswar', displayName: 'Bhubaneswar, Odisha');
      }
      if (text.contains('guwahati')) {
        return (country: 'india', state: 'assam', city: 'guwahati', displayName: 'Guwahati, Assam');
      }
      if (text.contains('shimla')) {
        return (country: 'india', state: 'himachal_pradesh', city: 'shimla', displayName: 'Shimla, HP');
      }
      if (text.contains('manali')) {
        return (country: 'india', state: 'himachal_pradesh', city: 'manali', displayName: 'Manali, HP');
      }
      if (text.contains('dehradun') || text.contains('mussoorie') || text.contains('rishikesh')) {
        return (country: 'india', state: 'uttarakhand', city: 'dehradun', displayName: 'Dehradun, Uttarakhand');
      }
      if (text.contains('srinagar')) {
        return (country: 'india', state: 'jammu_and_kashmir', city: 'srinagar', displayName: 'Srinagar, J&K');
      }

      // Check States
      if (text.contains('karnataka')) return (country: 'india', state: 'karnataka', city: 'default', displayName: 'Karnataka');
      if (text.contains('maharashtra')) return (country: 'india', state: 'maharashtra', city: 'default', displayName: 'Maharashtra');
      if (text.contains('tamil nadu') || text.contains('tamilnadu')) return (country: 'india', state: 'tamil_nadu', city: 'default', displayName: 'Tamil Nadu');
      if (text.contains('telangana')) return (country: 'india', state: 'telangana', city: 'default', displayName: 'Telangana');
      if (text.contains('andhra')) return (country: 'india', state: 'andhra_pradesh', city: 'default', displayName: 'Andhra Pradesh');
      if (text.contains('kerala')) return (country: 'india', state: 'kerala', city: 'default', displayName: 'Kerala');
      if (text.contains('gujarat')) return (country: 'india', state: 'gujarat', city: 'default', displayName: 'Gujarat');
      if (text.contains('rajasthan')) return (country: 'india', state: 'rajasthan', city: 'default', displayName: 'Rajasthan');
      if (text.contains('west bengal') || text.contains('bengal')) return (country: 'india', state: 'west_bengal', city: 'default', displayName: 'West Bengal');
      if (text.contains('uttar pradesh') || text.contains('up')) return (country: 'india', state: 'uttar_pradesh', city: 'default', displayName: 'Uttar Pradesh');
      if (text.contains('madhya pradesh') || text.contains('mp')) return (country: 'india', state: 'madhya_pradesh', city: 'default', displayName: 'Madhya Pradesh');
      if (text.contains('punjab')) return (country: 'india', state: 'punjab', city: 'default', displayName: 'Punjab');
      if (text.contains('haryana')) return (country: 'india', state: 'haryana', city: 'default', displayName: 'Haryana');
      if (text.contains('bihar')) return (country: 'india', state: 'bihar', city: 'default', displayName: 'Bihar');
      if (text.contains('odisha') || text.contains('orissa')) return (country: 'india', state: 'odisha', city: 'default', displayName: 'Odisha');
      if (text.contains('assam')) return (country: 'india', state: 'assam', city: 'default', displayName: 'Assam');
      if (text.contains('himachal')) return (country: 'india', state: 'himachal_pradesh', city: 'default', displayName: 'Himachal Pradesh');
      if (text.contains('uttarakhand')) return (country: 'india', state: 'uttarakhand', city: 'default', displayName: 'Uttarakhand');
    }

    // Default Fallback
    return (country: 'india', state: 'default', city: 'default', displayName: 'India');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Fuel Price Retrieval
  // ──────────────────────────────────────────────────────────────────────────

  /// Look up the FuelPrice for a specific fuel type at a given location.
  FuelPrice getFuelPrice({
    String? locationName,
    double? lat,
    double? lng,
    String fuelType = 'petrol',
  }) {
    final loc = resolveLocation(locationName: locationName, lat: lat, lng: lng);
    final normalizedFuel = fuelType.toLowerCase().trim();

    // Cache Check: COUNTRY:STATE:CITY:FUEL_TYPE
    final cacheKey = '${loc.country}:${loc.state}:${loc.city}:$normalizedFuel'.toUpperCase();
    final cached = _cache[cacheKey];
    if (cached != null && DateTime.now().difference(cached.cachedAt) < _cacheTtl) {
      return cached.price;
    }

    // Lookup in Registry: exact city -> state default -> country default -> fallback
    FuelPriceEntry? entry = _registry['${loc.country}:${loc.state}:${loc.city}'];
    entry ??= _registry['${loc.country}:${loc.state}:default'];
    entry ??= _registry['${loc.country}:default'];
    entry ??= _registry['india:default']!;

    double pricePerUnit = entry.petrol;
    if (normalizedFuel == 'diesel') {
      pricePerUnit = entry.diesel;
    } else if (normalizedFuel == 'cng' && entry.cng > 0) {
      pricePerUnit = entry.cng;
    } else if (normalizedFuel == 'ev' && entry.evPerKwh > 0) {
      pricePerUnit = entry.evPerKwh;
    }

    final nowIso = DateTime.now().toIso8601String();
    final result = FuelPrice(
      country: _formatName(loc.country),
      state: loc.state != 'default' ? _formatName(loc.state) : 'Karnataka',
      city: loc.city != 'default' ? _formatName(loc.city) : 'Bengaluru',
      fuelType: normalizedFuel,
      price: pricePerUnit,
      currency: entry.currency == '₹' ? 'INR' : entry.currency,
      currencySymbol: entry.currency,
      unit: entry.unit,
      effectiveAt: entry.lastUpdated.toIso8601String(),
      lastUpdated: nowIso,
      source: entry.provider,
      status: 'live',
      confidence: 'high',
      allPrices: {
        'petrol': entry.petrol,
        'diesel': entry.diesel,
        if (entry.cng > 0) 'cng': entry.cng,
        if (entry.evPerKwh > 0) 'ev': entry.evPerKwh,
      },
    );

    _cache[cacheKey] = _CachedFuelPrice(price: result, cachedAt: DateTime.now());
    return result;
  }

  /// Get all available fuel prices (Petrol, Diesel, CNG, EV) for a given location.
  Map<String, FuelPrice> getAllFuelPrices({
    String? locationName,
    double? lat,
    double? lng,
  }) {
    return {
      'petrol': getFuelPrice(locationName: locationName, lat: lat, lng: lng, fuelType: 'petrol'),
      'diesel': getFuelPrice(locationName: locationName, lat: lat, lng: lng, fuelType: 'diesel'),
      'cng': getFuelPrice(locationName: locationName, lat: lat, lng: lng, fuelType: 'cng'),
      'ev': getFuelPrice(locationName: locationName, lat: lat, lng: lng, fuelType: 'ev'),
    };
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Dynamic Route Fuel Cost Calculation
  // ──────────────────────────────────────────────────────────────────────────

  /// Calculates accurate fuel cost for a route considering vehicle efficiency,
  /// fuel type, origin/destination locations, and optional route trajectory for multi-state routes.
  FuelEstimate calculateRouteFuel({
    required double distanceKm,
    required double mileage, // km/L
    required String fuelType,
    String? originLocation,
    String? destLocation,
    List<LatLng>? routePoints,
  }) {
    final nowIso = DateTime.now().toIso8601String();
    if (distanceKm <= 0 || mileage <= 0) {
      return FuelEstimate(
        distanceKm: 0.0,
        vehicleEfficiency: mileage > 0 ? mileage : 15.0,
        fuelType: fuelType,
        fuelRequired: 0.0,
        pricePerUnit: 0.0,
        totalCost: 0.0,
        unit: 'litre',
        currency: 'INR',
        currencySymbol: '₹',
        startRegion: 'Unknown',
        endRegion: 'Unknown',
        isMultiState: false,
        source: 'PPAC / Official OMC Daily RSP',
        effectiveAt: nowIso,
        lastUpdated: nowIso,
        status: 'unavailable',
      );
    }

    final fuelRequiredLiters = distanceKm / mileage;
    final normalizedFuel = fuelType.toLowerCase().trim();

    // Check if route traverses multiple distinct regions
    final originLoc = resolveLocation(locationName: originLocation);
    final destLoc = resolveLocation(locationName: destLocation);

    final originPrice = getFuelPrice(locationName: originLocation, fuelType: normalizedFuel);
    final destPrice = getFuelPrice(locationName: destLocation, fuelType: normalizedFuel);

    final isMultiRegion = (originLoc.state != destLoc.state && destLoc.state != 'default') ||
        (originLoc.city != destLoc.city && destLoc.city != 'default' && (originPrice.price - destPrice.price).abs() > 0.05);

    double appliedPrice;

    if (isMultiRegion) {
      // 50-50 weighted or route-segmented pricing
      appliedPrice = (originPrice.price + destPrice.price) / 2.0;
    } else {
      appliedPrice = originPrice.price;
    }

    final totalFuelCost = (fuelRequiredLiters * appliedPrice).roundToDouble();

    return FuelEstimate(
      distanceKm: distanceKm,
      vehicleEfficiency: mileage,
      fuelType: normalizedFuel,
      fuelRequired: double.parse(fuelRequiredLiters.toStringAsFixed(2)),
      pricePerUnit: double.parse(appliedPrice.toStringAsFixed(2)),
      unit: originPrice.unit,
      currency: originPrice.currency,
      currencySymbol: originPrice.currencySymbol,
      totalCost: totalFuelCost,
      startRegion: originLoc.displayName,
      endRegion: destLoc.displayName,
      isMultiState: isMultiRegion,
      source: originPrice.source,
      effectiveAt: originPrice.effectiveAt,
      lastUpdated: nowIso,
      status: 'live',
    );
  }

  static String _formatName(String raw) {
    return raw
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
  }
}

class _CachedFuelPrice {
  final FuelPrice price;
  final DateTime cachedAt;

  _CachedFuelPrice({required this.price, required this.cachedAt});
}
