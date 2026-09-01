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
  final String? darshanWaitInfo;
  final int recommendedDarshanMinutes;
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
    this.darshanWaitInfo,
    this.recommendedDarshanMinutes = 60,
    this.lat,
    this.lng,
  });
}

class TempleDatabase {
  TempleDatabase._();

  static const List<TempleInfo> allTemples = [
    // --- TIRUPATI & TIRUMALA CIRCUIT (Canonical Pilgrimage Order) ---
    TempleInfo(
      canonicalName: 'Shri Varaha Swamy Temple',
      aliases: ['varaha swamy', 'adi varaha temple', 'varahaswamy', 'varaha'],
      rating: 4.8,
      reviewsCount: 18500,
      deity: 'Lord Adi Varaha Swamy',
      timing: 'Opens 5:00 AM · Closes 9:00 PM',
      description: 'Ancient shrine on the northern bank of Swami Pushkarini. By sacred tradition, pilgrims must pay respects here before entering Lord Venkateswara temple.',
      highlights: 'Traditional first darshan protocol, holy Swami Pushkarini views',
      city: 'Tirumala, Tirupati',
      state: 'Andhra Pradesh',
      darshanWaitInfo: 'Queue wait: 30–60 mins',
      recommendedDarshanMinutes: 60,
      lat: 13.6841,
      lng: 79.3488,
    ),
    TempleInfo(
      canonicalName: 'Sri Venkateswara Swamy Temple',
      aliases: ['tirumala balaji', 'venkateswara temple', 'ttd temple', 'seven hills', 'tirupati balaji', 'venkateswara swamy'],
      rating: 4.8,
      reviewsCount: 142000,
      deity: 'Lord Venkateswara (Balaji / Govinda)',
      timing: 'Opens 5:00 AM · Closes 11:30 PM',
      description: 'World-renowned hilltop shrine located on the Seventh Peak (Venkatadri) of Seshachalam Hills. One of the most sacred pilgrimage centers on Earth.',
      highlights: 'Golden Ananda Nilayam vimana, Tirupati Laddu prasadam, Swami Pushkarini holy tank',
      city: 'Tirumala, Tirupati',
      state: 'Andhra Pradesh',
      darshanWaitInfo: 'SED (₹300): 3–4 hrs · SSD Slotted: 4–6 hrs · Free Q: 8–12 hrs · VIP/SRIVANI: ~1 hr',
      recommendedDarshanMinutes: 240,
      lat: 13.6833,
      lng: 79.3472,
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
      darshanWaitInfo: 'Queue wait: 20–45 mins',
      recommendedDarshanMinutes: 45,
      lat: 13.6830,
      lng: 79.3470,
    ),
    TempleInfo(
      canonicalName: 'Sri Padmavathi Ammavari Temple',
      aliases: ['padmavathi ammavari', 'padmavathi temple', 'tiruchanur temple', 'alamelu manga'],
      rating: 4.7,
      reviewsCount: 45000,
      deity: 'Goddess Padmavathi (Alamelu Manga)',
      timing: 'Opens 5:00 AM · Closes 9:00 PM',
      description: 'Located in Tiruchanur, 5 km from Tirupati. Pilgrimage to Tirupati is considered complete only after seeking Goddess Padmavathi blessings.',
      highlights: 'Sacred Padma Sarovaram tank, grand Brahmotsavam celebrations, divine consort of Balaji',
      city: 'Tiruchanur, Tirupati',
      state: 'Andhra Pradesh',
      darshanWaitInfo: 'Special Darshan: 1–2 hrs · General Q: 2–3 hrs',
      recommendedDarshanMinutes: 90,
      lat: 13.6067,
      lng: 79.4489,
    ),
    TempleInfo(
      canonicalName: 'Sri Kalyana Venkateswara Swamy Temple',
      aliases: ['srinivasa mangapuram temple', 'kalyana venkateswara'],
      rating: 4.7,
      reviewsCount: 22000,
      deity: 'Lord Kalyana Venkateswara',
      timing: 'Opens 5:30 AM · Closes 8:30 PM',
      description: 'Located at Srinivasa Mangapuram (12 km west). Lord Venkateswara and Goddess Padmavathi stayed here for 6 months after their divine wedding.',
      highlights: 'Special prayers for newlyweds and marriage obstacles, peaceful heritage atmosphere',
      city: 'Srinivasa Mangapuram, Tirupati',
      state: 'Andhra Pradesh',
      darshanWaitInfo: 'Darshan wait: 30–60 mins',
      recommendedDarshanMinutes: 60,
      lat: 13.6169,
      lng: 79.3142,
    ),
    TempleInfo(
      canonicalName: 'Sri Kapileswara Swamy Temple & Kapila Theertham',
      aliases: ['kapileswara swamy', 'kapila theertham temple', 'kapileswara'],
      rating: 4.7,
      reviewsCount: 29000,
      deity: 'Lord Shiva (Kapileswara)',
      timing: 'Opens 5:00 AM · Closes 8:00 PM',
      description: 'The only major Shiva temple in Tirupati, situated right at the foothills of Tirumala amidst natural waterfalls and lush mountain streams.',
      highlights: 'Sacred Kapila Theertham mountain waterfall, ancient rock-cut Shiva lingam',
      city: 'Tirupati',
      state: 'Andhra Pradesh',
      darshanWaitInfo: 'Darshan wait: 30–60 mins',
      recommendedDarshanMinutes: 60,
      lat: 13.6534,
      lng: 79.4278,
    ),
    TempleInfo(
      canonicalName: 'Sri Govindaraja Swamy Temple',
      aliases: ['govindaraja swamy', 'govindarajaswamy temple', 'govindaraja'],
      rating: 4.7,
      reviewsCount: 38000,
      deity: 'Lord Govindaraja Swamy (Resting Vishnu Posture)',
      timing: 'Opens 5:00 AM · Closes 9:30 PM',
      description: 'Monumental 12th-century Vaishnavite temple consecrated by Saint Ramanujacharya in the heart of Tirupati with towering Raja Gopuram.',
      highlights: 'Sprawling ancient courtyards, Vijayanagara stone pillars, monumental gopuram',
      city: 'Tirupati',
      state: 'Andhra Pradesh',
      darshanWaitInfo: 'Darshan wait: 45–90 mins',
      recommendedDarshanMinutes: 75,
      lat: 13.6291,
      lng: 79.4182,
    ),
    TempleInfo(
      canonicalName: 'Sri Kodanda Rama Swami Temple',
      aliases: ['kodanda rama', 'kodandaramaswamy'],
      rating: 4.7,
      reviewsCount: 14000,
      deity: 'Lord Rama, Goddess Sita & Lakshmana',
      timing: 'Opens 5:00 AM · Closes 8:30 PM',
      description: 'Built by Chola kings to commemorate the return journey of Lord Rama, Sita, and Lakshmana from Lanka.',
      highlights: 'Ancient Chola stone architecture, peaceful city temple',
      city: 'Tirupati',
      state: 'Andhra Pradesh',
      darshanWaitInfo: 'Darshan wait: 20–40 mins',
      recommendedDarshanMinutes: 45,
      lat: 13.6350,
      lng: 79.4150,
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
    // --- TAMIL NADU PILGRIMAGE & HERITAGE ---
    TempleInfo(
      canonicalName: 'Madurai Meenakshi Amman Temple',
      aliases: ['meenakshi amman', 'meenakshi temple', 'madurai temple'],
      rating: 4.9,
      reviewsCount: 110000,
      deity: 'Goddess Meenakshi & Lord Sundareswarar (Shiva)',
      timing: 'Opens 5:00 AM · Closes 10:00 PM',
      description: 'Historic Hindu temple on the southern bank of the Vaigai River. Renowned for its 14 towering gopurams covered in thousands of vibrant mythological sculptures.',
      highlights: 'Hall of Thousand Pillars, Golden Lotus Tank (Porthamarai Kulam), magnificent Dravidian gopurams',
      city: 'Madurai',
      state: 'Tamil Nadu',
      darshanWaitInfo: 'Special Darshan: 1–2 hrs · General Q: 2–3.5 hrs',
      recommendedDarshanMinutes: 180,
      lat: 9.9195,
      lng: 78.1193,
    ),
    TempleInfo(
      canonicalName: 'Rameshwaram Ramanathaswamy Temple',
      aliases: ['rameshwaram temple', 'ramanathaswamy', 'rameshwaram'],
      rating: 4.8,
      reviewsCount: 78000,
      deity: 'Lord Shiva (Ramanathaswamy - Jyotirlinga)',
      timing: 'Opens 5:00 AM · Closes 9:00 PM',
      description: 'One of the Char Dham pilgrimage sites and 12 Jyotirlingas, where Lord Rama prayed to Shiva. Famous for the longest temple corridor in the world.',
      highlights: 'Longest sculpted pillar corridor in the world (1,212 pillars), 22 holy Theertham wells bath ritual',
      city: 'Rameswaram',
      state: 'Tamil Nadu',
      darshanWaitInfo: '22 Theertham Bath + Darshan: 2.5–4 hrs',
      recommendedDarshanMinutes: 210,
      lat: 9.2881,
      lng: 79.3174,
    ),
    TempleInfo(
      canonicalName: 'Brihadisvara Temple (Thanjavur Big Temple)',
      aliases: ['thanjavur big temple', 'brihadisvara', 'peruvudaiyar kovil', 'thanjavur temple'],
      rating: 4.9,
      reviewsCount: 82000,
      deity: 'Lord Shiva (Peruvudaiyar)',
      timing: 'Opens 6:00 AM · Closes 8:30 PM',
      description: 'UNESCO World Heritage monument built by Raja Raja Chola I in 1010 AD. One of the greatest architectural achievements in Indian history.',
      highlights: '216-ft granite Vimana tower, monolithic 80-tonne Kumbam capstone, massive monolithic Nandi',
      city: 'Thanjavur',
      state: 'Tamil Nadu',
      darshanWaitInfo: 'Darshan & Heritage Walk: 1.5–2.5 hrs',
      recommendedDarshanMinutes: 120,
      lat: 10.7828,
      lng: 79.1318,
    ),
    TempleInfo(
      canonicalName: 'Kashi Vishwanath Temple (Varanasi)',
      aliases: ['kashi vishwanath', 'varanasi temple', 'kashi', 'banaras temple'],
      rating: 4.9,
      reviewsCount: 125000,
      deity: 'Lord Shiva (Vishwanath - Jyotirlinga)',
      timing: 'Opens 3:00 AM · Closes 11:00 PM',
      description: 'One of the most sacred Jyotirlinga temples in Hinduism, situated on the western bank of holy River Ganga with the newly built Kashi Vishwanath Corridor.',
      highlights: 'Gold plated spire, sacred Ganga riverfront corridor, world-famous evening Ganga Aarti',
      city: 'Varanasi',
      state: 'Uttar Pradesh',
      darshanWaitInfo: 'Sugam Darshan: 1–1.5 hrs · General Q: 3–5 hrs',
      recommendedDarshanMinutes: 210,
      lat: 25.3109,
      lng: 83.0107,
    ),
    TempleInfo(
      canonicalName: 'Golden Temple (Sri Harmandir Sahib)',
      aliases: ['golden temple', 'harmandir sahib', 'amritsar temple'],
      rating: 4.9,
      reviewsCount: 165000,
      deity: 'Guru Granth Sahib',
      timing: 'Open 24 Hours',
      description: 'The holiest Gurdwara and primary pilgrimage site of Sikhism, surrounded by the holy Amrit Sarovar (Pool of Nectar) and plated with 500 kg of pure gold.',
      highlights: 'Pure gold sanctum in holy sarovar, 24/7 Langar community kitchen serving 100,000 daily',
      city: 'Amritsar',
      state: 'Punjab',
      darshanWaitInfo: 'Parikrama & Sanctum Darshan: 1.5–3 hrs',
      recommendedDarshanMinutes: 150,
      lat: 31.6200,
      lng: 74.8765,
    ),
    TempleInfo(
      canonicalName: 'Shree Jagannath Temple (Puri)',
      aliases: ['puri jagannath', 'jagannath temple', 'puri temple'],
      rating: 4.8,
      reviewsCount: 94000,
      deity: 'Lord Jagannath, Balabhadra & Subhadra',
      timing: 'Opens 5:00 AM · Closes 11:00 PM',
      description: 'One of the four original Char Dham pilgrimage sites, famous for its grand annual Ratha Yatra (Chariot Festival) on the Bay of Bengal coast.',
      highlights: 'Sacred Mahaprasad (Ananda Bazaar), Nilachakra wheel atop vimana, ancient kitchen',
      city: 'Puri',
      state: 'Odisha',
      darshanWaitInfo: 'General Darshan: 2–4 hrs · VIP: 1–1.5 hrs',
      recommendedDarshanMinutes: 180,
      lat: 19.8049,
      lng: 85.8179,
    ),
    // --- Bengaluru Landmark Temples & Heritage ---
    TempleInfo(
      canonicalName: 'ISKCON Temple Bangalore (Hare Krishna Hill)',
      aliases: ['iskcon bangalore', 'iskcon rajajinagar', 'iskcon temple', 'hare krishna hill'],
      rating: 4.8,
      reviewsCount: 110000,
      deity: 'Sri Sri Radha Krishnachandra',
      timing: 'Opens 4:15 AM · 7:15 AM - 1:00 PM · 4:15 PM - 8:30 PM',
      description: 'One of the largest ISKCON complexes in the world, located on Hare Krishna Hill in Rajajinagar featuring magnificent gold-plated dhwaja-stambha and Vedic cultural exhibits.',
      highlights: 'Grand gopuram, evening bhajans, sumptuous Khichdi prasadam and higher taste restaurant',
      city: 'Bengaluru',
      state: 'Karnataka',
      darshanWaitInfo: 'Darshan & Walkthrough: 1–1.5 hrs',
      recommendedDarshanMinutes: 90,
      lat: 13.0098,
      lng: 77.5511,
    ),
    TempleInfo(
      canonicalName: 'Bull Temple (Dodda Basavana Gudi)',
      aliases: ['bull temple', 'dodda basavana gudi', 'basavanagudi temple', 'nandi temple'],
      rating: 4.7,
      reviewsCount: 45000,
      deity: 'Sacred Nandi (Monolithic Bull)',
      timing: 'Opens 6:00 AM · Closes 8:00 PM',
      description: 'Historic 16th-century temple built by Kempe Gowda I, housing one of the largest monolithic Nandi statues in the world carved out of a single granite boulder.',
      highlights: '15-ft tall monolithic Nandi, iconic Bugle Rock park surroundings, groundnut fair (Kadalekai Parishe)',
      city: 'Bengaluru',
      state: 'Karnataka',
      darshanWaitInfo: 'Darshan: 30–45 mins',
      recommendedDarshanMinutes: 45,
      lat: 12.9423,
      lng: 77.5678,
    ),
    TempleInfo(
      canonicalName: 'Sri Gavi Gangadhareshwara Cave Temple',
      aliases: ['gavi gangadhareshwara', 'gavi cave temple', 'gavipuram temple'],
      rating: 4.8,
      reviewsCount: 32000,
      deity: 'Lord Shiva (Gangadhareshwara)',
      timing: 'Opens 6:00 AM · 12:30 PM | 6:00 PM · 8:30 PM',
      description: 'Ancient subterranean rock-cut cave temple famous for astronomical precision where the sun rays illuminate the inner sanctum Shivalinga on Makar Sankranti.',
      highlights: 'Natural rock cave sanctum, monolithic stone discs (Suryamajja), monolithic Trishula & Damaru',
      city: 'Bengaluru',
      state: 'Karnataka',
      darshanWaitInfo: 'Cave Darshan: 30–45 mins',
      recommendedDarshanMinutes: 45,
      lat: 12.9489,
      lng: 77.5612,
    ),
    TempleInfo(
      canonicalName: 'Bangalore Palace & Royal Grounds',
      aliases: ['bangalore palace', 'bengaluru palace', 'royal palace bangalore'],
      rating: 4.7,
      reviewsCount: 68000,
      deity: 'Wodeyar Royal Heritage & Architecture',
      timing: 'Opens 10:00 AM · Closes 5:30 PM',
      description: 'Majestic 19th-century royal palace built in Tudor-style architecture with fortified towers, battlements, elegant woodcarvings, and vintage paintings.',
      highlights: 'Tudor architectural turrets, audio tour of Durbar hall, royal vintage photo galleries',
      city: 'Bengaluru',
      state: 'Karnataka',
      darshanWaitInfo: 'Tour Duration: 1.5–2 hrs',
      recommendedDarshanMinutes: 120,
      lat: 12.9982,
      lng: 77.5921,
    ),
    TempleInfo(
      canonicalName: 'Lalbagh Botanical Garden & Glass House',
      aliases: ['lalbagh', 'lalbagh botanical garden', 'lalbagh glass house'],
      rating: 4.8,
      reviewsCount: 95000,
      deity: 'Heritage Flora & 3000-Million-Year-Old Rock',
      timing: 'Opens 6:00 AM · Closes 7:00 PM',
      description: '240-acre historic botanical garden commissioned by Hyder Ali, featuring India’s largest collection of tropical plants and the iconic 1889 Glass House.',
      highlights: 'Century-old Glass House, Kempegowda watchtower on Lalbagh Rock, serene lake walk',
      city: 'Bengaluru',
      state: 'Karnataka',
      darshanWaitInfo: 'Garden Walk & Exploration: 1.5–2.5 hrs',
      recommendedDarshanMinutes: 120,
      lat: 12.9507,
      lng: 77.5848,
    ),
    // --- Mysuru Heritage & Palaces ---
    TempleInfo(
      canonicalName: 'Mysore Palace (Amba Vilas Palace)',
      aliases: ['mysore palace', 'amba vilas', 'mysuru palace'],
      rating: 4.8,
      reviewsCount: 145000,
      deity: 'Wodeyar Royal Heritage & Durbar',
      timing: 'Opens 10:00 AM · Closes 5:30 PM · Illumination 7:00 PM - 7:45 PM',
      description: 'World-renowned Indo-Saracenic royal palace of the Wadiyar dynasty, illuminated by nearly 100,000 light bulbs every Sunday and holiday evening.',
      highlights: 'Golden Throne, stained glass Kalyana Mantapa ceiling, Gombe Thotti doll pavilion, evening illumination',
      city: 'Mysuru',
      state: 'Karnataka',
      darshanWaitInfo: 'Palace Tour: 2–3 hrs',
      recommendedDarshanMinutes: 150,
      lat: 12.3052,
      lng: 76.6552,
    ),
    TempleInfo(
      canonicalName: 'Brindavan Gardens & Musical Fountain',
      aliases: ['brindavan gardens', 'krs dam gardens', 'musical fountain mysore'],
      rating: 4.7,
      reviewsCount: 88000,
      deity: 'Terraced Gardens & Kaveri Waterway',
      timing: 'Opens 6:30 AM · Closes 9:00 PM · Music show 6:30 PM onwards',
      description: 'Celebrated terrace gardens adjoining the Krishnarajasagara (KRS) Dam across the Kaveri river, famous for evening laser and musical dancing fountains.',
      highlights: 'Symmetric terraced garden walkways, boating in Kaveri lagoon, synchronized musical fountain',
      city: 'Mysuru',
      state: 'Karnataka',
      darshanWaitInfo: 'Garden & Light Show: 2–2.5 hrs',
      recommendedDarshanMinutes: 120,
      lat: 12.4223,
      lng: 76.5742,
    ),
  ];

  /// Find rich temple info for any search query or place name
  static TempleInfo? findTemple(String name) {
    final lower = name.toLowerCase().trim();
    if (lower.isEmpty) return null;
    // Exclude non-temple events
    if (lower.contains('drive') || lower.contains('hotel') || lower.contains('rest') || lower.contains('breakfast') || lower.contains('lunch') || lower.contains('dinner') || lower.contains('coffee') || lower.contains('tea break')) {
      return null;
    }

    for (final t in allTemples) {
      if (t.canonicalName.toLowerCase() == lower) return t;
      if (lower.contains(t.canonicalName.toLowerCase())) return t;
      for (final a in t.aliases) {
        if (lower.contains(a)) return t;
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
    final destClean = destination.toLowerCase();
    final text = '$destination $preferences ${places.join(" ")}'.toLowerCase();

    // 1. Explicit Custom Places Passed by User
    if (places.isNotEmpty) {
      final res = <TempleInfo>[];
      for (final p in places) {
        final match = findTemple(p);
        if (match != null) {
          res.add(match);
        } else {
          res.add(TempleInfo(
            canonicalName: p,
            aliases: [p.toLowerCase()],
            rating: 4.8,
            reviewsCount: 22000,
            deity: 'Prominent Landmark & Attraction',
            timing: 'Opens 8:00 AM · Closes 7:00 PM',
            description: 'Major highlight and popular sightseeing point in $destination.',
            highlights: 'Top-rated sightseeing, cultural heritage, and scenic photography',
            city: destination,
            state: 'India',
            darshanWaitInfo: 'Estimated visit duration: 1.5–2 hrs',
            recommendedDarshanMinutes: 100,
          ));
        }
      }
      if (res.isNotEmpty) return res;
    }

    // 2. Strict Check for Tirupati / Tirumala (ONLY when destination contains Tirupati/Tirumala/Balaji)
    if (destClean.contains('tirupati') || destClean.contains('tirumala') || destClean.contains('balaji') || destClean.contains('srikalahasti') || destClean.contains('kanipakam') || destClean.contains('venkateswara')) {
      return allTemples.where((t) => t.city.contains('Tirupati') || t.city.contains('Tirumala') || t.city.contains('Srikalahasti') || t.city.contains('Kanipakam')).toList();
    }

    // 3. Mysuru / Srirangapatna / Nanjangud / Mandya
    if (destClean.contains('mysore') || destClean.contains('mysuru') || destClean.contains('chamundi') || destClean.contains('srirangapatna') || destClean.contains('nanjangud') || destClean.contains('mandya')) {
      final matches = allTemples.where((t) => t.city.contains('Mysuru') || t.city.contains('Srirangapatna') || t.city.contains('Nanjangud')).toList();
      if (matches.isNotEmpty) return matches;
    }

    // 4. Bengaluru / Bangalore
    if (destClean.contains('bengaluru') || destClean.contains('bangalore') || destClean.contains('mathikere') || destClean.contains('whitefield') || destClean.contains('indiranagar') || destClean.contains('jayanagar') || destClean.contains('malleshwaram')) {
      final matches = allTemples.where((t) => t.city.contains('Bengaluru')).toList();
      if (matches.isNotEmpty) return matches;
    }

    // 5. Coastal Karnataka (Udupi, Murudeshwar, Dharmasthala, Gokarna, Mangalore)
    if (destClean.contains('udupi') || destClean.contains('murudeshwar') || destClean.contains('dharmasthala') || destClean.contains('kukke') || destClean.contains('subramanya') || destClean.contains('gokarna') || destClean.contains('mangalore')) {
      final matches = allTemples.where((t) => t.city.contains('Dakshina Kannada') || t.city.contains('Uttara Kannada') || t.city.contains('Udupi')).toList();
      if (matches.isNotEmpty) return matches;
    }

    // 6. Tamil Nadu (Madurai, Rameshwaram, Thanjavur)
    if (destClean.contains('madurai') || destClean.contains('meenakshi') || destClean.contains('rameshwaram') || destClean.contains('thanjavur')) {
      final matches = allTemples.where((t) => t.state == 'Tamil Nadu').toList();
      if (matches.isNotEmpty) return matches;
    }

    // 7. Varanasi / Kashi
    if (destClean.contains('varanasi') || destClean.contains('kashi') || destClean.contains('banaras')) {
      final matches = allTemples.where((t) => t.city.contains('Varanasi')).toList();
      if (matches.isNotEmpty) return matches;
    }

    // 8. Amritsar
    if (destClean.contains('amritsar') || destClean.contains('harmandir')) {
      final matches = allTemples.where((t) => t.city.contains('Amritsar')).toList();
      if (matches.isNotEmpty) return matches;
    }

    // 9. Puri
    if (destClean.contains('puri') || destClean.contains('jagannath')) {
      final matches = allTemples.where((t) => t.city.contains('Puri')).toList();
      if (matches.isNotEmpty) return matches;
    }

    // 10. Dynamic Tailored Attractions strictly scoped to the user's Destination (NEVER Tirupati!)
    final cityLabel = destination.isNotEmpty ? destination.split(',').first.trim() : 'Destination';
    return [
      TempleInfo(
        canonicalName: '$cityLabel Iconic Heritage Landmark & Historic Grounds',
        aliases: ['heritage', 'monument', 'landmark'],
        rating: 4.8,
        reviewsCount: 38000,
        deity: 'Architectural Monument & Cultural Heritage',
        timing: 'Opens 8:30 AM · Closes 6:00 PM',
        description: 'Iconic royal architectural monument representing the rich cultural heritage and timeless history of $cityLabel.',
        highlights: 'Monumental architecture, historical galleries, manicured courtyard grounds',
        city: cityLabel,
        state: 'Local Region',
        darshanWaitInfo: 'Sightseeing & Tour: 1.5–2.5 hrs',
        recommendedDarshanMinutes: 120,
      ),
      TempleInfo(
        canonicalName: '$cityLabel Sacred Cultural Shrine & Spiritual Sanctum',
        aliases: ['shrine', 'temple', 'sanctum'],
        rating: 4.8,
        reviewsCount: 29000,
        deity: 'Presiding Guardian Deity & Holy Sanctum',
        timing: 'Opens 6:00 AM · Closes 8:30 PM',
        description: 'Historic spiritual sanctuary revered by travelers and pilgrims visiting $cityLabel.',
        highlights: 'Traditional morning aarti, peaceful sanctum ambiance, intricate architecture',
        city: cityLabel,
        state: 'Local Region',
        darshanWaitInfo: 'Sanctum Visit: 1–1.5 hrs',
        recommendedDarshanMinutes: 75,
      ),
      TempleInfo(
        canonicalName: '$cityLabel Waterfront Promenade & Botanical Gardens',
        aliases: ['gardens', 'park', 'lake'],
        rating: 4.7,
        reviewsCount: 24000,
        deity: 'Scenic Flora & Waterside Vista',
        timing: 'Opens 6:30 AM · Closes 7:30 PM',
        description: 'Sprawling landscaped botanical gardens and serene waterside walking promenade in $cityLabel.',
        highlights: 'Lush greenery, scenic boating, fountain illumination, golden hour photography',
        city: cityLabel,
        state: 'Local Region',
        darshanWaitInfo: 'Garden Walk & Leisure: 1–1.5 hrs',
        recommendedDarshanMinutes: 75,
      ),
      TempleInfo(
        canonicalName: '$cityLabel Panoramic Hilltop & Sunset Vista Viewpoint',
        aliases: ['viewpoint', 'hilltop', 'sunset'],
        rating: 4.8,
        reviewsCount: 21000,
        deity: '360° Valley & Panoramic Vistas',
        timing: 'Opens 6:00 AM · Closes 7:00 PM',
        description: 'Elevated viewpoint offering breathtaking panoramic sunrise and sunset vistas across the $cityLabel region.',
        highlights: 'Panoramic landscape photography, cool breeze, scenic cliffside pathways',
        city: cityLabel,
        state: 'Local Region',
        darshanWaitInfo: 'Sunset Viewing: 45–60 mins',
        recommendedDarshanMinutes: 60,
      ),
      TempleInfo(
        canonicalName: '$cityLabel Traditional Crafts & Regional Food Bazaar',
        aliases: ['bazaar', 'market', 'handicrafts'],
        rating: 4.6,
        reviewsCount: 18000,
        deity: 'Artisan Crafts & Regional Delicacies',
        timing: 'Opens 10:00 AM · Closes 9:30 PM',
        description: 'Vibrant local bazaar famous for authentic regional handicrafts, aromatic spices, and traditional culinary street treats in $cityLabel.',
        highlights: 'Handcrafted souvenirs, authentic street specialties, vibrant cultural market',
        city: cityLabel,
        state: 'Local Region',
        darshanWaitInfo: 'Bazaar Exploration: 1–2 hrs',
        recommendedDarshanMinutes: 90,
      ),
    ];
  }
}
