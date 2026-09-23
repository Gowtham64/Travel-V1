class DestinationItem {
  final String placeId;
  final String name;
  final String tagline;
  final String formattedAddress;
  final String country;
  final String countryCode; // 'IN', 'US', 'GB', 'AE', 'FR', 'AU', 'JP'
  final String region;
  final double lat;
  final double lng;
  final String category; // 'mountains', 'beaches', 'heritage', 'nature', 'roadtrip', 'urban'
  final String imageUrl;
  final double rating;
  final int reviewsCount;
  final String bestTimeToVisit;
  final List<String> topHighlights;

  const DestinationItem({
    required this.placeId,
    required this.name,
    required this.tagline,
    required this.formattedAddress,
    required this.country,
    required this.countryCode,
    required this.region,
    required this.lat,
    required this.lng,
    required this.category,
    required this.imageUrl,
    this.rating = 4.8,
    this.reviewsCount = 1240,
    required this.bestTimeToVisit,
    required this.topHighlights,
  });
}

class DestinationCatalogService {
  DestinationCatalogService._();
  static final DestinationCatalogService instance = DestinationCatalogService._();

  static const List<DestinationItem> globalDestinations = [
    // ══════════════════ INDIA ══════════════════
    DestinationItem(
      placeId: 'dest_coorg_in',
      name: 'Coorg',
      tagline: 'Scotland of India • Coffee Plantations & Waterfalls',
      formattedAddress: 'Kodagu, Karnataka, India',
      country: 'India',
      countryCode: 'IN',
      region: 'Karnataka',
      lat: 12.3375,
      lng: 75.8069,
      category: 'mountains',
      imageUrl: 'images/destination_coorg.png',
      rating: 4.9,
      reviewsCount: 3820,
      bestTimeToVisit: 'Oct - Mar',
      topHighlights: ['Abbey Falls', 'Raja’s Seat', 'Dubare Elephant Camp', 'Coffee Estate Trails'],
    ),
    DestinationItem(
      placeId: 'dest_ooty_in',
      name: 'Ooty',
      tagline: 'Queen of Hill Stations • Nilgiri Mountain Railway',
      formattedAddress: 'Nilgiris, Tamil Nadu, India',
      country: 'India',
      countryCode: 'IN',
      region: 'Tamil Nadu',
      lat: 11.4102,
      lng: 76.6950,
      category: 'mountains',
      imageUrl: 'images/destination_ooty.png',
      rating: 4.8,
      reviewsCount: 4210,
      bestTimeToVisit: 'Oct - Jun',
      topHighlights: ['Botanical Gardens', 'Doddabetta Peak', 'Pykara Lake', 'Nilgiri Toy Train'],
    ),
    DestinationItem(
      placeId: 'dest_goa_in',
      name: 'Goa',
      tagline: 'Sun-kissed Beaches & Portuguese Heritage',
      formattedAddress: 'Goa, India',
      country: 'India',
      countryCode: 'IN',
      region: 'Goa',
      lat: 15.2993,
      lng: 74.1240,
      category: 'beaches',
      imageUrl: 'images/destination_goa.png',
      rating: 4.9,
      reviewsCount: 8900,
      bestTimeToVisit: 'Nov - Feb',
      topHighlights: ['Palolem Beach', 'Fort Aguada', 'Dudhsagar Falls', 'Old Goa Cathedrals'],
    ),
    DestinationItem(
      placeId: 'dest_mysuru_in',
      name: 'Mysuru',
      tagline: 'City of Palaces, Silk & Royal Heritage',
      formattedAddress: 'Mysuru, Karnataka, India',
      country: 'India',
      countryCode: 'IN',
      region: 'Karnataka',
      lat: 12.2958,
      lng: 76.6394,
      category: 'heritage',
      imageUrl: 'images/destination_mysuru.png',
      rating: 4.8,
      reviewsCount: 3100,
      bestTimeToVisit: 'Sep - Mar',
      topHighlights: ['Mysore Palace', 'Chamundi Hills', 'Brindavan Gardens', 'St. Philomena’s Cathedral'],
    ),
    DestinationItem(
      placeId: 'dest_chikmagalur_in',
      name: 'Chikmagalur',
      tagline: 'Mullayanagiri Peaks & Lush Green Valleys',
      formattedAddress: 'Chikkamagaluru, Karnataka, India',
      country: 'India',
      countryCode: 'IN',
      region: 'Karnataka',
      lat: 13.3161,
      lng: 75.7720,
      category: 'mountains',
      imageUrl: 'images/destination_chikmagalur.png',
      rating: 4.9,
      reviewsCount: 2950,
      bestTimeToVisit: 'Sep - May',
      topHighlights: ['Mullayanagiri Peak', 'Baba Budangiri', 'Hebbe Falls', 'Coffee Museum'],
    ),
    DestinationItem(
      placeId: 'dest_hampi_in',
      name: 'Hampi',
      tagline: 'UNESCO World Heritage • Ruins of Vijayanagara',
      formattedAddress: 'Vijayanagara, Karnataka, India',
      country: 'India',
      countryCode: 'IN',
      region: 'Karnataka',
      lat: 15.3350,
      lng: 76.4600,
      category: 'heritage',
      imageUrl: 'images/destination_hampi.png',
      rating: 4.9,
      reviewsCount: 4500,
      bestTimeToVisit: 'Nov - Feb',
      topHighlights: ['Virupaksha Temple', 'Stone Chariot', 'Vittala Temple', 'Matanga Hill Sunrise'],
    ),

    // ══════════════════ UNITED STATES ══════════════════
    DestinationItem(
      placeId: 'dest_grand_canyon_us',
      name: 'Grand Canyon',
      tagline: 'Iconic Red Rock Vistas & Desert Highways',
      formattedAddress: 'Arizona, United States',
      country: 'United States',
      countryCode: 'US',
      region: 'Arizona',
      lat: 36.0544,
      lng: -112.1401,
      category: 'nature',
      imageUrl: 'https://images.unsplash.com/photo-1474044159687-1ee9f3a51722?q=80&w=1200&auto=format&fit=crop',
      rating: 4.9,
      reviewsCount: 12400,
      bestTimeToVisit: 'Mar - May, Sep - Nov',
      topHighlights: ['South Rim Trail', 'Desert View Watchtower', 'Bright Angel Trail', 'Mather Point'],
    ),
    DestinationItem(
      placeId: 'dest_big_sur_us',
      name: 'Big Sur & PCH Highway 1',
      tagline: 'Pacific Coast Scenic Highway & Bixby Bridge',
      formattedAddress: 'California, United States',
      country: 'United States',
      countryCode: 'US',
      region: 'California',
      lat: 36.2704,
      lng: -121.8081,
      category: 'roadtrip',
      imageUrl: 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?q=80&w=1200&auto=format&fit=crop',
      rating: 4.9,
      reviewsCount: 8200,
      bestTimeToVisit: 'Apr - Oct',
      topHighlights: ['Bixby Creek Bridge', 'McWay Falls', 'Pfeiffer Beach', 'Point Lobos State Reserve'],
    ),
    DestinationItem(
      placeId: 'dest_yosemite_us',
      name: 'Yosemite National Park',
      tagline: 'Granite Cliffs, Giant Sequoias & Waterfalls',
      formattedAddress: 'California, United States',
      country: 'United States',
      countryCode: 'US',
      region: 'California',
      lat: 37.8651,
      lng: -119.5383,
      category: 'mountains',
      imageUrl: 'https://images.unsplash.com/photo-1426604966848-d7adac402bff?q=80&w=1200&auto=format&fit=crop',
      rating: 4.9,
      reviewsCount: 9700,
      bestTimeToVisit: 'May - Sep',
      topHighlights: ['El Capitan', 'Half Dome', 'Yosemite Falls', 'Glacier Point Overlook'],
    ),

    // ══════════════════ UNITED KINGDOM ══════════════════
    DestinationItem(
      placeId: 'dest_lake_district_gb',
      name: 'Lake District',
      tagline: 'Glacial Lakes, Rugged Fells & Literary Trails',
      formattedAddress: 'Cumbria, England, United Kingdom',
      country: 'United Kingdom',
      countryCode: 'GB',
      region: 'England',
      lat: 54.4609,
      lng: -3.0886,
      category: 'nature',
      imageUrl: 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?q=80&w=1200&auto=format&fit=crop',
      rating: 4.8,
      reviewsCount: 5100,
      bestTimeToVisit: 'May - Sep',
      topHighlights: ['Lake Windermere', 'Scafell Pike', 'Keswick', 'Ullswater Steamer Cruise'],
    ),
    DestinationItem(
      placeId: 'dest_scottish_highlands_gb',
      name: 'Scottish Highlands',
      tagline: 'North Coast 500 Route • Castles & Lochs',
      formattedAddress: 'Highlands, Scotland, United Kingdom',
      country: 'United Kingdom',
      countryCode: 'GB',
      region: 'Scotland',
      lat: 57.3229,
      lng: -4.4244,
      category: 'roadtrip',
      imageUrl: 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?q=80&w=1200&auto=format&fit=crop',
      rating: 4.9,
      reviewsCount: 6800,
      bestTimeToVisit: 'May - Sep',
      topHighlights: ['Loch Ness', 'Eilean Donan Castle', 'Isle of Skye', 'Glencoe Valley Pass'],
    ),

    // ══════════════════ UNITED ARAB EMIRATES ══════════════════
    DestinationItem(
      placeId: 'dest_dubai_ae',
      name: 'Dubai & Desert Dunes',
      tagline: 'Futuristic Skylines & Desert Safari Trails',
      formattedAddress: 'Dubai, United Arab Emirates',
      country: 'United Arab Emirates',
      countryCode: 'AE',
      region: 'Dubai',
      lat: 25.2048,
      lng: 55.2708,
      category: 'urban',
      imageUrl: 'https://images.unsplash.com/photo-1512453979798-5ea266f8880c?q=80&w=1200&auto=format&fit=crop',
      rating: 4.9,
      reviewsCount: 14200,
      bestTimeToVisit: 'Nov - Mar',
      topHighlights: ['Burj Khalifa', 'Palm Jumeirah', 'Hatta Mountain Reserve', 'Dubai Marina'],
    ),

    // ══════════════════ EUROPE ══════════════════
    DestinationItem(
      placeId: 'dest_amalfi_it',
      name: 'Amalfi Coast',
      tagline: 'Dramatic Cliffs & Mediterranean Coastline',
      formattedAddress: 'Campania, Italy',
      country: 'Italy',
      countryCode: 'IT',
      region: 'Europe',
      lat: 40.6340,
      lng: 14.6027,
      category: 'roadtrip',
      imageUrl: 'https://images.unsplash.com/photo-1533105079780-92b9be482077?q=80&w=1200&auto=format&fit=crop',
      rating: 4.9,
      reviewsCount: 8900,
      bestTimeToVisit: 'Apr - Oct',
      topHighlights: ['Positano Cliffs', 'Ravello Gardens', 'Amalfi Cathedral', 'Path of the Gods'],
    ),
    DestinationItem(
      placeId: 'dest_swiss_alps_ch',
      name: 'Swiss Alps & Passes',
      tagline: 'Furka Pass, Glaciers & Alpine Vistas',
      formattedAddress: 'Valais, Switzerland',
      country: 'Switzerland',
      countryCode: 'CH',
      region: 'Europe',
      lat: 46.5724,
      lng: 8.4150,
      category: 'mountains',
      imageUrl: 'https://images.unsplash.com/photo-1502784444187-359ac186c5bb?q=80&w=1200&auto=format&fit=crop',
      rating: 4.9,
      reviewsCount: 9200,
      bestTimeToVisit: 'Jun - Sep',
      topHighlights: ['Furka Pass', 'Matterhorn Viewpoint', 'Lauterbrunnen Valley', 'Grimsel Pass'],
    ),

    // ══════════════════ AUSTRALIA ══════════════════
    DestinationItem(
      placeId: 'dest_great_ocean_road_au',
      name: 'Great Ocean Road',
      tagline: 'Twelve Apostles & Scenic Coastal Drive',
      formattedAddress: 'Victoria, Australia',
      country: 'Australia',
      countryCode: 'AU',
      region: 'Victoria',
      lat: -38.6657,
      lng: 143.1039,
      category: 'roadtrip',
      imageUrl: 'https://images.unsplash.com/photo-1529108190281-9a4f620bc2d8?q=80&w=1200&auto=format&fit=crop',
      rating: 4.9,
      reviewsCount: 7400,
      bestTimeToVisit: 'Nov - Apr',
      topHighlights: ['Twelve Apostles', 'Loch Ard Gorge', 'Bells Beach', 'Otway Rainforest'],
    ),

    // ══════════════════ JAPAN ══════════════════
    DestinationItem(
      placeId: 'dest_fuji_jp',
      name: 'Mount Fuji & Hakone',
      tagline: 'Sacred Volcano, Hot Springs & Lake Ashi',
      formattedAddress: 'Kanagawa / Shizuoka, Japan',
      country: 'Japan',
      countryCode: 'JP',
      region: 'Kantō / Chūbu',
      lat: 35.3606,
      lng: 138.7274,
      category: 'mountains',
      imageUrl: 'https://images.unsplash.com/photo-1490806843957-31f4c9a91c65?q=80&w=1200&auto=format&fit=crop',
      rating: 4.9,
      reviewsCount: 11200,
      bestTimeToVisit: 'Oct - May',
      topHighlights: ['Lake Kawaguchiko', 'Hakone Ropeway', 'Chureito Pagoda', 'Fuji Five Lakes'],
    ),
  ];

  List<DestinationItem> getDestinationsForRegion(String countryCode, {String? category}) {
    var list = globalDestinations.where((d) => d.countryCode == countryCode || d.region.toUpperCase() == countryCode.toUpperCase()).toList();
    if (list.isEmpty) {
      list = globalDestinations;
    }
    if (category != null && category != 'all') {
      final filtered = list.where((d) => d.category.toLowerCase() == category.toLowerCase()).toList();
      return filtered.isNotEmpty ? filtered : list;
    }
    return list;
  }
}
