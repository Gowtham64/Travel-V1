import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/saved_place_model.dart';
import '../services/saved_places_service.dart';
import '../widgets/trip_modal.dart';

class SavedPlacesScreen extends StatefulWidget {
  const SavedPlacesScreen({super.key});

  @override
  State<SavedPlacesScreen> createState() => _SavedPlacesScreenState();
}

class _SavedPlacesScreenState extends State<SavedPlacesScreen> {
  final _service = SavedPlacesService();
  final _searchCtrl = TextEditingController();
  String _selectedCategory = 'ALL';
  Position? _userPosition;

  final List<String> _categories = [
    'ALL',
    'Waterfall',
    'Lake',
    'Temple & Heritage',
    'Viewpoint',
    'Restaurant',
    'Cafe',
    'Hotel',
    'Fuel',
  ];

  @override
  void initState() {
    super.initState();
    _service.init();
    _service.addListener(_onServiceUpdate);
    _getUserLocation();
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceUpdate);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _getUserLocation() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 4),
          ),
        );
        if (mounted) setState(() => _userPosition = pos);
      }
    } catch (_) {}
  }

  List<SavedPlace> get _filteredPlaces {
    final query = _searchCtrl.text.trim().toLowerCase();
    return _service.places.where((p) {
      final matchesCategory = _selectedCategory == 'ALL' ||
          p.category.toLowerCase().contains(_selectedCategory.toLowerCase());
      final matchesQuery = query.isEmpty ||
          p.name.toLowerCase().contains(query) ||
          p.location.toLowerCase().contains(query) ||
          (p.description ?? '').toLowerCase().contains(query);
      return matchesCategory && matchesQuery;
    }).toList();
  }

  void _addNewPlaceDialog() {
    final nameCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String category = 'Viewpoint';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
          title: const Text('Save a New Place', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Place Name *', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'e.g. Hebbe Falls',
                    hintStyle: const TextStyle(color: Color(0xFF64748B)),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Category', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButton<String>(
                    value: category,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF1E293B),
                    underline: const SizedBox.shrink(),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    items: ['Waterfall', 'Lake', 'Temple & Heritage', 'Viewpoint', 'Restaurant', 'Cafe', 'Hotel', 'Fuel']
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDlgState(() => category = val);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Location / City', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                const SizedBox(height: 6),
                TextField(
                  controller: locationCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'e.g. Kemmangundi, Karnataka',
                    hintStyle: const TextStyle(color: Color(0xFF64748B)),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Notes / Description', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                const SizedBox(height: 6),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Scenic coffee stop with hill trek',
                    hintStyle: const TextStyle(color: Color(0xFF64748B)),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEC4899),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final newPlace = SavedPlace(
                  id: 'user_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  category: category,
                  location: locationCtrl.text.trim().isNotEmpty ? locationCtrl.text.trim() : 'India',
                  lat: 13.0,
                  lng: 76.0,
                  rating: 4.8,
                  description: descCtrl.text.trim().isNotEmpty ? descCtrl.text.trim() : null,
                  savedAt: DateTime.now(),
                );
                _service.savePlace(newPlace);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Saved "${newPlace.name}" to your Saved Places!'),
                    backgroundColor: const Color(0xFF10B981),
                  ),
                );
              },
              child: const Text('Save Place', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _addPlaceToTrip(SavedPlace place) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.add_road_rounded, color: Color(0xFF38BDF8), size: 24),
                  const SizedBox(width: 10),
                  Text('Plan Trip with "${place.name}"', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Add this spot as a destination or intermediate stop on your journey:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFF38BDF8).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.flag_rounded, color: Color(0xFF38BDF8)),
                ),
                title: const Text('Set as Destination in One Way Trip', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: Text('Drive to ${place.name} with real fuel, tolls & route stops', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  showVoyPlanTripModal(
                    context,
                    initialMode: 'one_way',
                    initialDestination: place.name,
                  );
                },
              ),
              const Divider(color: Colors.white12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFF8B5CF6).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.cached_rounded, color: Color(0xFF8B5CF6)),
                ),
                title: const Text('Build Round Trip Itinerary', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: Text('Create a vacation itinerary including ${place.name}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  showVoyPlanTripModal(
                    context,
                    initialMode: 'vacation',
                    initialDestination: place.name,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToPlace(SavedPlace place) async {
    final query = Uri.encodeComponent('${place.name} ${place.location}');
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final places = _filteredPlaces;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saved Places', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            Text('Individual spots, viewpoints & cafes (separate from trips)', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_location_alt_rounded, color: Color(0xFFEC4899)),
            tooltip: 'Add Place',
            onPressed: _addNewPlaceDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Notice banner clarifying distinction between Trips and Places
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFF1E293B).withValues(alpha: 0.6),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Color(0xFFEC4899), size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Saved Places are single points of interest. To manage full journeys, open My Trips.',
                    style: TextStyle(color: Color(0xFFE2E8F0), fontSize: 11.5),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('My Trips', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
          ),

          // Search and Filter Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search saved places, cities, viewpoints...',
                hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF0F172A),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFEC4899))),
              ),
            ),
          ),

          // Category Chips Row
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, idx) {
                final cat = _categories[idx];
                final isSelected = _selectedCategory == cat;
                return ChoiceChip(
                  label: Text(cat == 'ALL' ? 'All Places' : cat),
                  selected: isSelected,
                  onSelected: (val) {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedCategory = cat);
                  },
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  selectedColor: const Color(0xFFEC4899),
                  backgroundColor: const Color(0xFF0F172A),
                  side: BorderSide(color: isSelected ? const Color(0xFFEC4899) : Colors.white.withValues(alpha: 0.1)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          // Places List
          Expanded(
            child: places.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bookmark_border_rounded, size: 54, color: Color(0xFF64748B)),
                        const SizedBox(height: 12),
                        Text(
                          _searchCtrl.text.isNotEmpty || _selectedCategory != 'ALL'
                              ? 'No matching saved places'
                              : 'No saved places yet',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        const Text('Tap "+ Add Place" above to bookmark your favorite spots.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEC4899),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _addNewPlaceDialog,
                          icon: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                          label: const Text('Add a Place', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: places.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (ctx, idx) {
                      final place = places[idx];
                      double? distKm;
                      if (_userPosition != null && place.lat != 0.0) {
                        distKm = place.distanceFrom(_userPosition!.latitude, _userPosition!.longitude);
                      }

                      return Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Card Image + Category Badge
                            if (place.image != null && place.image!.isNotEmpty)
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                                child: Stack(
                                  children: [
                                    Image.network(
                                      place.image!,
                                      height: 130,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        height: 80,
                                        color: const Color(0xFF1E293B),
                                        child: const Center(child: Icon(Icons.place_rounded, color: Colors.white24, size: 36)),
                                      ),
                                    ),
                                    Positioned(
                                      top: 10,
                                      left: 10,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.65),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: Colors.white24),
                                        ),
                                        child: Text(
                                          place.category.toUpperCase(),
                                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                                        ),
                                      ),
                                    ),
                                    if (place.rating != null)
                                      Positioned(
                                        top: 10,
                                        right: 10,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF59E0B),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.star_rounded, color: Colors.white, size: 14),
                                              const SizedBox(width: 4),
                                              Text(
                                                place.rating!.toStringAsFixed(1),
                                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                            // Content Padding
                            Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          place.name,
                                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                                        tooltip: 'Remove from Saved',
                                        onPressed: () {
                                          _service.removePlace(place.id);
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Removed "${place.name}" from saved places'),
                                              action: SnackBarAction(
                                                label: 'Undo',
                                                textColor: const Color(0xFF38BDF8),
                                                onPressed: () => _service.savePlace(place),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      const Icon(Icons.location_on_outlined, color: Color(0xFF94A3B8), size: 14),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          place.location,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                        ),
                                      ),
                                      if (distKm != null && distKm > 0) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(6)),
                                          child: Text(
                                            '${distKm.toStringAsFixed(0)} km away',
                                            style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (place.description != null && place.description!.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      place.description!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, height: 1.3),
                                    ),
                                  ],
                                  const SizedBox(height: 12),

                                  // Action Buttons
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(color: Color(0xFF38BDF8)),
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          onPressed: () => _addPlaceToTrip(place),
                                          icon: const Icon(Icons.add_road_rounded, color: Color(0xFF38BDF8), size: 16),
                                          label: const Text('Add to Trip', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.w700)),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF2563EB),
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          onPressed: () => _navigateToPlace(place),
                                          icon: const Icon(Icons.navigation_rounded, color: Colors.white, size: 16),
                                          label: const Text('Navigate', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
