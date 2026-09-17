import 'dart:math' as math;

class SavedPlace {
  final String id;
  final String name;
  final String category; // 'Waterfall', 'Lake', 'Temple', 'Viewpoint', 'Restaurant', 'Hotel', 'Cafe', 'Attraction', 'Fuel', 'Utility'
  final String location;
  final double lat;
  final double lng;
  final double? rating;
  final String? image;
  final String? description;
  final DateTime savedAt;

  const SavedPlace({
    required this.id,
    required this.name,
    required this.category,
    required this.location,
    required this.lat,
    required this.lng,
    this.rating,
    this.image,
    this.description,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'location': location,
        'lat': lat,
        'lng': lng,
        'rating': rating,
        'image': image,
        'description': description,
        'savedAt': savedAt.toIso8601String(),
      };

  factory SavedPlace.fromJson(Map<String, dynamic> json) {
    return SavedPlace(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name']?.toString() ?? 'Unnamed Place',
      category: json['category']?.toString() ?? 'Attraction',
      location: json['location']?.toString() ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      rating: (json['rating'] as num?)?.toDouble(),
      image: json['image']?.toString(),
      description: json['description']?.toString(),
      savedAt: json['savedAt'] != null
          ? DateTime.tryParse(json['savedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// Calculates approximate great-circle distance in kilometers from [userLat, userLng].
  double distanceFrom(double userLat, double userLng) {
    if (lat == 0.0 && lng == 0.0) return 0.0;
    const p = 0.017453292519943295; // Math.PI / 180
    final a = 0.5 -
        math.cos((lat - userLat) * p) / 2 +
        math.cos(userLat * p) *
            math.cos(lat * p) *
            (1 - math.cos((lng - userLng) * p)) /
            2;
    return 12742 * math.asin(math.sqrt(a)); // 2 * R; R = 6371 km
  }
}
