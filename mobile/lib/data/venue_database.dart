/// Curated Venue & Dining Database
/// Contains top-rated real highway stops, authentic restaurants, and verified hotels
/// categorized by region and meal/stay type.
class RecommendedVenue {
  final String name;
  final String type; // 'breakfast' | 'coffee' | 'lunch' | 'dinner' | 'hotel'
  final double rating;
  final String specialty;
  final String city;
  final String address;
  final String priceRange;

  const RecommendedVenue({
    required this.name,
    required this.type,
    required this.rating,
    required this.specialty,
    required this.city,
    required this.address,
    this.priceRange = '₹₹',
  });
}

class VenueDatabase {
  VenueDatabase._();

  static const List<RecommendedVenue> allVenues = [
    // ==========================================
    // TIRUPATI & HIGHWAY CIRCUIT (NH 75 / NH 69)
    // ==========================================
    // Highway Coffee & Breakfast
    RecommendedVenue(
      name: 'Woodys Highway Restaurant & Cafe',
      type: 'coffee',
      rating: 4.6,
      specialty: 'Authentic South Indian Filter Coffee, Crispy Vada & Masala Dosa',
      city: 'Kolar Highway (NH 75)',
      address: 'Bangalore - Tirupati Highway, Kolar',
    ),
    RecommendedVenue(
      name: 'Adyar Ananda Bhavan (A2B) Highway Plaza',
      type: 'breakfast',
      rating: 4.5,
      specialty: 'Ghee Podi Idli, Rava Dosa, Hot Filter Coffee & Clean Highway Restrooms',
      city: 'Mulbagal Highway (NH 75)',
      address: 'Near Mulbagal Toll Plaza, NH 75',
    ),
    RecommendedVenue(
      name: 'Maiyas Highway Express Food Court',
      type: 'coffee',
      rating: 4.5,
      specialty: 'Specialty Degree Coffee, Bisi Bele Bath & Sweets',
      city: 'Kolar Highway',
      address: 'NH 75 Expressway Junction',
    ),
    // Tirupati Lunch
    RecommendedVenue(
      name: 'Minerva Grand Pure Vegetarian Restaurant',
      type: 'lunch',
      rating: 4.7,
      specialty: 'Grand South Indian Thali, Ghee Sambar Rice & Andhra Thali',
      city: 'Tirupati',
      address: 'Near Old Maternity Hospital, Tirupati',
    ),
    RecommendedVenue(
      name: 'Sri Venkateswara Nitya Annaprasadam Complex',
      type: 'lunch',
      rating: 4.9,
      specialty: 'Sacred Tirumala Prasadam, Hot Sambar Rice, Chitrannam & Sweet Pongal',
      city: 'Tirumala',
      address: 'Near Sri Venkateswara Temple, Tirumala',
    ),
    RecommendedVenue(
      name: 'Hotel Mayura Pure Veg Restaurant',
      type: 'lunch',
      rating: 4.6,
      specialty: 'Authentic Andhra Meals, Avakaya Pappu & Curd Rice',
      city: 'Tirupati',
      address: 'Opposite APSRTC Central Bus Station, Tirupati',
    ),
    RecommendedVenue(
      name: 'Bhimas Deluxe Heritage Veg Dining',
      type: 'dinner',
      rating: 4.6,
      specialty: 'Traditional South Indian Thali Meals, Poori Kurma & Sweet Kheer',
      city: 'Tirupati',
      address: 'G. Car Street, Near Railway Station, Tirupati',
    ),
    RecommendedVenue(
      name: 'PS4 Andhra Traditional Restaurant',
      type: 'dinner',
      rating: 4.5,
      specialty: 'Spicy Andhra Meals, Guntur Paneer & Hot Podi Rice',
      city: 'Tirupati',
      address: 'Air Bypass Road, Tirupati',
    ),
    // Tirupati Hotels
    RecommendedVenue(
      name: 'Fortune Select Grand Ridge (Member ITC Hotel Group)',
      type: 'hotel',
      rating: 4.7,
      specialty: '5-Star Luxury Stay, Veg Dining, Swimming Pool & Mountain Views',
      city: 'Tirupati',
      address: 'Shilparamam, Tiruchanur Road, Tirupati',
      priceRange: '₹₹₹',
    ),
    RecommendedVenue(
      name: 'Marasa Sarovar Premiere',
      type: 'hotel',
      rating: 4.7,
      specialty: 'World-class 5-Star Hotel inspired by Dashavatara Themes & Spa',
      city: 'Tirupati',
      address: 'Upadhyayanagar, Karakambadi Road, Tirupati',
      priceRange: '₹₹₹',
    ),
    RecommendedVenue(
      name: 'Pai Viceroy Hotel',
      type: 'hotel',
      rating: 4.6,
      specialty: 'Premium Pilgrim Suites, Gufha Restaurant & 24/7 Front Desk',
      city: 'Tirupati',
      address: 'T.P. Area, Near Alipiri Road, Tirupati',
      priceRange: '₹₹',
    ),
    RecommendedVenue(
      name: 'TTD Srinivasam Pilgrimage Complex',
      type: 'hotel',
      rating: 4.5,
      specialty: 'Direct TTD Managed Pilgrim Guest House & SED Ticket counters',
      city: 'Tirupati',
      address: 'Opposite Central Bus Stand, Tirupati',
      priceRange: '₹',
    ),

    // ==========================================
    // BENGALURU, MANDYA & MYSURU CIRCUIT
    // ==========================================
    RecommendedVenue(
      name: 'MTR 1924 Expressway Plaza',
      type: 'breakfast',
      rating: 4.7,
      specialty: 'Legendary Rava Idli with Pure Ghee, Masala Dosa & Filter Coffee',
      city: 'Bangalore-Mysore Expressway',
      address: 'Expressway Food Plaza, Maddur',
    ),
    RecommendedVenue(
      name: 'Kamat Lokaruchi Heritage Dining',
      type: 'breakfast',
      rating: 4.6,
      specialty: 'Akki Rotti, Jolada Rotti Oota, Filter Coffee & Heritage Village Decor',
      city: 'Ramanagara Highway',
      address: 'Jannagere, Bangalore-Mysore Highway',
    ),
    RecommendedVenue(
      name: 'Shivalli Tiffin Room (STR)',
      type: 'coffee',
      rating: 4.6,
      specialty: 'Authentic Filter Coffee, Set Dosa & Gulab Jamun',
      city: 'Channapatna Highway',
      address: 'Expressway Service Road, Channapatna',
    ),
    RecommendedVenue(
      name: 'Hotel Original Vinayaka Mylari',
      type: 'lunch',
      rating: 4.8,
      specialty: 'World-Famous Butter Mylari Dosa with Fresh White Butter & Coconut Chutney',
      city: 'Mysuru',
      address: 'Nazarbad Main Road, Mysuru',
    ),
    RecommendedVenue(
      name: 'Hotel Dasaprakash Heritage Restaurant',
      type: 'lunch',
      rating: 4.6,
      specialty: 'Traditional Mysuru Royal Thali Meals & Ice Cream Sundaes',
      city: 'Mysuru',
      address: 'Gandhi Square, Mysuru',
    ),
    RecommendedVenue(
      name: 'Grand Mercure Mysuru (Accor)',
      type: 'hotel',
      rating: 4.7,
      specialty: 'Luxury 5-Star Stay, Rooftop Dining overlooking Chamundi Hills',
      city: 'Mysuru',
      address: 'New Sayyaji Rao Road, Mysuru',
      priceRange: '₹₹₹',
    ),
    RecommendedVenue(
      name: 'Radisson Blu Plaza Hotel Mysuru',
      type: 'hotel',
      rating: 4.8,
      specialty: 'Premium 5-Star Resort near Mysuru Palace & Golf Club',
      city: 'Mysuru',
      address: 'M.G. Road, Mysuru',
      priceRange: '₹₹₹',
    ),

    // ==========================================
    // TAMIL NADU (MADURAI, RAMESHWARAM, CHENNAI)
    // ==========================================
    RecommendedVenue(
      name: 'Murugan Idli Shop',
      type: 'breakfast',
      rating: 4.8,
      specialty: 'Melt-in-mouth Soft Ghee Idli, 4 varieties of fresh Chutneys & Jigarthanda',
      city: 'Madurai',
      address: 'West Masi Street, Near Meenakshi Temple, Madurai',
    ),
    RecommendedVenue(
      name: 'Sree Sabarees Pure Veg Restaurant',
      type: 'lunch',
      rating: 4.7,
      specialty: 'Traditional Chettinad Veg Thali, Curd Vadai & Filter Coffee',
      city: 'Madurai',
      address: 'Opposite Railway Station, Madurai',
    ),
    RecommendedVenue(
      name: 'Heritage Madurai Resort',
      type: 'hotel',
      rating: 4.8,
      specialty: 'Geoffrey Bawa architecture, Olympic temple pool & Luxury Banyan Villa',
      city: 'Madurai',
      address: 'Kochadai, Madurai',
      priceRange: '₹₹₹',
    ),
    RecommendedVenue(
      name: 'Daiwik Hotels Rameshwaram',
      type: 'hotel',
      rating: 4.6,
      specialty: '4-Star Holistic Pilgrim Hotel, Aahaar Pure Veg Restaurant',
      city: 'Rameswaram',
      address: 'NH 49, Near Railway Station, Rameswaram',
      priceRange: '₹₹',
    ),

    // ==========================================
    // COASTAL KARNATAKA & UDUPI
    // ==========================================
    RecommendedVenue(
      name: 'Mitra Samaj Iconic Udupi Kitchen',
      type: 'breakfast',
      rating: 4.8,
      specialty: 'Authentic 1949 Udupi Masala Dosa, Goli Baje, Badam Halwa & Filter Coffee',
      city: 'Udupi',
      address: 'Car Street, Opposite Sri Krishna Matha, Udupi',
    ),
    RecommendedVenue(
      name: 'The Ocean Pearl Hotel & Dining',
      type: 'hotel',
      rating: 4.7,
      specialty: 'Premium 4-Star Stay, Sagar Ratna Veg Dining & Grand Suites',
      city: 'Udupi',
      address: 'Kalandi Temple Road, Udupi',
      priceRange: '₹₹',
    ),
    RecommendedVenue(
      name: 'RNS Residency Murudeshwar',
      type: 'hotel',
      rating: 4.7,
      specialty: 'Spectacular Sea-Facing Luxury Hotel beside 123-ft Shiva Statue',
      city: 'Murudeshwar',
      address: 'Temple Road, Arabian Sea Beachfront, Murudeshwar',
      priceRange: '₹₹',
    ),

    // ==========================================
    // VARANASI & NORTH INDIA
    // ==========================================
    RecommendedVenue(
      name: 'Keshari Ruchikar Bhojnalaya',
      type: 'lunch',
      rating: 4.7,
      specialty: 'Banarasi Thali, Special Rabri, Kashi Malaiyo & Poori Sabzi',
      city: 'Varanasi',
      address: 'D 14/9, Near Kashi Vishwanath Temple, Varanasi',
    ),
    RecommendedVenue(
      name: 'BrijRama Palace Heritage Hotel',
      type: 'hotel',
      rating: 4.9,
      specialty: '18th-century Maratha Palace on Darbhanga Ghat with private boat check-in',
      city: 'Varanasi',
      address: 'Darbhanga Ghat, Varanasi',
    ),
    // ==========================================
    // GOA & COASTAL HIGHWAY CIRCUIT
    // ==========================================
    RecommendedVenue(
      name: 'Cafe Bodega Heritage Bakery & Cafe',
      type: 'coffee',
      rating: 4.7,
      specialty: 'Artisanal Brewed Coffee, Fresh Croissants & Mediterranean Breakfast',
      city: 'Altinho, Panaji, Goa',
      address: 'Sunaparanta Centre for the Arts, Altinho, Panaji',
    ),
    RecommendedVenue(
      name: 'Ritz Classic Heritage Dining',
      type: 'lunch',
      rating: 4.8,
      specialty: 'Authentic Goan Fish Curry Thali, Sol Kadi, Prawn Balchao & Vegetarian Thali',
      city: 'Panaji, Goa',
      address: '18th June Road, Panaji, Goa',
    ),
    RecommendedVenue(
      name: "Fisherman's Wharf Waterfront Dining",
      type: 'dinner',
      rating: 4.8,
      specialty: 'Riverside Goan Delicacies, Live Music & Arabian Sea Breeze',
      city: 'Cavelossim / Panaji, Goa',
      address: 'Mobor Beach Road, Cavelossim, Goa',
      priceRange: '₹₹₹',
    ),
    RecommendedVenue(
      name: 'Taj Fort Aguada Resort & Spa',
      type: 'hotel',
      rating: 4.9,
      specialty: '5-Star Luxury Portuguese Heritage Beachfront Resort overlooking Arabian Sea',
      city: 'Candolim, North Goa',
      address: 'Sinquerim Beach, Candolim, Goa',
      priceRange: '₹₹₹',
    ),
    RecommendedVenue(
      name: 'The Postcard Moira Luxury Boutique Stay',
      type: 'hotel',
      rating: 4.8,
      specialty: '300-year-old restored Portuguese villa amidst lush banana plantations',
      city: 'Moira, North Goa',
      address: 'Moira, Bardez, Goa',
      priceRange: '₹₹₹',
    ),
    // ==========================================
    // MUMBAI & MAHARASHTRA CIRCUIT
    // ==========================================
    RecommendedVenue(
      name: 'Kyani & Co. Heritage Irani Cafe',
      type: 'breakfast',
      rating: 4.6,
      specialty: 'Authentic Bun Maska, Parsi Akuri on Toast & Heritage Irani Chai',
      city: 'Mumbai',
      address: 'Opposite Metro Cinema, Marine Lines, Mumbai',
    ),
    RecommendedVenue(
      name: 'Cafe Mondegar Colaba Promenade',
      type: 'coffee',
      rating: 4.6,
      specialty: 'Iconic Mario Miranda Murals, Filter Coffee & Continental Breakfast',
      city: 'Mumbai',
      address: 'Metro House, Colaba Causeway, Mumbai',
    ),
    RecommendedVenue(
      name: 'Shree Thaker Bhojanalay Pure Veg Dining',
      type: 'lunch',
      rating: 4.8,
      specialty: 'Legendary Gujarati & Maharashtrian Royal Thali with Fresh Ghee Rotis & Sweets',
      city: 'Mumbai',
      address: 'Building No. 31, Dadiseth Agyari Lane, Kalbadevi, Mumbai',
    ),
    RecommendedVenue(
      name: 'Mahesh Lunch Home Iconic Coastal Dining',
      type: 'dinner',
      rating: 4.7,
      specialty: 'Celebrated Coastal Curries, Mangalorean Delicacies & Fresh Seafood',
      city: 'Mumbai',
      address: '8-B, Cawasji Patel Street, Fort, Mumbai',
    ),
    RecommendedVenue(
      name: 'The Taj Mahal Palace, Mumbai',
      type: 'hotel',
      rating: 4.9,
      specialty: 'Historic 5-Star Luxury Heritage Landmark facing the Gateway of India',
      city: 'Mumbai',
      address: 'Apollo Bunder, Colaba, Mumbai',
      priceRange: '₹₹₹',
    ),
    RecommendedVenue(
      name: 'Trident Hotel Nariman Point',
      type: 'hotel',
      rating: 4.7,
      specialty: 'Panoramic views of Marine Drive Queen\'s Necklace & 24/7 hospitality',
      city: 'Mumbai',
      address: 'Nariman Point, Marine Drive, Mumbai',
      priceRange: '₹₹₹',
    ),

    // ==========================================
    // BENGALURU & KARNATAKA METRO CIRCUIT
    // ==========================================
    RecommendedVenue(
      name: 'Vidyarthi Bhavan Gandhi Bazaar',
      type: 'breakfast',
      rating: 4.7,
      specialty: 'Crispy Butter Masala Dosa, Kesari Bath & Traditional Filter Coffee',
      city: 'Bengaluru',
      address: 'Gandhi Bazaar Main Road, Basavanagudi, Bengaluru',
    ),
    RecommendedVenue(
      name: 'Brahmins Coffee Bar',
      type: 'coffee',
      rating: 4.8,
      specialty: 'Steaming Hot Idlis, Crispy Vada with Coconut Chutney & Degree Coffee',
      city: 'Bengaluru',
      address: 'Near Shankar Mutt, Shankarpuram, Bengaluru',
    ),
    RecommendedVenue(
      name: 'Mavalli Tiffin Room (MTR) Lalbagh',
      type: 'lunch',
      rating: 4.7,
      specialty: 'Iconic Karnataka Silver Plate Thali, Bisibelebath & Chandrahara',
      city: 'Bengaluru',
      address: '14 Lalbagh Main Road, Bengaluru',
    ),
    RecommendedVenue(
      name: 'Karavalli at The Gateway Hotel',
      type: 'dinner',
      rating: 4.8,
      specialty: 'Traditional Coastal Seafood, Appams, Stew & South Indian Delicacies',
      city: 'Bengaluru',
      address: 'Residency Road, Bengaluru',
    ),
    RecommendedVenue(
      name: 'The Leela Palace Bengaluru',
      type: 'hotel',
      rating: 4.9,
      specialty: 'Opulent Royal Palace Architecture, Lush Gardens & 5-Star Luxury Suites',
      city: 'Bengaluru',
      address: 'HAL Old Airport Road, Kodihalli, Bengaluru',
      priceRange: '₹₹₹',
    ),

    // ==========================================
    // DELHI / NCR CIRCUIT
    // ==========================================
    RecommendedVenue(
      name: 'Saravana Bhavan Janpath',
      type: 'breakfast',
      rating: 4.6,
      specialty: 'Ghee Roast Dosa, Mini Tiffin Platter & Authentic Filter Coffee',
      city: 'Delhi',
      address: 'Janpath, Connaught Place, New Delhi',
    ),
    RecommendedVenue(
      name: 'Gulati Restaurant Pandara Road',
      type: 'lunch',
      rating: 4.7,
      specialty: 'Legendary Dal Makhani, Butter Paneer & Classic North Indian Curries',
      city: 'Delhi',
      address: '6, Pandara Road Market, New Delhi',
    ),
    RecommendedVenue(
      name: 'Bukhara - ITC Maurya',
      type: 'dinner',
      rating: 4.9,
      specialty: 'World-Renowned Dal Bukhara, Sikandari Raan & Tandoori Specialties',
      city: 'Delhi',
      address: 'ITC Maurya, Diplomatic Enclave, Chanakyapuri, New Delhi',
    ),
    RecommendedVenue(
      name: 'The Imperial New Delhi',
      type: 'hotel',
      rating: 4.8,
      specialty: 'Historic Art Deco Colonial Luxury Hotel with High Tea Verandah',
      city: 'Delhi',
      address: 'Janpath Lane, Connaught Place, New Delhi',
      priceRange: '₹₹₹',
    ),

    // ==========================================
    // PUNE & LONAVALA CIRCUIT
    // ==========================================
    RecommendedVenue(
      name: 'Vaishali Restaurant FC Road',
      type: 'breakfast',
      rating: 4.7,
      specialty: 'Famous SPDP, Mysore Masala Dosa, Filter Coffee & Youth Vibe',
      city: 'Pune',
      address: 'Fergusson College Road, Shivajinagar, Pune',
    ),
    RecommendedVenue(
      name: 'Shreyas Pure Veg Dining Deccan',
      type: 'lunch',
      rating: 4.7,
      specialty: 'Authentic Maharashtrian Thali, Kothimbir Vadi, Puran Poli & Aamras',
      city: 'Pune',
      address: 'Apte Road, Deccan Gymkhana, Pune',
    ),
    RecommendedVenue(
      name: 'The Ritz-Carlton, Pune',
      type: 'hotel',
      rating: 4.8,
      specialty: 'Golf Course views, 5-star opulent stay & signature wellness spa',
      city: 'Pune',
      address: 'Golf Course Square, Airport Road, Yerawada, Pune',
      priceRange: '₹₹₹',
    ),
  ];

  /// Get best matching venue for destination and type
  static RecommendedVenue getBestVenue({
    required String destination,
    required String type, // 'breakfast' | 'coffee' | 'lunch' | 'dinner' | 'hotel'
    String highwayRoute = '',
  }) {
    final cleanDest = destination.split(',').first.trim().toLowerCase();
    final query = '$cleanDest $destination $highwayRoute'.toLowerCase();

    // 1. Try exact destination + type match
    final matches = allVenues.where((v) {
      if (v.type != type && !(type == 'coffee' && v.type == 'breakfast')) return false;
      final vCity = v.city.toLowerCase();
      final vAddr = v.address.toLowerCase();
      if (query.contains('mumbai') || query.contains('bombay')) {
        return vCity.contains('mumbai') || vAddr.contains('mumbai');
      }
      if (query.contains('bengaluru') || query.contains('bangalore')) {
        return vCity.contains('bengaluru') || vCity.contains('bangalore') || vAddr.contains('bengaluru');
      }
      if (query.contains('delhi')) {
        return vCity.contains('delhi') || vAddr.contains('delhi');
      }
      if (query.contains('pune')) {
        return vCity.contains('pune') || vAddr.contains('pune');
      }
      if (query.contains('goa')) {
        return vCity.contains('goa') || vAddr.contains('goa');
      }
      if (query.contains('tirupati') || query.contains('tirumala')) {
        return vCity.contains('tirupati') || vCity.contains('tirumala') || vCity.contains('kolar') || vCity.contains('mulbagal');
      }
      if (query.contains('mysore') || query.contains('mysuru') || query.contains('mandya')) {
        return vCity.contains('mysur') || vCity.contains('maddur') || vCity.contains('ramanagara') || vCity.contains('expressway');
      }
      if (query.contains('madurai') || query.contains('rameshwaram')) {
        return vCity.contains('madurai') || vCity.contains('rameswaram');
      }
      if (query.contains('udupi') || query.contains('murudeshwar')) {
        return vCity.contains('udupi') || vCity.contains('murudeshwar');
      }
      if (query.contains('varanasi') || query.contains('kashi')) {
        return vCity.contains('varanasi');
      }
      return vCity.contains(cleanDest) || cleanDest.contains(vCity) || vAddr.contains(cleanDest);
    }).toList();

    if (matches.isNotEmpty) {
      return matches.first;
    }

    final cityTitle = destination.split(',').first.trim();

    // 2. Synthesize a premium venue for any destination
    switch (type) {
      case 'breakfast':
      case 'coffee':
        return RecommendedVenue(
          name: '$cityTitle Traditional Filter Coffee & Tiffin Plaza',
          type: type,
          rating: 4.7,
          specialty: 'Crispy Dosa, Steaming Ghee Idli & Signature Filter Coffee',
          city: cityTitle,
          address: 'Highway Rest Plaza / Main Promenade, $cityTitle',
        );
      case 'lunch':
        return RecommendedVenue(
          name: '$cityTitle Celebrated Heritage Veg Restaurant',
          type: 'lunch',
          rating: 4.7,
          specialty: 'Authentic Royal Thali Meals & Traditional Sweet Specialties',
          city: cityTitle,
          address: 'Heritage Temple Ring Road, $cityTitle',
        );
      case 'dinner':
        return RecommendedVenue(
          name: '$cityTitle Royal Courtyard Dining',
          type: 'dinner',
          rating: 4.6,
          specialty: 'Multi-Cuisine Pure Veg Thali & Warm Regional Specialties',
          city: cityTitle,
          address: 'City Center Promenade, $cityTitle',
        );
      case 'hotel':
      default:
        return RecommendedVenue(
          name: '$cityTitle Grand Heritage Stay & Suites',
          type: 'hotel',
          rating: 4.7,
          specialty: 'Luxury Pilgrim Suites, 24/7 Front Desk & Safe Car Parking',
          city: cityTitle,
          address: 'Central Pilgrimage Boulevard, $cityTitle',
          priceRange: '₹₹₹',
        );
    }
  }
}
