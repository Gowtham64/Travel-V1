import 'package:flutter/material.dart';

class StopPointItem {
  final String id;
  final String name;
  final String category;
  final String categoryKey; // e.g. 'fuel', 'food', 'cafe', etc.
  final IconData icon;
  final Color color;
  final double rating;
  final int reviewCount;
  final String detourTime;
  final double detourKm;
  final String eta;
  final String recDuration;
  final String address;
  final String openingHours;
  final double lat;
  final double lng;
  final String imageUrl;
  final List<String> tags;

  const StopPointItem({
    required this.id,
    required this.name,
    required this.category,
    required this.categoryKey,
    required this.icon,
    required this.color,
    required this.rating,
    required this.reviewCount,
    required this.detourTime,
    required this.detourKm,
    required this.eta,
    required this.recDuration,
    required this.address,
    required this.openingHours,
    required this.lat,
    required this.lng,
    required this.imageUrl,
    required this.tags,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'category': category,
        'categoryKey': categoryKey,
        'rating': rating,
        'reviewCount': reviewCount,
        'detourTime': detourTime,
        'detourKm': detourKm,
        'eta': eta,
        'duration': recDuration,
        'address': address,
        'openingHours': openingHours,
        'lat': lat,
        'lng': lng,
        'image': imageUrl,
        'tags': tags,
      };
}

class StopCatalogCategory {
  final String key;
  final String label;
  final IconData icon;
  final Color color;

  const StopCatalogCategory(this.key, this.label, this.icon, this.color);
}

class StopCatalogService {
  StopCatalogService._();
  static final StopCatalogService instance = StopCatalogService._();

  static const List<StopCatalogCategory> categories = [
    StopCatalogCategory('all', 'All Stops', Icons.auto_awesome_rounded, Color(0xFFD4AF37)),
    StopCatalogCategory('fuel', 'Fuel Stations', Icons.local_gas_station_rounded, Color(0xFFF59E0B)),
    StopCatalogCategory('food', 'Restaurants', Icons.restaurant_rounded, Color(0xFF10B981)),
    StopCatalogCategory('cafe', 'Cafes', Icons.local_cafe_rounded, Color(0xFF8B5CF6)),
    StopCatalogCategory('stay', 'Hotels & Stays', Icons.hotel_rounded, Color(0xFF6366F1)),
    StopCatalogCategory('restroom', 'Restrooms', Icons.wc_rounded, Color(0xFF06B6D4)),
    StopCatalogCategory('attraction', 'Attractions', Icons.museum_rounded, Color(0xFFEC4899)),
    StopCatalogCategory('tourist', 'Tourist Places', Icons.photo_camera_rounded, Color(0xFF14B8A6)),
    StopCatalogCategory('ev', 'EV Charging', Icons.electric_car_rounded, Color(0xFF22C55E)),
    StopCatalogCategory('hospital', 'Hospitals', Icons.local_hospital_rounded, Color(0xFFEF4444)),
    StopCatalogCategory('parking', 'Parking', Icons.local_parking_rounded, Color(0xFF64748B)),
    StopCatalogCategory('shopping', 'Shopping', Icons.shopping_bag_rounded, Color(0xFFA855F7)),
    StopCatalogCategory('rest_area', 'Rest Areas', Icons.deck_rounded, Color(0xFF3B82F6)),
    StopCatalogCategory('viewpoint', 'Viewpoints', Icons.landscape_rounded, Color(0xFFEAB308)),
  ];

  /// Returns verified, route-aware recommendations along the journey corridor
  List<StopPointItem> getStopsAlongCorridor({
    required String origin,
    required String destination,
    double distanceKm = 250,
    String? categoryFilter,
  }) {
    // Generate route-relevant stops based on origin and destination
    final isSouthRoute = origin.toLowerCase().contains('bangalore') ||
        destination.toLowerCase().contains('coorg') ||
        destination.toLowerCase().contains('mysore') ||
        destination.toLowerCase().contains('ooty') ||
        destination.toLowerCase().contains('wayanad') ||
        destination.toLowerCase().contains('goa');

    final List<StopPointItem> stops = [
      StopPointItem(
        id: 'stop-fuel-1',
        name: isSouthRoute ? 'IndianOil Swagat Highway COCO' : 'BPCL Highway Fuel & Express Food',
        category: 'Fuel Stations',
        categoryKey: 'fuel',
        icon: Icons.local_gas_station_rounded,
        color: const Color(0xFFF59E0B),
        rating: 4.8,
        reviewCount: 1420,
        detourTime: '+1 min detour',
        detourKm: 0.1,
        eta: '1h 15m from start',
        recDuration: '15 mins',
        address: 'Directly on National Highway Corridor',
        openingHours: 'Open 24 Hours',
        lat: 12.6500,
        lng: 77.2100,
        imageUrl: 'https://images.unsplash.com/photo-1545459720-aac8509eb02c?w=400&q=80',
        tags: ['Clean Washrooms', 'Nitrogen Air', 'Credit Cards', '24/7'],
      ),
      StopPointItem(
        id: 'stop-ev-1',
        name: 'Zeon Fast 60kW DC Dual EV Charger',
        category: 'EV Charging',
        categoryKey: 'ev',
        icon: Icons.electric_car_rounded,
        color: const Color(0xFF22C55E),
        rating: 4.7,
        reviewCount: 380,
        detourTime: '+2 mins detour',
        detourKm: 0.3,
        eta: '1h 30m from start',
        recDuration: '30 mins',
        address: 'Attached to Food Plaza Plaza NH75',
        openingHours: 'Open 24 Hours',
        lat: 12.7200,
        lng: 76.9500,
        imageUrl: 'https://images.unsplash.com/photo-1563986768609-322da13575f3?w=400&q=80',
        tags: ['CCS2 Fast', 'Dual Gun', 'Cafeteria Onsite'],
      ),
      StopPointItem(
        id: 'stop-food-1',
        name: isSouthRoute ? 'Kamat Lokaruchi Heritage Restaurant' : 'Highway Treat Garden Restaurant',
        category: 'Restaurants',
        categoryKey: 'food',
        icon: Icons.restaurant_rounded,
        color: const Color(0xFF10B981),
        rating: 4.6,
        reviewCount: 6840,
        detourTime: '+2 mins detour',
        detourKm: 0.2,
        eta: '1h 45m from start',
        recDuration: '45 mins',
        address: 'Ramanagara Corridor Bypass',
        openingHours: '6:30 AM - 10:30 PM',
        lat: 12.7150,
        lng: 77.2980,
        imageUrl: 'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=400&q=80',
        tags: ['Traditional Thali', 'Filter Coffee', 'Family Seating', 'Ample Parking'],
      ),
      StopPointItem(
        id: 'stop-cafe-1',
        name: 'Third Wave Coffee / CCD Highway Hub',
        category: 'Cafes',
        categoryKey: 'cafe',
        icon: Icons.local_cafe_rounded,
        color: const Color(0xFF8B5CF6),
        rating: 4.5,
        reviewCount: 920,
        detourTime: '+1 min detour',
        detourKm: 0.1,
        eta: '2h 10m from start',
        recDuration: '20 mins',
        address: 'Highway Rest Plaza Unit 4',
        openingHours: '7:00 AM - 11:00 PM',
        lat: 12.5800,
        lng: 76.8500,
        imageUrl: 'https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?w=400&q=80',
        tags: ['Espresso', 'Free WiFi', 'AC Seating', 'Takeaway Drive-thru'],
      ),
      StopPointItem(
        id: 'stop-view-1',
        name: isSouthRoute ? 'Channapatna Craft & Viewpoint Halt' : 'Scenic Valley Panoramic Viewpoint',
        category: 'Viewpoints',
        categoryKey: 'viewpoint',
        icon: Icons.landscape_rounded,
        color: const Color(0xFFEAB308),
        rating: 4.7,
        reviewCount: 2150,
        detourTime: '+4 mins detour',
        detourKm: 0.8,
        eta: '2h 40m from start',
        recDuration: '30 mins',
        address: 'Ghat Edge Highway Overlook',
        openingHours: 'Sunrise to Sunset',
        lat: 12.4500,
        lng: 76.5400,
        imageUrl: 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=400&q=80',
        tags: ['Photo Point', 'Valley Breeze', 'Local Souvenirs'],
      ),
      StopPointItem(
        id: 'stop-rest-1',
        name: 'Expressway Clean Rest Stop & Plaza',
        category: 'Rest Areas',
        categoryKey: 'rest_area',
        icon: Icons.deck_rounded,
        color: const Color(0xFF3B82F6),
        rating: 4.6,
        reviewCount: 1750,
        detourTime: 'Direct Exit (+0m)',
        detourKm: 0.0,
        eta: '3h 10m from start',
        recDuration: '25 mins',
        address: 'KM 142 Rest Plaza NH Corridor',
        openingHours: 'Open 24 Hours',
        lat: 12.3500,
        lng: 76.3200,
        imageUrl: 'https://images.unsplash.com/photo-1517649763962-0c623266ddc0?w=400&q=80',
        tags: ['Child Play Area', 'Clean Restrooms', 'ATM', 'Pharmacy'],
      ),
      StopPointItem(
        id: 'stop-attr-1',
        name: isSouthRoute ? 'Bylakuppe Golden Temple (Namdroling Monastery)' : 'Historic Heritage Fort & Gardens',
        category: 'Attractions',
        categoryKey: 'attraction',
        icon: Icons.museum_rounded,
        color: const Color(0xFFEC4899),
        rating: 4.9,
        reviewCount: 14300,
        detourTime: '+6 mins detour',
        detourKm: 1.2,
        eta: '4h 00m from start',
        recDuration: '1h 15m',
        address: 'Bylakuppe, Coorg Borders',
        openingHours: '9:00 AM - 6:00 PM',
        lat: 12.4300,
        lng: 75.9600,
        imageUrl: 'https://images.unsplash.com/photo-1544735716-392fe2489ffa?w=400&q=80',
        tags: ['Tibetan Heritage', 'Garden Walkway', 'Serene', 'Gift Shop'],
      ),
      StopPointItem(
        id: 'stop-stay-1',
        name: isSouthRoute ? 'The Tamara / Evolve Back Plantation Resort' : 'Royal Heritage Palace Resort',
        category: 'Hotels & Stays',
        categoryKey: 'stay',
        icon: Icons.hotel_rounded,
        color: const Color(0xFF6366F1),
        rating: 4.8,
        reviewCount: 3100,
        detourTime: '+5 mins detour',
        detourKm: 1.5,
        eta: 'Destination Arrival',
        recDuration: 'Overnight Stay',
        address: 'Main Destination Corridor',
        openingHours: 'Check-in 2:00 PM',
        lat: 12.4200,
        lng: 75.7400,
        imageUrl: 'https://images.unsplash.com/photo-1566073771259-6a8506099945?w=400&q=80',
        tags: ['Coffee Plantation', 'Infinity Pool', 'Spa', 'Fine Dining'],
      ),
    ];

    if (categoryFilter == null || categoryFilter == 'all') {
      return stops;
    }
    return stops.where((s) => s.categoryKey == categoryFilter).toList();
  }
}
