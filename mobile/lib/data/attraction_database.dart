import 'temple_database.dart';
import 'venue_database.dart';

class CuratedAttraction {
  final String name;
  final String city;
  final String rating;
  final int durationMin;
  final String highlight;
  final List<String> categories;
  final String type; // 'activity', 'place', 'viewpoint', 'food', 'nature'

  const CuratedAttraction({
    required this.name,
    required this.city,
    required this.rating,
    required this.durationMin,
    required this.highlight,
    required this.categories,
    this.type = 'place',
  });
}

class AttractionDatabase {
  static const List<CuratedAttraction> allAttractions = [
    // --- Coastal Karnataka (Mangaluru, Udupi, Ullal, Malpe) ---
    CuratedAttraction(
      name: 'Panambur Beach & Water Sports',
      city: 'Mangaluru',
      rating: '4.7',
      durationMin: 90,
      highlight: 'Jet skiing, boat rides, camel rides & sunset photography along Arabian Sea',
      categories: ['Beaches', 'Famous City Attractions', 'Instagrammable / Photography Spots'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Tannirbhavi Beach & Tree Park',
      city: 'Mangaluru',
      rating: '4.7',
      durationMin: 90,
      highlight: 'Tranquil beach with dense pine canopy, ferry crossing & walking trails',
      categories: ['Beaches', 'Nature & Forests', 'Viewpoints & Scenic Places'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Kudroli Gokarnanatheshwara Temple',
      city: 'Mangaluru',
      rating: '4.8',
      durationMin: 75,
      highlight: 'Illuminated marble corridors, golden gopuram & sacred Pushkarini',
      categories: ['Temples & Religious Places', 'Cultural Places', 'Historical & Heritage Places'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Kadri Manjunath Temple & Ancient Caves',
      city: 'Mangaluru',
      rating: '4.8',
      durationMin: 75,
      highlight: 'Historic hill shrine with natural mountain springs & Pandava caves',
      categories: ['Temples & Religious Places', 'Historical & Heritage Places', 'Hills & Mountains'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'St. Aloysius Chapel & Heritage Art Gallery',
      city: 'Mangaluru',
      rating: '4.8',
      durationMin: 60,
      highlight: 'Magnificent Sistine Chapel-style ceiling frescoes by Italian Jesuit Bro. Moscheni',
      categories: ['Historical & Heritage Places', 'Cultural Places', 'Monuments & Landmarks'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Pilikula Nisargadhama Biological Park',
      city: 'Mangaluru',
      rating: '4.7',
      durationMin: 150,
      highlight: 'Safari zoo, heritage artisanal village, lake boating & 3D planetarium',
      categories: ['Wildlife & National Parks', 'Nature & Forests', 'Rivers, Lakes & Waterfalls'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Sultan Battery & Gurupura Riverfront',
      city: 'Mangaluru',
      rating: '4.6',
      durationMin: 60,
      highlight: 'Tipu Sultan 1784 naval watchtower overlooking river mouth & boat jetty',
      categories: ['Forts & Palaces', 'Historical & Heritage Places', 'Rivers, Lakes & Waterfalls'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Someshwara Beach & Rudra Shile Rocks',
      city: 'Ullal, Mangaluru',
      rating: '4.7',
      durationMin: 75,
      highlight: 'Dramatic large monolithic sea boulders & panoramic sunset viewpoint',
      categories: ['Beaches', 'Viewpoints & Scenic Places', 'Instagrammable / Photography Spots'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Surathkal Lighthouse & Beach Lookout',
      city: 'Surathkal, Mangaluru',
      rating: '4.7',
      durationMin: 60,
      highlight: 'Panoramic 360-degree ocean lookout atop rocky coastal lighthouse hill',
      categories: ['Viewpoints & Scenic Places', 'Beaches', 'Monuments & Landmarks'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Kateel Sri Durgaparameshwari Temple',
      city: 'Kateel, Mangaluru',
      rating: '4.8',
      durationMin: 90,
      highlight: 'Sacred river island sanctum surrounded by rushing streams of Nandini river',
      categories: ['Temples & Religious Places', 'Rivers, Lakes & Waterfalls'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Udupi Sri Krishna Matha & Temple Square',
      city: 'Udupi',
      rating: '4.9',
      durationMin: 90,
      highlight: 'Historic 13th-century Madhvacharya matha, golden ratha & holy pond',
      categories: ['Temples & Religious Places', 'Cultural Places', 'Famous / Must-Visit Places'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Malpe Beach & St. Mary\'s Island',
      city: 'Malpe, Udupi',
      rating: '4.8',
      durationMin: 180,
      highlight: 'Scenic ferry ride to million-year-old columnar basalt rock formations',
      categories: ['Beaches', 'Nature & Forests', 'Instagrammable / Photography Spots'],
      type: 'place',
    ),

    // --- Chikmagalur & Western Ghats ---
    CuratedAttraction(
      name: 'Mullayanagiri Peak & Trekking Ridge',
      city: 'Chikmagalur',
      rating: '4.8',
      durationMin: 150,
      highlight: 'Sweeping Western Ghats mountain vistas, cool mist and hilltop temple',
      categories: ['Hills & Mountains', 'Viewpoints & Scenic Places', 'Instagrammable / Photography Spots'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Baba Budangiri & Datta Peeta',
      city: 'Chikmagalur',
      rating: '4.7',
      durationMin: 120,
      highlight: 'Dramatic mountain pass, historic caves and origin of Indian coffee',
      categories: ['Hills & Mountains', 'Cultural Places', 'Historical & Heritage Places'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Hebbe Falls & Mountain Stream Trek',
      city: 'Chikmagalur',
      rating: '4.8',
      durationMin: 180,
      highlight: 'Exciting 4x4 jungle ride & trek through coffee plantations to roaring falls',
      categories: ['Rivers, Lakes & Waterfalls', 'Nature & Forests', 'Hills & Mountains'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Z Point Sunset Lookout',
      city: 'Kemmanagundi, Chikmagalur',
      rating: '4.7',
      durationMin: 90,
      highlight: 'Thrilling cliffside walking trail with 360-degree green valley views',
      categories: ['Viewpoints & Scenic Places', 'Hills & Mountains', 'Instagrammable / Photography Spots'],
      type: 'place',
    ),

    // --- Wayanad ---
    CuratedAttraction(
      name: 'Banasura Sagar Dam & Speed Boating',
      city: 'Wayanad',
      rating: '4.7',
      durationMin: 120,
      highlight: 'Speed boating in emerald reservoir surrounded by misty Banasura hills',
      categories: ['Famous Bridges / Dams', 'Rivers, Lakes & Waterfalls', 'Viewpoints & Scenic Places'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Edakkal Caves & Prehistoric Carvings',
      city: 'Wayanad',
      rating: '4.7',
      durationMin: 120,
      highlight: 'Scenic uphill mountain trek to prehistoric rock engravings & valley view',
      categories: ['Historical & Heritage Places', 'Hills & Mountains', 'Cultural Places'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Soochipara Waterfalls (Sentinel Rock)',
      city: 'Wayanad',
      rating: '4.7',
      durationMin: 120,
      highlight: 'Walk through tea plantations and lush evergreen forest to natural pool',
      categories: ['Rivers, Lakes & Waterfalls', 'Nature & Forests'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Lakkidi View Point & Ghat Road Vista',
      city: 'Wayanad',
      rating: '4.6',
      durationMin: 60,
      highlight: 'Dramatic 700m high cliff edge looking over winding Thamarassery Churam',
      categories: ['Viewpoints & Scenic Places', 'Hills & Mountains'],
      type: 'place',
    ),

    // --- Mysuru ---
    CuratedAttraction(
      name: 'Mysore Palace (Amba Vilas)',
      city: 'Mysuru',
      rating: '4.8',
      durationMin: 150,
      highlight: 'Golden Throne, stained glass Kalyana Mantapa & illuminated royal durbar',
      categories: ['Forts & Palaces', 'Historical & Heritage Places', 'Famous / Must-Visit Places'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Brindavan Gardens & Musical Dancing Fountain',
      city: 'Mysuru',
      rating: '4.7',
      durationMin: 120,
      highlight: 'Terraced botanical gardens and synchronized musical dancing fountains',
      categories: ['Nature & Forests', 'Rivers, Lakes & Waterfalls', 'Famous City Attractions'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Sri Chamarajendra Zoological Gardens',
      city: 'Mysuru',
      rating: '4.8',
      durationMin: 150,
      highlight: 'Historic 1892 sanctuary with giraffes, big cats & exotic birds',
      categories: ['Wildlife & National Parks', 'Nature & Forests', 'Famous / Must-Visit Places'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Chamundi Hills & Monolithic Nandi',
      city: 'Mysuru',
      rating: '4.8',
      durationMin: 90,
      highlight: 'Hilltop Shakti Peetha & 16ft monolithic Nandi statue',
      categories: ['Temples & Religious Places', 'Viewpoints & Scenic Places', 'Hills & Mountains'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Devaraja Heritage Spice & Silk Market',
      city: 'Mysuru',
      rating: '4.7',
      durationMin: 75,
      highlight: 'Vibrant 100-year-old market with pure sandalwood, silk & Mysore Pak',
      categories: ['Famous Markets & Local Places', 'Cultural Places'],
      type: 'place',
    ),

    // --- Coorg (Kodagu) ---
    CuratedAttraction(
      name: 'Abbey Falls & Coffee Estate Trek',
      city: 'Madikeri, Coorg',
      rating: '4.7',
      durationMin: 75,
      highlight: '70ft roaring waterfall surrounded by private coffee and spice estates',
      categories: ['Rivers, Lakes & Waterfalls', 'Nature & Forests'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Raja\'s Seat Sunset Viewpoint',
      city: 'Madikeri, Coorg',
      rating: '4.7',
      durationMin: 60,
      highlight: 'Panoramic sunset view over Western Ghats mist-covered valleys',
      categories: ['Viewpoints & Scenic Places', 'Hills & Mountains'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Dubare Elephant Camp & River Boating',
      city: 'Coorg',
      rating: '4.7',
      durationMin: 120,
      highlight: 'Interactive elephant care, river boating & white water rafting',
      categories: ['Wildlife & National Parks', 'Rivers, Lakes & Waterfalls'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Namdroling Monastery (Golden Temple)',
      city: 'Bylakuppe, Coorg',
      rating: '4.8',
      durationMin: 90,
      highlight: '40ft gold-plated Buddha statues, ornate Tibetan murals & peace bell',
      categories: ['Cultural Places', 'Temples & Religious Places'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Mandalpatti Peak 4x4 Jeep Safari',
      city: 'Madikeri, Coorg',
      rating: '4.8',
      durationMin: 150,
      highlight: 'Off-road 4x4 adventure through clouds to 4000ft high mountain ridge',
      categories: ['Hills & Mountains', 'Viewpoints & Scenic Places'],
      type: 'place',
    ),

    // --- Bengaluru ---
    CuratedAttraction(
      name: 'Bangalore Palace & Royal Grounds',
      city: 'Bengaluru',
      rating: '4.7',
      durationMin: 120,
      highlight: 'Tudor-revival wooden palace with royal hunting memorabilia & gardens',
      categories: ['Forts & Palaces', 'Historical & Heritage Places'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Lalbagh Botanical Gardens & Glass House',
      city: 'Bengaluru',
      rating: '4.8',
      durationMin: 120,
      highlight: 'Centuries-old botanical trees, crystal palace glass house & lotus lake',
      categories: ['Nature & Forests', 'Famous City Attractions'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Cubbon Park & Heritage Promenade',
      city: 'Bengaluru',
      rating: '4.7',
      durationMin: 90,
      highlight: '300-acre green canopy heart of the city with statues & bamboo groves',
      categories: ['Nature & Forests', 'Famous City Attractions'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Bannerghatta National Park & Safari',
      city: 'Bengaluru',
      rating: '4.7',
      durationMin: 180,
      highlight: 'Grand safari seeing lions, tigers and bears in natural biological reserve',
      categories: ['Wildlife & National Parks', 'Nature & Forests'],
      type: 'place',
    ),

    // --- Goa ---
    CuratedAttraction(
      name: 'Baga & Calangute Beach Coastal Strip',
      city: 'North Goa',
      rating: '4.6',
      durationMin: 120,
      highlight: 'Parasailing, banana boat rides, beach shacks & lively nightlife',
      categories: ['Beaches', 'Famous City Attractions'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Aguada Fort & Portuguese Lighthouse',
      city: 'Sinquerim, Goa',
      rating: '4.7',
      durationMin: 90,
      highlight: '17th-century Portuguese fortress overlooking confluence of Mandovi river',
      categories: ['Forts & Palaces', 'Historical & Heritage Places', 'Viewpoints & Scenic Places'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Dudhsagar Waterfalls & Forest Jeep Trek',
      city: 'Goa Border',
      rating: '4.8',
      durationMin: 240,
      highlight: 'Four-tiered 310m milky white waterfall surrounded by Bhagwan Mahavir wildlife',
      categories: ['Rivers, Lakes & Waterfalls', 'Nature & Forests'],
      type: 'place',
    ),

    // --- Mumbai ---
    CuratedAttraction(
      name: 'Gateway of India & Apollo Bunder',
      city: 'Mumbai',
      rating: '4.8',
      durationMin: 90,
      highlight: 'Iconic 1924 basalt arch monument overlooking Mumbai harbour',
      categories: ['Historical & Heritage Places', 'Monuments & Landmarks'],
      type: 'place',
    ),
    CuratedAttraction(
      name: 'Marine Drive & Queen\'s Necklace Viewpoint',
      city: 'Mumbai',
      rating: '4.8',
      durationMin: 90,
      highlight: 'Curved 3.6 km coastal promenade with sweeping sunset Arabian sea views',
      categories: ['Viewpoints & Scenic Places', 'Famous City Attractions'],
      type: 'place',
    ),
  ];

  /// Pre-defined ready-to-add travel activities
  static const List<Map<String, String>> readyActivities = [
    {
      'name': '🌅 Sunrise Viewpoint & Morning Coffee Walk',
      'area': 'Scenic Viewpoint',
      'why': 'Early morning golden hour panorama & fresh brewed local beverage',
      'category': 'Viewpoints & Scenic Places',
    },
    {
      'name': '🛕 Morning Darshan, Aarti & Temple Visit',
      'area': 'Historic Spiritual Sanctum',
      'why': 'Sacred morning blessings, peaceful pradakshina & temple prasadam',
      'category': 'Temples & Religious Places',
    },
    {
      'name': '🏖️ Sunset Beach Walk & Photography',
      'area': 'Coastal Beach Promenade',
      'why': 'Golden hour Arabian sea vistas, sea breeze & sunset photography',
      'category': 'Beaches',
    },
    {
      'name': '🏰 Heritage Palace & Architecture Tour',
      'area': 'Royal Landmark',
      'why': 'Guided walk through royal durbar halls, antique galleries & arches',
      'category': 'Forts & Palaces',
    },
    {
      'name': '🍛 Traditional Coastal / Regional Thali Lunch',
      'area': 'Heritage Dining Venue',
      'why': 'Authentic regional dishes, fresh spice curries & local sweet dessert',
      'category': 'Famous Markets & Local Places',
    },
    {
      'name': '🌊 Waterfall Trek & Natural Pool Dip',
      'area': 'Forest Stream Trail',
      'why': 'Walk through lush greenery to cascading natural mountain springs',
      'category': 'Rivers, Lakes & Waterfalls',
    },
    {
      'name': '🐘 Wildlife Jeep Safari & Nature Exploration',
      'area': 'Forest Reserve / Sanctuary',
      'why': 'Open-top wildlife sighting of elephants, deer, peacocks & big cats',
      'category': 'Wildlife & National Parks',
    },
    {
      'name': '🛍️ Artisan Market & Local Souvenir Shopping',
      'area': 'Traditional Bazaar',
      'why': 'Local spices, handmade crafts, regional textiles & street snacks',
      'category': 'Famous Markets & Local Places',
    },
    {
      'name': '☕ Plantation Walk & Fresh Roastery Tour',
      'area': 'Estate Trail',
      'why': 'Guided sensory walk through coffee/tea shrubs with live brewing demo',
      'category': 'Nature & Forests',
    },
  ];

  /// Search places, temples, venues, and activities with high relevance and autocomplete
  static List<Map<String, String>> search(String query, {String? category, String? cityFilter}) {
    final q = query.trim().toLowerCase();
    final results = <Map<String, String>>[];
    final seenNames = <String>{};

    bool matches(String target) => target.toLowerCase().contains(q);

    // 1. Check curated attractions
    for (final a in allAttractions) {
      if (category != null && category.isNotEmpty && category != 'All') {
        if (!a.categories.any((c) => c.toLowerCase().contains(category.toLowerCase()))) {
          continue;
        }
      }
      if (q.isEmpty ||
          matches(a.name) ||
          matches(a.city) ||
          matches(a.highlight) ||
          a.categories.any((c) => matches(c))) {
        if (!seenNames.contains(a.name)) {
          seenNames.add(a.name);
          results.add({
            'name': a.name,
            'area': a.city,
            'why': '⭐ ${a.rating} · ${a.highlight}',
          });
        }
      }
    }

    // 2. Check ready activities
    for (final act in readyActivities) {
      if (category != null && category.isNotEmpty && category != 'All') {
        if (act['category'] != null &&
            !act['category']!.toLowerCase().contains(category.toLowerCase())) {
          continue;
        }
      }
      if (q.isEmpty ||
          matches(act['name']!) ||
          matches(act['area']!) ||
          matches(act['why']!)) {
        if (!seenNames.contains(act['name']!)) {
          seenNames.add(act['name']!);
          results.add({
            'name': act['name']!,
            'area': act['area']!,
            'why': act['why']!,
          });
        }
      }
    }

    // 3. Check TempleDatabase
    for (final t in TempleDatabase.allTemples) {
      if (category != null && category.isNotEmpty && category != 'All' && !category.contains('Temple')) {
        continue;
      }
      if (q.isEmpty ||
          matches(t.canonicalName) ||
          matches(t.city) ||
          matches(t.deity) ||
          matches(t.highlights) ||
          t.aliases.any((al) => matches(al))) {
        if (!seenNames.contains(t.canonicalName)) {
          seenNames.add(t.canonicalName);
          results.add({
            'name': t.canonicalName,
            'area': '${t.city}, ${t.state}',
            'why': '🛕 ${t.deity} · ⭐ ${t.rating} · ${t.highlights}',
          });
        }
      }
    }

    // 4. Check VenueDatabase
    for (final v in VenueDatabase.allVenues) {
      if (category != null && category.isNotEmpty && category != 'All' && !category.contains('Dining') && !category.contains('Food')) {
        continue;
      }
      if (q.isEmpty ||
          matches(v.name) ||
          matches(v.city) ||
          matches(v.specialty)) {
        if (!seenNames.contains(v.name)) {
          seenNames.add(v.name);
          results.add({
            'name': v.name,
            'area': v.city,
            'why': '⭐ ${v.rating} · ${v.specialty}',
          });
        }
      }
    }

    return results;
  }
}
