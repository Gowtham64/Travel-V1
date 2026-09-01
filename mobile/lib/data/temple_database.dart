/// Curated Indian Temple & Pilgrimage Knowledge Base
/// Contains rich details: Deities, Star Ratings, Darshan Timings, Historical Highlights,
/// and Pilgrimage significance.
class TempleInfo {
  final String canonicalName;
  final List<String> aliases;
  final double rating;
  final int reviewsCount;
  final String deity;
  final String timing;
  final String description;
  final String highlights;
  final String categoryType;
  final String city;
  final String state;
  final double? lat;
  final double? lng;

  const TempleInfo({
    required this.canonicalName,
    required this.aliases,
    required this.rating,
    required this.reviewsCount,
    required this.deity,
    required this.timing,
    required this.description,
    required this.highlights,
    this.categoryType = '🛕 Hindu temple',
    required this.city,
    required this.state,
    this.lat,
    this.lng,
  });
}

class TempleDatabase {
  TempleDatabase._();

  static const List<TempleInfo> allTemples = [
    // --- TIRUPATI & TIRUMALA CIRCUIT ---
    TempleInfo(
      canonicalName: 'Sri Venkateswara Swamy Temple',
      aliases: ['tirumala', 'tirupati balaji', 'venkateswara', 'ttd temple', 'seven hills', 'balaji'],
      rating: 4.8,
      reviewsCount: 142000,
      deity: 'Lord Venkateswara (Balaji / Govinda)',
      timing: 'Opens 5:00 AM · Closes 11:30 PM',
      description: 'World-renowned hilltop shrine located on the Seventh Peak (Venkatadri) of Seshachalam Hills. One of the most sacred pilgrimage centers on Earth.',
      highlights: 'Golden Ananda Nilayam vimana, Tirupati Laddu prasadam, Swami Pushkarini holy tank',
      city: 'Tirumala, Tirupati',
      state: 'Andhra Pradesh',
      lat: 13.6833,
      lng: 79.3472,
    ),
    TempleInfo(
      canonicalName: 'Shri Varaha Swamy Temple',
      aliases: ['varaha swamy', 'adi varaha temple', 'varahaswamy'],
      rating: 4.8,
      reviewsCount: 18500,
      deity: 'Lord Adi Varaha Swamy',
      timing: 'Opens 5:00 AM · Closes 9:00 PM',
      description: 'Ancient shrine on the northern bank of Swami Pushkarini. By sacred tradition, pilgrims must pay respects here before entering Lord Venkateswara temple.',
      highlights: 'Traditional first darshan protocol, holy Swami Pushkarini views',
      city: 'Tirumala, Tirupati',
      state: 'Andhra Pradesh',
      lat: 13.6841,
      lng: 79.3488,
    ),
    TempleInfo(
      canonicalName: 'Sri Bedi Anjaneya Swamy Temple',
      aliases: ['bedi anjaneya', 'bedi hanuman temple', 'tirumala hanuman'],
      rating: 4.8,
      reviewsCount: 12400,
      deity: 'Lord Hanuman (Bedi Anjaneya)',
      timing: 'Opens 5:30 AM · Closes 9:30 PM',
      description: 'Revered temple located directly opposite the Mahadwaram of Sri Venkateswara Temple, where Lord Hanuman is depicted with folded hands.',
      highlights: 'Directly opposite main temple gopuram, traditional post-darshan stop',
      city: 'Tirumala, Tirupati',
      state: 'Andhra Pradesh',
      lat: 13.6830,
      lng: 79.3470,
    ),
    TempleInfo(
      canonicalName: 'Sri Padmavathi Ammavari Temple',
      aliases: ['padmavathi', 'tiruchanur', 'alamelu manga', 'padmavathi ammavaru'],
      rating: 4.7,
      reviewsCount: 45000,
      deity: 'Goddess Padmavathi (Alamelu Manga)',
      timing: 'Opens 5:00 AM · Closes 9:00 PM',
      description: 'Located in Tiruchanur, 5 km from Tirupati. Pilgrimage to Tirupati is considered complete only after seeking Goddess Padmavathi blessings.',
      highlights: 'Sacred Padma Sarovaram tank, grand Brahmotsavam celebrations, divine consort of Balaji',
      city: 'Tiruchanur, Tirupati',
      state: 'Andhra Pradesh',
      lat: 13.6067,
      lng: 79.4489,
    ),
    TempleInfo(
      canonicalName: 'Sri Govindaraja Swamy Temple',
      aliases: ['govindaraja', 'govindarajaswamy', 'tirupati central temple'],
      rating: 4.7,
      reviewsCount: 38000,
      deity: 'Lord Govindaraja Swamy (Resting Vishnu Posture)',
      timing: 'Opens 5:00 AM · Closes 9:30 PM',
      description: 'Monumental 12th-century Vaishnavite temple consecrated by Saint Ramanujacharya in the heart of Tirupati with towering Raja Gopuram.',
      highlights: 'Sprawling ancient courtyards, Vijayanagara stone pillars, monumental gopuram',
      city: 'Tirupati',
      state: 'Andhra Pradesh',
      lat: 13.6291,
      lng: 79.4182,
    ),
    TempleInfo(
      canonicalName: 'Sri Kapileswara Swamy Temple & Kapila Theertham',
      aliases: ['kapileswara', 'kapila theertham', 'kapila theertham falls'],
      rating: 4.7,
      reviewsCount: 29000,
      deity: 'Lord Shiva (Kapileswara)',
      timing: 'Opens 5:00 AM · Closes 8:00 PM',
      description: 'The only major Shiva temple in Tirupati, situated right at the foothills of Tirumala amidst natural waterfalls and lush mountain streams.',
      highlights: 'Sacred Kapila Theertham mountain waterfall, ancient rock-cut Shiva lingam',
      city: 'Tirupati',
      state: 'Andhra Pradesh',
      lat: 13.6534,
      lng: 79.4278,
    ),
    TempleInfo(
      canonicalName: 'Sri Kalyana Venkateswara Swamy Temple',
      aliases: ['srinivasa mangapuram', 'kalyana venkateswara'],
      rating: 4.7,
      reviewsCount: 22000,
      deity: 'Lord Kalyana Venkateswara',
      timing: 'Opens 5:30 AM · Closes 8:30 PM',
      description: 'Located at Srinivasa Mangapuram (12 km west). Lord Venkateswara and Goddess Padmavathi stayed here for 6 months after their divine wedding.',
      highlights: 'Special prayers for newlyweds and marriage obstacles, peaceful heritage atmosphere',
      city: 'Srinivasa Mangapuram, Tirupati',
      state: 'Andhra Pradesh',
      lat: 13.6169,
      lng: 79.3142,
    ),
    TempleInfo(
      canonicalName: 'Sri Kodanda Rama Swami Temple',
      aliases: ['kodanda rama', 'kodandaramaswamy'],
      rating: 4.7,
      reviewsCount: 16000,
      deity: 'Lord Rama, Sita Devi & Lakshmana',
      timing: 'Opens 6:00 AM · Closes 8:30 PM',
      description: 'Historic 10th-century Chola-built temple commemorating Lord Rama, Sita, and Lakshmana resting on their victorious return from Lanka.',
      highlights: 'Centuries-old stone architecture, adjacent sacred Pushkarini tank',
      city: 'Tirupati',
      state: 'Andhra Pradesh',
      lat: 13.6339,
      lng: 79.4167,
    ),
    TempleInfo(
      canonicalName: 'Srikalahasti Temple',
      aliases: ['srikalahasti', 'kalahasti', 'vayu lingam', 'rahu ketu temple'],
      rating: 4.7,
      reviewsCount: 52000,
      deity: 'Lord Shiva (Kalahasteeswara) & Gnana Prasunambika',
      timing: 'Opens 5:30 AM · Closes 9:00 PM',
      description: 'One of the Pancha Bhoota Stalas representing Vayu (Air element) on the banks of Swarnamukhi River. World-famous for Rahu-Ketu dosha nivarana.',
      highlights: 'Vayu Lingam with perpetual flickering lamp, massive monolithic gopurams, Chola architecture',
      city: 'Srikalahasti',
      state: 'Andhra Pradesh',
      lat: 13.7498,
      lng: 79.6984,
    ),
    TempleInfo(
      canonicalName: 'Kanipakam Vinayaka Temple',
      aliases: ['kanipakam', 'varasidhi vinayaka', 'kanipakam ganesha'],
      rating: 4.7,
      reviewsCount: 41000,
      deity: 'Lord Varasidhi Vinayaka (Swayambhu Ganesha)',
      timing: 'Opens 5:00 AM · Closes 9:00 PM',
      description: 'Famous for its Swayambhu (self-manifested) idol of Lord Ganesha inside a natural well of water that miraculously continues to grow over centuries.',
      highlights: 'Sacred water well sanctum, holy Bahuda river spring, wish-fulfilling deity',
      city: 'Kanipakam, Chittoor',
      state: 'Andhra Pradesh',
      lat: 13.2798,
      lng: 79.0353,
    ),

    // --- KARNATAKA & BENGALURU / MYSORE CIRCUIT ---
    TempleInfo(
      canonicalName: 'Sri Chamundeshwari Temple',
      aliases: ['chamundeshwari', 'chamundi hill', 'chamundi temple', 'mysore temple'],
      rating: 4.8,
      reviewsCount: 68000,
      deity: 'Goddess Chamundeshwari (Durga)',
      timing: 'Opens 7:30 AM · Closes 9:00 PM',
      description: 'Prominent Shakti Peetha atop the 1000m Chamundi Hills overlooking Mysuru city. Features the slaying of demon Mahishasura.',
      highlights: 'Seven-tier Raja Gopuram, 1000-step ancient hill staircase, monolithic 16-ft Nandi statue',
      city: 'Chamundi Hills, Mysuru',
      state: 'Karnataka',
      lat: 12.2753,
      lng: 76.6702,
    ),
    TempleInfo(
      canonicalName: 'Sri Ranganathaswamy Temple (Srirangapatna)',
      aliases: ['srirangapatna temple', 'adi ranga', 'ranganatha swamy srirangapatna'],
      rating: 4.8,
      reviewsCount: 36000,
      deity: 'Lord Ranganatha (Adi Ranga - Resting Vishnu)',
      timing: 'Opens 6:00 AM · Closes 8:30 PM',
      description: 'One of the five sacred Pancharanga Kshetrams on an island formed by the Kaveri River. Founded in 894 AD with magnificent Hoysala & Vijayanagara craft.',
      highlights: 'Sacred Kaveri island shrine, monolithic Vishnu idol on Adisesha, ancient sanctum',
      city: 'Srirangapatna',
      state: 'Karnataka',
      lat: 12.4245,
      lng: 76.6793,
    ),
    TempleInfo(
      canonicalName: 'Sri Nimishamba Temple',
      aliases: ['nimishamba', 'nimishambha temple'],
      rating: 4.7,
      reviewsCount: 19000,
      deity: 'Goddess Nimishamba (Incarnation of Parvati)',
      timing: 'Opens 6:30 AM · Closes 8:30 PM',
      description: 'Picturesque temple on the banks of River Kaveri. Devotees believe Goddess Nimishamba removes all distress within a minute (Nimisha).',
      highlights: 'Scenic riverbank Kaveri ghats, Sri Chakra carving, wish-fulfilling deity',
      city: 'Ganjam, Srirangapatna',
      state: 'Karnataka',
      lat: 12.4182,
      lng: 76.7112,
    ),
    TempleInfo(
      canonicalName: 'Sri Srikanteshwara Temple (Nanjangud)',
      aliases: ['nanjangud', 'srikanteshwara', 'nanjundeshwara', 'dakshina kashi'],
      rating: 4.8,
      reviewsCount: 31000,
      deity: 'Lord Shiva (Nanjundeshwara / Srikanteshwara)',
      timing: 'Opens 6:00 AM · Closes 8:30 PM',
      description: 'Known as the "Dakshina Kashi", this massive temple on the banks of Kapila River is renowned for miraculous healing waters and ancient Shaivite lore.',
      highlights: 'Sprawling Dravidian temple complex, Kapila River Sangama, historic chariot festival',
      city: 'Nanjangud, Mysuru',
      state: 'Karnataka',
      lat: 12.1194,
      lng: 76.6811,
    ),
    TempleInfo(
      canonicalName: 'Sri Gavi Gangadhareshwara Temple',
      aliases: ['gavi gangadhareshwara', 'gavipuram cave temple'],
      rating: 4.7,
      reviewsCount: 17000,
      deity: 'Lord Shiva (Gangadhareshwara)',
      timing: 'Opens 6:00 AM · Closes 8:00 PM',
      description: 'Famous 9th-century rock-cut cave temple in Bengaluru with monolithic stone discs (Suryamajik) and natural astronomical alignment on Makar Sankranti.',
      highlights: 'Sunlight illuminates inner Shiva lingam on Sankranti, ancient subterranean caves',
      city: 'Gavipuram, Bengaluru',
      state: 'Karnataka',
      lat: 12.9482,
      lng: 77.5634,
    ),
    TempleInfo(
      canonicalName: 'Sri Bull Temple (Dodda Basavana Gudi)',
      aliases: ['bull temple', 'dodda basavana gudi', 'nandi temple basavanagudi'],
      rating: 4.7,
      reviewsCount: 28000,
      deity: 'Sacred Nandi (Dodda Basava)',
      timing: 'Opens 6:00 AM · Closes 8:30 PM',
      description: 'Houses one of the largest monolithic Nandi statues in the world, carved from a single piece of granite by Kempegowda in 1537.',
      highlights: 'Massive 4.5m high monolithic granite Nandi, annual Kadalekai Parishe peanut festival',
      city: 'Basavanagudi, Bengaluru',
      state: 'Karnataka',
      lat: 12.9421,
      lng: 77.5681,
    ),
    TempleInfo(
      canonicalName: 'Kukke Subramanya Temple',
      aliases: ['kukke', 'kukke subramanya', 'subramanya swamy'],
      rating: 4.9,
      reviewsCount: 62000,
      deity: 'Lord Subramanya (Kartikeya / Snake Deity)',
      timing: 'Opens 6:00 AM · Closes 8:30 PM',
      description: 'Nestled in the lush Western Ghats beneath Kumara Parvatha. Premier pilgrimage destination for Sarpa Samskara and Ashlesha Bali pujas.',
      highlights: 'Sarpa Dosha pujas, holy Kumaradhara river bath, Western Ghats mountain backdrop',
      city: 'Subramanya, Dakshina Kannada',
      state: 'Karnataka',
      lat: 12.6631,
      lng: 75.6172,
    ),
    TempleInfo(
      canonicalName: 'Dharmasthala Sri Manjunatha Swamy Temple',
      aliases: ['dharmasthala', 'manjunatha temple', 'dharmasthala manjunatha'],
      rating: 4.9,
      reviewsCount: 74000,
      deity: 'Lord Shiva (Manjunatha Swamy)',
      timing: 'Opens 6:30 AM · Closes 8:30 PM',
      description: 'Renowned 800-year-old pilgrimage shrine on the Netravati River representing harmony where Jain Heggade administration oversees Hindu worship.',
      highlights: 'Legendary Annadana (free community meals for thousands daily), massive Bahubali statue',
      city: 'Dharmasthala, Dakshina Kannada',
      state: 'Karnataka',
      lat: 12.9567,
      lng: 75.3789,
    ),
    TempleInfo(
      canonicalName: 'Murudeshwar Shiva Temple',
      aliases: ['murudeshwar', 'murudeshwara temple', 'tallest shiva statue'],
      rating: 4.8,
      reviewsCount: 58000,
      deity: 'Lord Shiva',
      timing: 'Opens 6:00 AM · Closes 8:30 PM',
      description: 'Spectacular seaside temple on the Kanduka Hill surrounded on three sides by the Arabian Sea, featuring the world\'s second-tallest Shiva statue (123 ft).',
      highlights: '123-ft colossal Shiva statue, 20-tier Raja Gopuram with lift to 18th floor viewing deck',
      city: 'Murudeshwar, Uttara Kannada',
      state: 'Karnataka',
      lat: 14.0942,
      lng: 74.4849,
    ),
    TempleInfo(
      canonicalName: 'Udupi Sri Krishna Matha',
      aliases: ['udupi krishna', 'krishna matha', 'kanakana kindi'],
      rating: 4.9,
      reviewsCount: 51000,
      deity: 'Lord Krishna (Bala Krishna)',
      timing: 'Opens 5:30 AM · Closes 9:00 PM',
      description: 'Historic 13th-century monastery founded by saint Madhvacharya. Famous for the Kanakana Kindi, a silver-plated window through which Lord Krishna turned.',
      highlights: 'Kanakana Kindi window darshan, traditional Udupi cuisine prasadam, Ashta Mathas',
      city: 'Udupi',
      state: 'Karnataka',
      lat: 13.3409,
      lng: 74.7516,
    ),
  ];

  /// Find rich temple info for any search query or place name
  static TempleInfo? findTemple(String name) {
    final lower = name.toLowerCase().trim();
    for (final t in allTemples) {
      if (t.canonicalName.toLowerCase() == lower) return t;
      for (final a in t.aliases) {
        if (lower.contains(a) || a.contains(lower)) return t;
      }
    }
    return null;
  }

  /// Resolve rich, verified attractions & temples for any destination and query
  static List<TempleInfo> getAttractionPool({
    required String destination,
    String preferences = '',
    List<String> places = const [],
  }) {
    final text = '$destination $preferences ${places.join(" ")}'.toLowerCase();

    // Check for Tirupati / Tirumala / Andhra Pilgrimage
    if (text.contains('tirupati') || text.contains('tirumala') || text.contains('balaji') || text.contains('srikalahasti') || text.contains('kanipakam') || text.contains('venkateswara')) {
      return allTemples.where((t) => t.city.contains('Tirupati') || t.city.contains('Tirumala') || t.city.contains('Srikalahasti') || t.city.contains('Kanipakam')).toList();
    }

    // Check for Mysuru / Srirangapatna / Nanjangud
    if (text.contains('mysore') || text.contains('mysuru') || text.contains('chamundi') || text.contains('srirangapatna') || text.contains('nanjangud') || text.contains('mandya')) {
      return allTemples.where((t) => t.city.contains('Mysuru') || t.city.contains('Srirangapatna') || t.city.contains('Nanjangud')).toList();
    }

    // Check for Coastal Karnataka / Western Ghats / Udupi
    if (text.contains('udupi') || text.contains('murudeshwar') || text.contains('dharmasthala') || text.contains('kukke') || text.contains('subramanya') || text.contains('gokarna') || text.contains('mangalore')) {
      return allTemples.where((t) => t.city.contains('Dakshina Kannada') || t.city.contains('Uttara Kannada') || t.city.contains('Udupi')).toList();
    }

    // Check for Bengaluru
    if (text.contains('bengaluru') || text.contains('bangalore')) {
      return allTemples.where((t) => t.city.contains('Bengaluru')).toList();
    }

    // Default: If specific places list provided, map them
    if (places.isNotEmpty) {
      final res = <TempleInfo>[];
      for (final p in places) {
        final match = findTemple(p);
        if (match != null) res.add(match);
      }
      if (res.isNotEmpty) return res;
    }

    // Fallback: return top rated temples
    return allTemples;
  }
}
