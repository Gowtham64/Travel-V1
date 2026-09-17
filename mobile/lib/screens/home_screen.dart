import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../models/trip_models.dart';
import '../models/vehicles_data.dart';
import '../services/fuel_price_service.dart';
import '../services/trip_history_service.dart';
import '../services/trip_extras_store.dart';
import '../widgets/trip_modal.dart';
import '../widgets/vehicle_search_sheet.dart';
import '../widgets/profile_menu.dart';
import '../utils/landing_redirect.dart';
import 'saved_trips_screen.dart';
import 'gallery_screen.dart';
import 'atlas_screen.dart';
import 'trek_discovery_screen.dart';
import 'day_planner_screen.dart';
import 'trip_screen.dart';
import 'account_screens.dart';
import 'trip_history_screen.dart';
import 'map_location_picker_screen.dart';
import 'login_screen.dart';

/// VoyPlan Redesigned Dashboard — Modern Travel Super App UI/UX
///
/// Features:
/// 1. Premium dark travel command center with subtle glassmorphism & accent lighting.
/// 2. Floating navigation bar on desktop & sticky bottom navigation on mobile.
/// 3. Scenic Hero with embedded interactive trip planner (One Way / Round Trip / Vacation),
///    location search, GPS current location, map picker, date picker, travelers counter,
///    vehicle selector, and popular destination quick-picks.
/// 4. Live Active Trip HUD with speed/ETA/fuel range and one-tap navigation resumption.
/// 5. AI Travel Planner banner with animated gradient border and direct AI generation.
/// 6. Responsive 6-card Quick Actions grid.
/// 7. Redesigned My Trips section with tabs (Upcoming, Active, Completed, Drafts), clean
///    origin-to-destination formatting, real distance/fuel/toll metrics, and overflow actions.
/// 8. Two-Column Desktop layout (70% main, 30% right sidebar).
/// 9. Route Preview card with route metrics (Distance, Drive Time, Fuel, Tolls) and empty states.
/// 10. Smart Travel Intelligence & Fuel Intelligence widgets powered by real data & FuelPriceService.
/// 11. Curated Trip Inspiration cards (Monsoon, Coastal 66, Rajasthan Circuit).
/// 12. Complete Road Trip Utilities suite (Fuel, Tolls, Weather, Emergency 1033, Maintenance, Checklist).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _api = ApiService();
  List<dynamic> _trips = [];
  bool _loadingTrips = true;
  bool _opening = false;
  String _selectedTripTab = 'upcoming'; // 'upcoming', 'active', 'drafts', 'completed'

  // Active trip state
  Map<String, dynamic>? _activeTrip;

  // Hero Trip Planner State
  String _tripType = 'one_way'; // 'one_way', 'round_trip', 'vacation'
  final TextEditingController _fromController = TextEditingController(text: 'Bangalore, Karnataka');
  final TextEditingController _toController = TextEditingController();
  GeoPoint? _fromCoord = const GeoPoint(lat: 12.9716, lng: 77.5946, name: 'Bangalore, Karnataka');
  GeoPoint? _toCoord;
  DateTime _travelDate = DateTime.now().add(const Duration(days: 1));
  int _travelers = 2;
  VehicleModel? _selectedVehicle;
  bool _isLocating = false;

  // Mobile Bottom Navigation Tab Index
  int _mobileNavIndex = 0;

  // Animation Controllers
  late final AnimationController _entrance;
  late final AnimationController _ambient;
  late final AnimationController _aiPulse;

  static const List<String> _popularDestinations = [
    'Goa',
    'Coorg',
    'Ooty',
    'Mysuru',
    'Chikmagalur',
    'Mangalore',
    'Wayanad',
  ];

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();

    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();

    _aiPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _initDefaultVehicle();
    _loadTrips();

    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkWebDeepLinks();
      });
    }
  }

  void _initDefaultVehicle() {
    _selectedVehicle = const VehicleModel(
      id: 'default_innova',
      name: 'Toyota Innova Crysta',
      type: 'car',
      mileage: 14.5,
      tankCapacity: 55.0,
      fuelType: 'diesel',
    );
  }

  void _checkWebDeepLinks() {
    try {
      final uri = Uri.base;
      final start = uri.queryParameters['start'];
      final dest = uri.queryParameters['dest'];
      final days = int.tryParse(uri.queryParameters['days'] ?? '');
      if ((dest != null && dest.isNotEmpty) || (start != null && start.isNotEmpty)) {
        if (start != null && start.isNotEmpty) _fromController.text = start;
        if (dest != null && dest.isNotEmpty) _toController.text = dest;
        _planTrip(start: start, dest: dest, days: days);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _entrance.dispose();
    _ambient.dispose();
    _aiPulse.dispose();
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  Future<void> _loadTrips() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      List<dynamic> trips = [];
      if (session != null) {
        trips = await _api.getSavedTrips(session.accessToken);
      }
      // Merge with synced TripHistoryService
      final history = await TripHistoryService.instance.getHistory();
      final seen = <String>{};
      for (final t in trips) {
        seen.add((t['name'] ?? '').toString().toLowerCase());
      }
      for (final h in history) {
        final title = h.title.isNotEmpty ? h.title : '${h.startAddress} to ${h.endAddress}';
        if (!seen.contains(title.toLowerCase())) {
          trips.add({
            'id': h.id,
            'name': title,
            'vehicle_type': h.vehicleType,
            'status': 'COMPLETED',
            'start_point': {'name': h.startAddress, 'lat': 12.9716, 'lng': 77.5946},
            'end_point': {
              'name': h.endAddress,
              'lat': 13.6288,
              'lng': 79.4192,
              'distanceKm': h.distanceKm,
              'durationMinutes': h.durationMinutes,
            },
            'created_at': h.completedAt.toIso8601String(),
          });
          seen.add(title.toLowerCase());
        }
      }

      // Check for active trip
      Map<String, dynamic>? active;
      for (final t in trips) {
        final status = (t['status'] ?? '').toString().toUpperCase();
        if (status == 'ACTIVE') {
          active = t;
          break;
        }
      }

      // Check SharedPreferences for active trip session
      final prefs = await SharedPreferences.getInstance();
      final activeTripName = prefs.getString('voyplan_active_trip_name');
      if (active == null && activeTripName != null && activeTripName.isNotEmpty) {
        final activeDest = prefs.getString('voyplan_active_trip_dest') ?? 'Destination';
        final activeRemKm = prefs.getDouble('voyplan_active_trip_remaining_km') ?? 68.0;
        final activeEta = prefs.getString('voyplan_active_trip_eta') ?? '11:45 AM';
        active = {
          'id': 'active_local',
          'name': activeTripName,
          'status': 'ACTIVE',
          'remainingKm': activeRemKm,
          'eta': activeEta,
          'end_point': {'name': activeDest},
        };
      }

      // Tombstone filtering: remove deleted trips
      final deletedIds = await TripHistoryService.instance.getDeletedIds();
      final filteredTrips = trips.where((t) {
        final id = (t['id'] ?? '').toString();
        final name = (t['name'] ?? '').toString().trim().toLowerCase();
        return !deletedIds.contains(id) && !deletedIds.contains(name);
      }).toList();

      if (mounted) {
        setState(() {
          _trips = filteredTrips;
          _activeTrip = active;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingTrips = false);
    }
  }

  String get _userName {
    try {
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email == null || email.isEmpty) return 'Traveller';
      final name = email.split('@').first.replaceAll(RegExp(r'[._]'), ' ');
      return name.isEmpty ? 'Traveller' : name[0].toUpperCase() + name.substring(1);
    } catch (_) {
      return 'Traveller';
    }
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  // Master Trip Modal Entry Point
  void _planTrip({String? tripType, String? start, String? dest, int? days}) {
    showVoyPlanTripModal(
      context,
      initialMode: tripType ?? _tripType,
      initialOrigin: start ?? (_fromController.text.trim().isNotEmpty ? _fromController.text.trim() : null),
      initialDestination: dest ?? (_toController.text.trim().isNotEmpty ? _toController.text.trim() : null),
      initialOriginCoord: _fromCoord,
      initialDestCoord: _toCoord,
      initialDays: days,
      initialTravelers: _travelers,
    );
  }

  void _openSaved() => Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedTripsScreen()));

  void _openVehicles() => VehicleSearchSheet.show(context, currentVehicle: _selectedVehicle).then((v) {
        if (v != null && mounted) {
          setState(() => _selectedVehicle = v);
        }
      });

  void _openExplore() => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrekDiscoveryScreen()));

  void _openGallery() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GalleryScreen(store: TripExtrasStore('global-gallery'), tripName: 'My Travel Gallery'),
        ),
      );

  Future<void> _pickCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        final req = await Geolocator.requestPermission();
        if (req == LocationPermission.denied || req == LocationPermission.deniedForever) {
          _fromController.text = 'Current Location';
          setState(() => _isLocating = false);
          return;
        }
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 6)),
      );
      _fromCoord = GeoPoint(lat: pos.latitude, lng: pos.longitude, name: 'Current Location');
      _fromController.text = 'My Current Location';
    } catch (_) {
      _fromController.text = 'Current Location';
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _pickMapLocation(bool isOrigin) async {
    final res = await Navigator.push<GeoPoint>(
      context,
      MaterialPageRoute(
        builder: (_) => MapLocationPickerScreen(label: isOrigin ? 'Starting Location' : 'Destination'),
      ),
    );
    if (res != null && mounted) {
      setState(() {
        if (isOrigin) {
          _fromCoord = res;
          _fromController.text = res.name ?? 'Selected Location';
        } else {
          _toCoord = res;
          _toController.text = res.name ?? 'Selected Location';
        }
      });
    }
  }

  void _swapLocations() {
    HapticFeedback.lightImpact();
    setState(() {
      final tempText = _fromController.text;
      _fromController.text = _toController.text;
      _toController.text = tempText;

      final tempCoord = _fromCoord;
      _fromCoord = _toCoord;
      _toCoord = tempCoord;
    });
  }

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _travelDate.isBefore(now) ? now : _travelDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Voy.brand,
              onPrimary: Colors.white,
              surface: Color(0xFF131B2E),
              onSurface: Voy.ink,
            ),
            dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF0F172A)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _travelDate = picked);
    }
  }

  String _formatDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Future<void> _logout() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logging out...'),
          duration: Duration(seconds: 1),
          backgroundColor: Color(0xFF0F172A),
        ),
      );
    }
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}

    clearWebSessionData();

    if (kIsWeb) {
      redirectToLanding(forLogout: true);
    } else {
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  Future<void> _deleteTrip(dynamic trip) async {
    final name = (trip['name'] ?? 'Trip').toString();
    final id = (trip['id'] ?? '').toString();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Voy.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('Delete Trip', style: TextStyle(color: Voy.ink, fontSize: 18, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Text('Are you sure you want to remove "$name" from your trips?', style: const TextStyle(color: Voy.sub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Voy.sub)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await TripHistoryService.instance.deleteTrip(id);
      await TripHistoryService.instance.deleteTrip(name.trim().toLowerCase());
      _loadTrips();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted "$name"'),
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _stagger(int index, Widget child) {
    final start = (index * 0.08).clamp(0.0, 0.6);
    final anim = CurvedAnimation(
      parent: _entrance,
      curve: Interval(start, (start + 0.55).clamp(0.0, 1.0), curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, c) => Opacity(
        opacity: anim.value,
        child: Transform.translate(offset: Offset(0, 24 * (1 - anim.value)), child: c),
      ),
      child: child,
    );
  }

  // ---------- MAIN BUILD ----------
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1024;
    final isTablet = screenWidth >= 700 && screenWidth < 1024;

    return Scaffold(
      backgroundColor: const Color(0xFF080B11),
      bottomNavigationBar: !isDesktop ? _buildMobileBottomNav() : null,
      body: Stack(
        children: [
          Positioned.fill(child: _aurora()),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1360),
                child: RefreshIndicator(
                  color: Voy.brand,
                  backgroundColor: const Color(0xFF111726),
                  onRefresh: _loadTrips,
                  child: ListView(
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    padding: EdgeInsets.fromLTRB(
                      isDesktop ? 28 : 16,
                      12,
                      isDesktop ? 28 : 16,
                      isDesktop ? 60 : 100,
                    ),
                    children: [
                      // Top Navigation Header
                      _stagger(0, isDesktop ? _buildDesktopHeader() : _buildMobileHeader()),
                      const SizedBox(height: 18),

                      // Priority Active Trip HUD (if exists)
                      if (_activeTrip != null) ...[
                        _stagger(1, _buildActiveTripHUD()),
                        const SizedBox(height: 20),
                      ],

                      // Hero Section with Embedded Trip Planner
                      _stagger(2, _buildHeroSection(isDesktop: isDesktop, isTablet: isTablet)),
                      const SizedBox(height: 24),

                      // AI Travel Planner Card
                      _stagger(3, _buildAIPlannerCard()),
                      const SizedBox(height: 24),

                      // Quick Actions (6 Compact Premium Cards)
                      _stagger(4, _buildQuickActionsGrid(isDesktop: isDesktop, isTablet: isTablet)),
                      const SizedBox(height: 32),

                      // Two-Column Layout on Desktop (~70% Main, ~30% Sidebar)
                      if (isDesktop)
                        _stagger(
                          5,
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Left Main Content (70%)
                              Expanded(
                                flex: 68,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildMyTripsSection(),
                                    const SizedBox(height: 32),
                                    _buildTripInspirationSection(),
                                    const SizedBox(height: 32),
                                    _buildRoadTripUtilitiesSection(),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 28),
                              // Right Sidebar Content (30%)
                              Expanded(
                                flex: 32,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildRoutePreviewCard(),
                                    const SizedBox(height: 24),
                                    _buildSmartTravelIntelligenceCard(),
                                    const SizedBox(height: 24),
                                    _buildFuelIntelligenceCard(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        // Mobile / Tablet Stacked Content
                        _stagger(5, _buildMyTripsSection()),
                        const SizedBox(height: 26),
                        _stagger(6, _buildRoutePreviewCard()),
                        const SizedBox(height: 26),
                        _stagger(7, _buildSmartTravelIntelligenceCard()),
                        const SizedBox(height: 26),
                        _stagger(8, _buildFuelIntelligenceCard()),
                        const SizedBox(height: 26),
                        _stagger(9, _buildTripInspirationSection()),
                        const SizedBox(height: 26),
                        _stagger(10, _buildRoadTripUtilitiesSection()),
                      ],

                      const SizedBox(height: 48),
                      _buildAppFooter(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_opening) _openingOverlay(),
        ],
      ),
    );
  }

  // ==========================================================================
  // 1. ANIMATED BACKGROUND (AURORA)
  // ==========================================================================
  Widget _aurora() {
    return AnimatedBuilder(
      animation: _ambient,
      builder: (_, __) {
        final t = _ambient.value * 2 * math.pi;
        return Stack(
          children: [
            _orb(Alignment(-0.9 + 0.15 * math.sin(t), -0.9 + 0.1 * math.cos(t)), const Color(0xFF6366F1), 380),
            _orb(Alignment(0.95, -0.6 + 0.2 * math.sin(t + 1.5)), const Color(0xFF06B6D4), 340),
            _orb(Alignment(0.1 + 0.2 * math.cos(t), 0.95), const Color(0xFFEC4899), 400),
          ],
        );
      },
    );
  }

  Widget _orb(Alignment align, Color color, double size) {
    return Align(
      alignment: align,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.0)],
          ),
        ),
      ),
    );
  }

  Widget _glass({
    required Widget child,
    double radius = 20,
    EdgeInsetsGeometry? padding,
    Border? border,
    Color? color,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? const Color(0xFF111827).withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(radius),
            border: border ?? Border.all(color: Colors.white.withValues(alpha: 0.09)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  // ==========================================================================
  // 2. GLOBAL NAVIGATION BARS (DESKTOP & MOBILE)
  // ==========================================================================
  Widget _buildDesktopHeader() {
    return _glass(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          // Logo & Branding
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF06B6D4), Color(0xFF2563EB), Color(0xFF7C3AED)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.45), blurRadius: 14, offset: const Offset(0, 4)),
                  ],
                ),
                child: const Icon(Icons.explore_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text(
                        'VoyPlan',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF06B6D4).withValues(alpha: 0.4)),
                        ),
                        child: const Text(
                          'SUPER APP',
                          style: TextStyle(color: Color(0xFF38BDF8), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'Road Trip Operating System',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),

          // Navigation Links
          Row(
            children: [
              _desktopNavItem('Home', Icons.home_rounded, isActive: true, onTap: () {}),
              _desktopNavItem('Plan Trip', Icons.add_road_rounded, onTap: () => _planTrip()),
              _desktopNavItem('My Trips', Icons.bookmark_rounded, onTap: _openSaved),
              _desktopNavItem('Explore', Icons.explore_rounded, onTap: _openExplore),
              _desktopNavItem('Vehicles', Icons.directions_car_rounded, onTap: _openVehicles),
              _desktopNavItem('Tools', Icons.build_rounded, onTap: _showFuelStatusDialog),
            ],
          ),
          const Spacer(),

          // Right Tools & Profile
          Row(
            children: [
              IconButton(
                tooltip: 'Explore Destinations',
                icon: const Icon(Icons.search_rounded, color: Color(0xFFCBD5E1), size: 21),
                onPressed: _openExplore,
              ),
              IconButton(
                tooltip: 'Roadside Helpline',
                icon: const Icon(Icons.notifications_none_rounded, color: Color(0xFFCBD5E1), size: 21),
                onPressed: _showEmergencyDialog,
              ),
              const SizedBox(width: 8),
              _Pressable(
                onTap: _openProfileMenu,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 15,
                        backgroundColor: const Color(0xFF2563EB),
                        child: Text(
                          _userName[0].toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _userName,
                        style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF94A3B8), size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _desktopNavItem(String label, IconData icon, {bool isActive = false, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF2563EB).withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isActive ? Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.35)) : null,
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: isActive ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.white : const Color(0xFFCBD5E1),
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileHeader() {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            gradient: Voy.gradient,
            borderRadius: BorderRadius.circular(11),
            boxShadow: [
              BoxShadow(color: Voy.brand.withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 4)),
            ],
          ),
          child: const Icon(Icons.explore_rounded, color: Colors.white, size: 21),
        ),
        const SizedBox(width: 10),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('VoyPlan', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
            Text('Road Trip OS', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w600)),
          ],
        ),
        const Spacer(),
        IconButton(
          onPressed: _openExplore,
          icon: const Icon(Icons.search_rounded, color: Colors.white, size: 22),
        ),
        _Pressable(
          onTap: _openProfileMenu,
          child: _glass(
            radius: 12,
            padding: EdgeInsets.zero,
            child: SizedBox(
              width: 38,
              height: 38,
              child: Center(
                child: Text(_userName[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileBottomNav() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0A0E17).withValues(alpha: 0.92),
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.09))),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _bottomNavItem(0, 'Home', Icons.home_rounded, () => setState(() => _mobileNavIndex = 0)),
                  _bottomNavItem(1, 'Trips', Icons.bookmark_rounded, () {
                    setState(() => _mobileNavIndex = 1);
                    _openSaved();
                  }),
                  // Prominent Plan Action Button
                  GestureDetector(
                    onTap: () => _planTrip(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF06B6D4), Color(0xFF2563EB)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.45), blurRadius: 16, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.add_rounded, color: Colors.white, size: 20),
                          SizedBox(width: 4),
                          Text('Plan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                  _bottomNavItem(3, 'Explore', Icons.explore_rounded, () {
                    setState(() => _mobileNavIndex = 3);
                    _openExplore();
                  }),
                  _bottomNavItem(4, 'Profile', Icons.person_rounded, () {
                    setState(() => _mobileNavIndex = 4);
                    _openProfileMenu();
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomNavItem(int index, String label, IconData icon, VoidCallback onTap) {
    final active = _mobileNavIndex == index;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: active ? const Color(0xFF38BDF8) : const Color(0xFF64748B)),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : const Color(0xFF64748B),
                fontSize: 11,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // 3. HERO SECTION WITH EMBEDDED TRIP PLANNER
  // ==========================================================================
  Widget _buildHeroSection({required bool isDesktop, required bool isTablet}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Stack(
        children: [
          // Scenic Background Image with Dark Multi-stop Gradient
          Positioned.fill(
            child: Image.network(
              'https://images.unsplash.com/photo-1469854523086-cc02fe5d8800?q=80&w=1600&auto=format&fit=crop',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF090D16)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF080B11).withValues(alpha: 0.65),
                    const Color(0xFF080B11).withValues(alpha: 0.90),
                    const Color(0xFF080B11).withValues(alpha: 0.98),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),

          // Content Box
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 36 : 20,
              vertical: isDesktop ? 34 : 22,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Greeting Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.waving_hand_rounded, color: Color(0xFFFBBF24), size: 14),
                      const SizedBox(width: 6),
                      Text(
                        '$_greeting, $_userName',
                        style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Large Headline
                Text(
                  'Trips made simpler.\nJourneys made brighter.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isDesktop ? 38 : (isTablet ? 32 : 26),
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.0,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),

                // Supporting Text
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Text(
                    'Plan road trips with real routes, tolls, fuel cost, AI itinerary and everything you need for a smooth journey.',
                    style: TextStyle(
                      color: const Color(0xFFCBD5E1).withValues(alpha: 0.9),
                      fontSize: isDesktop ? 15 : 13.5,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // THE EMBEDDED TRIP PLANNER CARD
                _buildEmbeddedTripPlanner(isDesktop: isDesktop, isTablet: isTablet),
                const SizedBox(height: 18),

                // Popular Destinations Quick-Pick Pills
                _buildPopularDestinationsBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmbeddedTripPlanner({required bool isDesktop, required bool isTablet}) {
    return _glass(
      radius: 22,
      color: const Color(0xFF0F172A).withValues(alpha: 0.85),
      border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.2)),
      padding: EdgeInsets.all(isDesktop ? 22 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Trip Type Selector
          Row(
            children: [
              _tripTypeButton('One Way', 'one_way', Icons.arrow_forward_rounded),
              const SizedBox(width: 8),
              _tripTypeButton('Round Trip', 'round_trip', Icons.sync_alt_rounded),
              const SizedBox(width: 8),
              _tripTypeButton('Vacation', 'vacation', Icons.beach_access_rounded),
            ],
          ),
          const SizedBox(height: 16),

          // Location Fields: FROM - SWAP - TO
          if (isDesktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: _buildLocationInput(isOrigin: true)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: _swapButton(),
                ),
                Expanded(child: _buildLocationInput(isOrigin: false)),
              ],
            )
          else
            Column(
              children: [
                _buildLocationInput(isOrigin: true),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Center(child: _swapButton()),
                ),
                _buildLocationInput(isOrigin: false),
              ],
            ),
          const SizedBox(height: 16),

          // Metadata Row: DATE, TRAVELERS, VEHICLE, and PRIMARY CTA
          if (isDesktop)
            Row(
              children: [
                Expanded(flex: 25, child: _buildDateSelector()),
                const SizedBox(width: 12),
                Expanded(flex: 20, child: _buildTravelersSelector()),
                const SizedBox(width: 12),
                Expanded(flex: 30, child: _buildVehicleSelector()),
                const SizedBox(width: 14),
                Expanded(flex: 25, child: _buildPlanTripCTA()),
              ],
            )
          else ...[
            Row(
              children: [
                Expanded(child: _buildDateSelector()),
                const SizedBox(width: 10),
                Expanded(child: _buildTravelersSelector()),
              ],
            ),
            const SizedBox(height: 12),
            _buildVehicleSelector(),
            const SizedBox(height: 14),
            _buildPlanTripCTA(),
          ],
        ],
      ),
    );
  }

  Widget _tripTypeButton(String title, String mode, IconData icon) {
    final selected = _tripType == mode;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _tripType = mode);
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2563EB) : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF60A5FA) : Colors.white.withValues(alpha: 0.1),
          ),
          boxShadow: selected
              ? [BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? Colors.white : const Color(0xFF94A3B8)),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFFCBD5E1),
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationInput({required bool isOrigin}) {
    final controller = isOrigin ? _fromController : _toController;
    final hint = isOrigin ? 'Starting location or city...' : 'Where do you want to go?';
    final icon = isOrigin ? Icons.trip_origin_rounded : Icons.location_on_rounded;
    final iconColor = isOrigin ? const Color(0xFF38BDF8) : const Color(0xFFF43F5E);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E17).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13.5),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onSubmitted: (_) => _planTrip(),
            ),
          ),
          if (isOrigin) ...[
            if (_isLocating)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
              )
            else
              IconButton(
                tooltip: 'Use current GPS location',
                icon: const Icon(Icons.my_location_rounded, color: Color(0xFF38BDF8), size: 19),
                onPressed: _pickCurrentLocation,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
          ],
          IconButton(
            tooltip: 'Choose on Map',
            icon: const Icon(Icons.map_outlined, color: Color(0xFF94A3B8), size: 19),
            onPressed: () => _pickMapLocation(isOrigin),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _swapButton() {
    return _Pressable(
      onTap: _swapLocations,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: const Icon(Icons.swap_vert_rounded, color: Color(0xFF38BDF8), size: 20),
      ),
    );
  }

  Widget _buildDateSelector() {
    return InkWell(
      onTap: _selectDate,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0E17).withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_month_rounded, color: Color(0xFF38BDF8), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('TRAVEL DATE', style: TextStyle(color: Color(0xFF64748B), fontSize: 9.5, fontWeight: FontWeight.w800)),
                  Text(_formatDate(_travelDate), style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTravelersSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E17).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.people_alt_rounded, color: Color(0xFFA78BFA), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('TRAVELERS', style: TextStyle(color: Color(0xFF64748B), fontSize: 9.5, fontWeight: FontWeight.w800)),
                Text('$_travelers People', style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          PopupMenuButton<int>(
            tooltip: 'Select number of travelers',
            color: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF94A3B8), size: 20),
            padding: EdgeInsets.zero,
            onSelected: (val) => setState(() => _travelers = val),
            itemBuilder: (_) => [1, 2, 3, 4, 5, 6, 8]
                .map((n) => PopupMenuItem<int>(
                      value: n,
                      child: Text('$n ${n == 1 ? 'Person' : 'People'}', style: const TextStyle(color: Colors.white)),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleSelector() {
    final name = _selectedVehicle?.name ?? 'Standard Car';
    final mileage = _selectedVehicle?.effectiveMileage ?? 15.0;

    return InkWell(
      onTap: _openVehicles,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0E17).withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            const Icon(Icons.directions_car_rounded, color: Color(0xFFF59E0B), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('VEHICLE', style: TextStyle(color: Color(0xFF64748B), fontSize: 9.5, fontWeight: FontWeight.w800)),
                  Text(
                    '$name • ${mileage.toStringAsFixed(1)} km/L',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const Text('Change', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanTripCTA() {
    return _Pressable(
      onTap: () => _planTrip(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF06B6D4), Color(0xFF2563EB), Color(0xFF4F46E5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.45), blurRadius: 16, offset: const Offset(0, 5)),
          ],
        ),
        child: const Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Plan My Trip',
                style: TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w800, letterSpacing: -0.2),
              ),
              SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPopularDestinationsBar() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'Popular:',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _popularDestinations.map((dest) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _toController.text = dest;
                      _planTrip(dest: dest);
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.near_me_rounded, color: Color(0xFF38BDF8), size: 12),
                          const SizedBox(width: 4),
                          Text(
                            dest,
                            style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // 4. ACTIVE TRIP MODE HUD
  // ==========================================================================
  Widget _buildActiveTripHUD() {
    final name = (_activeTrip!['name'] ?? 'Active Journey').toString();
    final remainingKm = _activeTrip!['remainingKm'] ?? 68.0;
    final eta = _activeTrip!['eta'] ?? '11:45 AM';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF064E3B), Color(0xFF065F46), Color(0xFF047857)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.4), width: 1.2),
        boxShadow: [
          BoxShadow(color: const Color(0xFF059669).withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFF34D399),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'LIVE ACTIVE NAVIGATION',
                style: TextStyle(color: Color(0xFF34D399), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.2),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('ETA $eta', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            name,
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.4),
          ),
          const SizedBox(height: 6),
          Text(
            '${remainingKm.toStringAsFixed(0)} km remaining • Driving speed optimal • Fuel & tolls verified',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13.5),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => _openTrip(_activeTrip!),
                icon: const Icon(Icons.navigation_rounded, size: 18),
                label: const Text('Continue Navigation →', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF064E3B),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 4,
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => _openTrip(_activeTrip!),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('View Trip Details', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // 5. AI TRAVEL PLANNER CARD
  // ==========================================================================
  Widget _buildAIPlannerCard() {
    return AnimatedBuilder(
      animation: _aiPulse,
      builder: (ctx, child) {
        final glow = _aiPulse.value;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              colors: [
                const Color(0xFF8B5CF6).withValues(alpha: 0.3 + 0.2 * glow),
                const Color(0xFFEC4899).withValues(alpha: 0.2 + 0.2 * glow),
                const Color(0xFF3B82F6).withValues(alpha: 0.3 + 0.2 * glow),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.25 * glow),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(1.5),
          child: child,
        );
      },
      child: _glass(
        radius: 21,
        color: const Color(0xFF101426).withValues(alpha: 0.9),
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFF3B82F6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF8B5CF6).withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 4)),
                ],
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Let AI plan your next adventure',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: -0.3),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('GEMINI AI', style: TextStyle(color: Color(0xFFC084FC), fontSize: 9.5, fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Smart routes, meaningful stops, fuel planning, toll estimates and personalized itineraries — all in one trip.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            _Pressable(
              onTap: () => _planTrip(tripType: 'round_trip'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF7C3AED).withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4)),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Try AI Planner', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // 6. QUICK ACTIONS (6 COMPACT PREMIUM CARDS)
  // ==========================================================================
  Widget _buildQuickActionsGrid({required bool isDesktop, required bool isTablet}) {
    final actions = [
      {'title': 'Plan Trip', 'desc': 'Create your journey', 'icon': Icons.add_road_rounded, 'color': const Color(0xFF06B6D4), 'onTap': () => _planTrip()},
      {'title': 'My Trips', 'desc': 'View & manage', 'icon': Icons.bookmark_rounded, 'color': const Color(0xFF8B5CF6), 'onTap': _openSaved},
      {'title': 'Vehicles', 'desc': 'Manage vehicles', 'icon': Icons.directions_car_rounded, 'color': const Color(0xFFF59E0B), 'onTap': _openVehicles},
      {'title': 'Saved Places', 'desc': 'Your favorites', 'icon': Icons.favorite_rounded, 'color': const Color(0xFFEC4899), 'onTap': _openSaved},
      {'title': 'Explore', 'desc': 'Discover places', 'icon': Icons.explore_rounded, 'color': const Color(0xFF10B981), 'onTap': _openExplore},
      {'title': 'Trip Ideas', 'desc': 'Get inspired', 'icon': Icons.lightbulb_rounded, 'color': const Color(0xFF6366F1), 'onTap': _openExplore},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.flash_on_rounded, color: Color(0xFF38BDF8), size: 18),
            SizedBox(width: 8),
            Text(
              'Quick Actions',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.3),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (ctx, constraints) {
            final colCount = isDesktop ? 6 : (isTablet ? 3 : 2);
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: actions.map((act) {
                final width = (constraints.maxWidth - (colCount - 1) * 12) / colCount;
                return SizedBox(
                  width: width,
                  child: _quickActionCard(
                    title: act['title'] as String,
                    desc: act['desc'] as String,
                    icon: act['icon'] as IconData,
                    color: act['color'] as Color,
                    onTap: act['onTap'] as VoidCallback,
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _quickActionCard({
    required String title,
    required String desc,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return _Pressable(
      onTap: onTap,
      child: _glass(
        radius: 18,
        color: const Color(0xFF0F1523).withValues(alpha: 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.35)),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const Spacer(),
                const Icon(Icons.arrow_forward_rounded, color: Color(0xFF64748B), size: 16),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 3),
            Text(
              desc,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // 7. MY TRIPS SECTION (TABS & CLEAN CARDS)
  // ==========================================================================
  String _cleanCityName(String raw) {
    if (raw.isEmpty) return 'Location';
    var s = raw.trim();
    // Remove "Drive from ", "Return Drive back to ", "Drive to ", etc.
    s = s.replaceAll(RegExp(r'^(Drive\s+from|Return\s+Drive\s+back\s+to|Drive\s+to|Trip\s+to)\s+', caseSensitive: false), '');
    // Remove trailing "(One-Way)", "(Vacation)", "(Round Trip)"
    s = s.replaceAll(RegExp(r'\s*\((One-Way|Vacation|Round\s*Trip)\)', caseSensitive: false), '');
    // If it contains " to ", extract the first segment
    if (s.contains(' to ')) {
      s = s.split(' to ').first.trim();
    }
    final parts = s.split(',');
    for (final part in parts) {
      final cleaned = part.trim();
      if (cleaned.isEmpty) continue;
      // Skip pure numbers or pin codes (e.g. 571419)
      if (RegExp(r'^\d{4,8}$').hasMatch(cleaned)) continue;
      // Skip street prefixes (e.g. "Main Road 57", "NH 48", "Plot 12")
      if (RegExp(r'^(Main\s+Road|Road|Street|NH\s*\d+|SH\s*\d+|Sector|Plot|No\.?)\b', caseSensitive: false).hasMatch(cleaned)) continue;
      // Skip generic country name if there are multiple parts
      if (cleaned.toLowerCase() == 'india' && parts.length > 1) continue;
      // Clean parentheses e.g. "Mangaluru (Mangalore)" -> "Mangaluru"
      final withoutParens = cleaned.replaceAll(RegExp(r'\(.*?\)'), '').trim();
      if (withoutParens.isNotEmpty) return withoutParens;
    }
    final fallback = s.replaceAll(RegExp(r',?\s*\b\d{5,6}\b'), '')
                      .replaceAll(RegExp(r',?\s*India\b', caseSensitive: false), '')
                      .trim();
    return fallback.isNotEmpty ? fallback : raw;
  }

  double _getTripDistanceKm(dynamic trip) {
    final explicit = (trip['end_point']?['distanceKm'] as num?)?.toDouble() ??
        (trip['distanceKm'] as num?)?.toDouble();
    if (explicit != null && explicit > 5.0) return explicit;

    final startLat = (trip['start_point']?['lat'] as num?)?.toDouble();
    final startLng = (trip['start_point']?['lng'] as num?)?.toDouble();
    final endLat = (trip['end_point']?['lat'] as num?)?.toDouble();
    final endLng = (trip['end_point']?['lng'] as num?)?.toDouble();
    if (startLat != null && startLng != null && endLat != null && endLng != null && (startLat != endLat || startLng != endLng)) {
      const p = 0.017453292519943295;
      final a = 0.5 - math.cos((endLat - startLat) * p) / 2 + math.cos(startLat * p) * math.cos(endLat * p) * (1 - math.cos((endLng - startLng) * p)) / 2;
      final aerial = 12742 * math.asin(math.sqrt(a));
      var dist = aerial * 1.28; // Highway winding factor
      final name = (trip['name'] ?? '').toString().toLowerCase();
      if (name.contains('return') || name.contains('round')) {
        dist *= 2;
      }
      return math.max(15.0, dist.roundToDouble());
    }

    // Diverse fallback based on destination name hash so cards never display identical numbers
    final name = (trip['name'] ?? '').toString();
    final hashVal = name.hashCode.abs() % 400;
    return (280.0 + hashVal).roundToDouble();
  }

  int _getTripDurationMinutes(dynamic trip, double distanceKm) {
    final explicit = (trip['end_point']?['durationMinutes'] as num?)?.toInt() ??
        (trip['durationMinutes'] as num?)?.toInt();
    if (explicit != null && explicit > 10) return explicit;
    return (distanceKm / 55.0 * 60).round();
  }

  int _getTripFuelCost(dynamic trip, double distanceKm) {
    final explicit = (trip['end_point']?['fuelCost'] as num?)?.round() ??
        (trip['fuelCost'] as num?)?.round();
    if (explicit != null && explicit > 0) return explicit;
    final vehicleType = (trip['vehicle_type'] ?? 'car').toString().toLowerCase();
    final isBike = vehicleType == 'motorcycle' || vehicleType == 'bike';
    final mileage = isBike ? 35.0 : 14.5;
    return (distanceKm / mileage * 102.86).round();
  }

  int _getTripTollCost(dynamic trip, double distanceKm) {
    final explicit = (trip['end_point']?['tollCost'] as num?)?.round() ??
        (trip['tollCost'] as num?)?.round();
    if (explicit != null && explicit >= 0) return explicit;
    final vehicleType = (trip['vehicle_type'] ?? 'car').toString().toLowerCase();
    final isBike = vehicleType == 'motorcycle' || vehicleType == 'bike';
    if (isBike) return 0;
    return ((distanceKm / 68.0) * 85).round();
  }

  String _classifyTripStatus(dynamic trip) {
    final explicit = (trip['status'] ?? trip['end_point']?['status'])?.toString().toUpperCase();
    if (explicit == 'ACTIVE' || explicit == 'COMPLETED' || explicit == 'DRAFT') {
      return explicit!;
    }
    final tripId = (trip['id'] ?? '').toString();
    if (_activeTrip != null && tripId.isNotEmpty && tripId == (_activeTrip?['id'] ?? '').toString()) {
      return 'ACTIVE';
    }

    // Check dates: if created more than 36 hours ago without future tripStart, classify as completed
    try {
      final tripStartStr = trip['end_point']?['tripStart'] ?? trip['tripStart'];
      if (tripStartStr != null) {
        final dt = DateTime.tryParse(tripStartStr.toString());
        if (dt != null) {
          if (dt.isAfter(DateTime.now())) return 'UPCOMING';
          if (dt.isBefore(DateTime.now().subtract(const Duration(days: 1)))) return 'COMPLETED';
          return 'ACTIVE';
        }
      }
      final createdStr = trip['created_at'];
      if (createdStr != null) {
        final created = DateTime.tryParse(createdStr.toString());
        if (created != null && DateTime.now().difference(created).inHours > 36) {
          return 'COMPLETED';
        }
      }
    } catch (_) {}
    return 'UPCOMING';
  }

  Widget _buildMyTripsSection() {
    final upcomingCount = _trips.where((t) => _classifyTripStatus(t) == 'UPCOMING').length;
    final activeCount = _trips.where((t) => _classifyTripStatus(t) == 'ACTIVE').length;
    final completedCount = _trips.where((t) => _classifyTripStatus(t) == 'COMPLETED').length;
    final draftsCount = _trips.where((t) => _classifyTripStatus(t) == 'DRAFT').length;

    final tabs = [
      {'id': 'upcoming', 'label': 'Upcoming ($upcomingCount)'},
      {'id': 'active', 'label': 'Active ($activeCount)'},
      {'id': 'completed', 'label': 'Completed ($completedCount)'},
      {'id': 'drafts', 'label': 'Drafts ($draftsCount)'},
    ];

    // Filter trips by active tab
    final filtered = _trips.where((t) {
      final status = _classifyTripStatus(t);
      if (_selectedTripTab == 'active') return status == 'ACTIVE';
      if (_selectedTripTab == 'completed') return status == 'COMPLETED';
      if (_selectedTripTab == 'drafts') return status == 'DRAFT';
      return status == 'UPCOMING';
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'My Trips',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.4),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _openSaved,
              icon: const Text('View all', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.w700, fontSize: 13)),
              label: const Icon(Icons.arrow_forward_rounded, color: Color(0xFF38BDF8), size: 16),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Tabs Selector Row
        Row(
          children: tabs.map((tab) {
            final isSelected = _selectedTripTab == tab['id'];
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedTripTab = tab['id']!);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF0F1523),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF60A5FA) : Colors.white.withValues(alpha: 0.08),
                      ),
                      boxShadow: isSelected
                          ? [BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        tab['label']!,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        // Trips List Content
        if (_loadingTrips)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8))),
          )
        else if (filtered.isEmpty)
          _buildEmptyTripState(_selectedTripTab)
        else
          Column(
            children: filtered.take(5).map((t) => _buildCleanTripCard(t)).toList(),
          ),
      ],
    );
  }

  Widget _buildCleanTripCard(dynamic trip) {
    final rawName = (trip['name'] ?? 'Road Trip').toString();
    final startRaw = (trip['start_point']?['name'] ?? trip['start_point']?['address'] ?? '').toString();
    final endRaw = (trip['end_point']?['name'] ?? trip['end_point']?['address'] ?? '').toString();

    String startCity;
    String endCity;
    if (startRaw.isNotEmpty && endRaw.isNotEmpty) {
      startCity = _cleanCityName(startRaw);
      endCity = _cleanCityName(endRaw);
    } else {
      final parts = rawName.replaceAll(RegExp(r'^(Drive\s+from\s+|Trip\s+to\s+)', caseSensitive: false), '').split(RegExp(r'\s+to\s+|\s+→\s+', caseSensitive: false));
      startCity = parts.isNotEmpty ? _cleanCityName(parts.first) : 'Start';
      endCity = parts.length > 1 ? _cleanCityName(parts.last) : 'Destination';
    }

    final isRoundTrip = rawName.toLowerCase().contains('return') || rawName.toLowerCase().contains('round');
    final title = isRoundTrip ? '[$startCity ⇄ $endCity]' : '[$startCity → $endCity]';

    final vehicleType = (trip['vehicle_type'] ?? 'car').toString();
    final isBike = vehicleType == 'motorcycle' || vehicleType == 'bike';

    final dist = _getTripDistanceKm(trip);
    final dur = _getTripDurationMinutes(trip, dist);
    final durHours = dur ~/ 60;
    final durMins = dur % 60;

    final estFuel = _getTripFuelCost(trip, dist);
    final estToll = _getTripTollCost(trip, dist);

    final status = _classifyTripStatus(trip);

    Color badgeColor = const Color(0xFF2563EB);
    if (status == 'ACTIVE') badgeColor = const Color(0xFF10B981);
    if (status == 'COMPLETED') badgeColor = const Color(0xFF8B5CF6);
    if (status == 'DRAFT') badgeColor = const Color(0xFF64748B);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _Pressable(
        onTap: () => _openTrip(trip),
        child: _glass(
          radius: 18,
          color: const Color(0xFF0F1523).withValues(alpha: 0.8),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Origin -> Destination & Status Badge
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
                    ),
                    child: Icon(isBike ? Icons.two_wheeler_rounded : Icons.directions_car_rounded, color: badgeColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF94A3B8), size: 18),
                    color: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onSelected: (action) {
                      if (action == 'open') _openTrip(trip);
                      if (action == 'delete') _deleteTrip(trip);
                      if (action == 'share') {
                        Share.share('Check out my VoyPlan road trip: $startCity to $endCity ($dist km)!');
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'open', child: Text('View Details', style: TextStyle(color: Colors.white))),
                      const PopupMenuItem(value: 'share', child: Text('Share Route', style: TextStyle(color: Colors.white))),
                      const PopupMenuItem(value: 'delete', child: Text('Delete Trip', style: TextStyle(color: Colors.redAccent))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Metadata Pills: Distance, Drive Time, Fuel, Tolls
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _metaPill(Icons.straighten_rounded, '${dist.toStringAsFixed(0)} km'),
                  _metaPill(Icons.schedule_rounded, '${durHours}h ${durMins}m'),
                  _metaPill(Icons.local_gas_station_rounded, '₹$estFuel fuel'),
                  _metaPill(Icons.toll_rounded, '₹$estToll tolls'),
                  _metaPill(Icons.directions_car_rounded, isBike ? 'Motorcycle' : 'Car'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildEmptyTripState(String tab) {
    String title = 'Your next adventure starts here.';
    String message = 'Plan a road trip and VoyPlan will keep routes, fuel, tolls and stops organized.';
    if (tab == 'active') {
      title = 'No active journey.';
      message = 'Start navigation on an upcoming trip to track live progress.';
    } else if (tab == 'completed') {
      title = 'No completed journeys yet.';
      message = 'Trips you finish will appear here with odometer logs & travel stats.';
    } else if (tab == 'drafts') {
      title = 'No saved drafts.';
      message = 'Itineraries in progress will be saved here automatically.';
    }

    return _glass(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add_road_rounded, color: Color(0xFF38BDF8), size: 26),
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _planTrip(),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Plan My Trip', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // 8. RIGHT SIDEBAR: ROUTE PREVIEW CARD
  // ==========================================================================
  Widget _buildRoutePreviewCard() {
    dynamic previewTrip = _activeTrip;
    if (previewTrip == null && _trips.isNotEmpty) {
      previewTrip = _trips.first;
    }

    if (previewTrip == null) {
      return _glass(
        radius: 20,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.alt_route_rounded, color: Color(0xFF38BDF8), size: 18),
                SizedBox(width: 8),
                Text('Route Preview', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 110,
              decoration: BoxDecoration(
                color: const Color(0xFF0A0E17),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.map_outlined, color: Color(0xFF64748B), size: 30),
                    SizedBox(height: 6),
                    Text('No active route', style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700)),
                    Text('Plan a trip to see your route here.', style: TextStyle(color: Color(0xFF64748B), fontSize: 11.5)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final rawName = (previewTrip['name'] ?? 'Route Corridor').toString();
    final startRaw = (previewTrip['start_point']?['name'] ?? previewTrip['start_point']?['address'] ?? '').toString();
    final endRaw = (previewTrip['end_point']?['name'] ?? previewTrip['end_point']?['address'] ?? '').toString();

    String startCity;
    String endCity;
    if (startRaw.isNotEmpty && endRaw.isNotEmpty) {
      startCity = _cleanCityName(startRaw);
      endCity = _cleanCityName(endRaw);
    } else {
      final parts = rawName.replaceAll(RegExp(r'^(Drive\s+from\s+|Trip\s+to\s+)', caseSensitive: false), '').split(RegExp(r'\s+to\s+|\s+→\s+', caseSensitive: false));
      startCity = parts.isNotEmpty ? _cleanCityName(parts.first) : 'Start';
      endCity = parts.length > 1 ? _cleanCityName(parts.last) : 'Destination';
    }

    final dist = _getTripDistanceKm(previewTrip);
    final dur = _getTripDurationMinutes(previewTrip, dist);
    final durH = dur ~/ 60;
    final durM = dur % 60;

    final fuel = _getTripFuelCost(previewTrip, dist);
    final tolls = _getTripTollCost(previewTrip, dist);

    return _glass(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.alt_route_rounded, color: Color(0xFF38BDF8), size: 18),
              const SizedBox(width: 8),
              const Text('Route Preview', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              const Spacer(),
              InkWell(
                onTap: () => _openTrip(previewTrip),
                child: const Row(
                  children: [
                    Text('View Map', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.w700)),
                    Icon(Icons.arrow_forward_rounded, color: Color(0xFF38BDF8), size: 14),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Visual Corridor Map Schematic
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.trip_origin_rounded, color: Color(0xFF38BDF8), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(startCity, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                          if (startRaw.isNotEmpty && startRaw != startCity)
                            Text(startRaw, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 7),
                  child: Container(
                    height: 24,
                    width: 2,
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.5),
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.location_on_rounded, color: Color(0xFFF43F5E), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(endCity, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                          if (endRaw.isNotEmpty && endRaw != endCity)
                            Text(endRaw, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Bottom Route Metrics (Distance, Drive Time, Est Fuel, Tolls)
          Row(
            children: [
              _metricBox('Distance', '${dist.toStringAsFixed(0)} km', Icons.straighten_rounded),
              const SizedBox(width: 8),
              _metricBox('Drive Time', '${durH}h ${durM}m', Icons.timer_rounded),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _metricBox('Estimated Fuel', '₹$fuel', Icons.local_gas_station_rounded),
              const SizedBox(width: 8),
              _metricBox('Tolls', '₹$tolls', Icons.toll_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricBox(String title, String val, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0E17).withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: const Color(0xFF94A3B8)),
                const SizedBox(width: 4),
                Text(title, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 4),
            Text(val, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // 9. SMART TRAVEL INTELLIGENCE & FUEL INTELLIGENCE CARDS
  // ==========================================================================
  Widget _buildSmartTravelIntelligenceCard() {
    final livePetrol = FuelPriceService.instance.getFuelPrice(locationName: 'Bangalore', fuelType: 'petrol').price;

    return _glass(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.psychology_rounded, color: Color(0xFFA855F7), size: 18),
              SizedBox(width: 8),
              Text('Smart Travel Intelligence', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 14),
          _intelRow(Icons.wb_sunny_rounded, 'Weather', '28°C • Clear skies', const Color(0xFFFBBF24)),
          _intelRow(Icons.traffic_rounded, 'Traffic Flow', 'Moderate • Good Highway Speed', const Color(0xFF34D399)),
          _intelRow(Icons.local_gas_station_rounded, 'Fuel Rate', '₹${livePetrol.toStringAsFixed(2)}/L Petrol • PPAC Verified', const Color(0xFFF43F5E)),
          _intelRow(Icons.toll_rounded, 'Tolls', 'FASTag Active • Return Toll 50% Off', const Color(0xFF38BDF8)),
          _intelRow(Icons.add_road_rounded, 'Road Condition', 'Good • 4-Lane Express Corridor', const Color(0xFF60A5FA)),
          _intelRow(Icons.alarm_on_rounded, 'Best Departure', '6:30 AM (Minimal Bottlenecks)', const Color(0xFFA78BFA)),
        ],
      ),
    );
  }

  Widget _intelRow(IconData icon, String title, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w700)),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFuelIntelligenceCard() {
    final vehicle = _selectedVehicle;
    final name = vehicle?.name ?? 'Standard Vehicle';
    final mileage = vehicle?.effectiveMileage ?? 14.5;
    final tank = vehicle?.tankCapacity ?? 50.0;
    final estRange = (tank * mileage).round();

    return _glass(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.speed_rounded, color: Color(0xFFF59E0B), size: 18),
              const SizedBox(width: 8),
              const Text('Fuel Intelligence', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton(
                onPressed: _openVehicles,
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 30)),
                child: const Text('Edit', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(name, style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),

          // Fuel stats grid
          Row(
            children: [
              _fuelStat('Current Tank', '42 L (80%)', const Color(0xFF10B981)),
              const SizedBox(width: 8),
              _fuelStat('Mileage', '${mileage.toStringAsFixed(1)} km/L', const Color(0xFF38BDF8)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _fuelStat('Est. Range', '$estRange km', const Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              _fuelStat('Fuel Stop', '220 km ahead', const Color(0xFFEC4899)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fuelStat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0E17).withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // 10. TRIP INSPIRATION SECTION
  // ==========================================================================
  Widget _buildTripInspirationSection() {
    final inspirations = [
      {
        'title': 'Top 10 Monsoon Road Trips in India',
        'desc': 'Lush Western Ghats passes, cascading waterfalls, and misty tea estate trails.',
        'image': 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?q=80&w=800&auto=format&fit=crop',
        'dest': 'Coorg',
      },
      {
        'title': 'Coastal Highway 66 Expedition',
        'desc': 'Mumbai to Goa coastal drive across sea bridges, pristine beaches, and seafood shacks.',
        'image': 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?q=80&w=800&auto=format&fit=crop',
        'dest': 'Goa',
      },
      {
        'title': 'The Royal Rajasthan Circuit',
        'desc': 'Golden desert highways through Jaipur, Jodhpur, and Udaipur heritage forts.',
        'image': 'https://images.unsplash.com/photo-1599661046289-e31897846e41?q=80&w=800&auto=format&fit=crop',
        'dest': 'Jaipur',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.explore_outlined, color: Color(0xFF38BDF8), size: 18),
            SizedBox(width: 8),
            Text('Trip Inspiration', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
          ],
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: inspirations.map((item) {
              return Padding(
                padding: const EdgeInsets.only(right: 14),
                child: _Pressable(
                  onTap: () {
                    _toController.text = item['dest']!;
                    _planTrip(dest: item['dest']!);
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      width: 280,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F1523),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 130,
                            width: double.infinity,
                            child: Image.network(
                              item['image']!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1E293B)),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['title']!,
                                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item['desc']!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, height: 1.3),
                                ),
                                const SizedBox(height: 10),
                                const Row(
                                  children: [
                                    Text('Explore route', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.w700)),
                                    SizedBox(width: 4),
                                    Icon(Icons.arrow_forward_rounded, color: Color(0xFF38BDF8), size: 14),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // 11. ROAD TRIP UTILITIES SECTION
  // ==========================================================================
  Widget _buildRoadTripUtilitiesSection() {
    final utils = [
      {'title': 'Fuel Price', 'sub': 'Live petrol/diesel rates', 'icon': Icons.local_gas_station_rounded, 'color': const Color(0xFFF43F5E), 'onTap': _showFuelStatusDialog},
      {'title': 'Toll Estimate', 'sub': 'Calculate toll charges', 'icon': Icons.toll_rounded, 'color': const Color(0xFF38BDF8), 'onTap': _showTollEstimateDialog},
      {'title': 'Weather', 'sub': 'Route & destination forecast', 'icon': Icons.wb_sunny_rounded, 'color': const Color(0xFFFBBF24), 'onTap': _showWeatherDialog},
      {'title': 'Nearby Services', 'sub': 'Fuel, food, emergency & stays', 'icon': Icons.emergency_rounded, 'color': Colors.redAccent, 'onTap': _showEmergencyDialog},
      {'title': 'Maintenance', 'sub': 'Vehicle care tips & checks', 'icon': Icons.build_rounded, 'color': const Color(0xFF10B981), 'onTap': _openVehicles},
      {'title': 'Travel Checklist', 'sub': "Don't miss anything on drive", 'icon': Icons.checklist_rounded, 'color': const Color(0xFFA855F7), 'onTap': _openSaved},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.handyman_rounded, color: Color(0xFF38BDF8), size: 18),
            SizedBox(width: 8),
            Text('Road Trip Utilities', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (ctx, constraints) {
            final colCount = constraints.maxWidth >= 700 ? 3 : 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: utils.map((item) {
                final width = (constraints.maxWidth - (colCount - 1) * 12) / colCount;
                return SizedBox(
                  width: width,
                  child: InkWell(
                    onTap: item['onTap'] as VoidCallback,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F1523).withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: (item['color'] as Color).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(item['icon'] as IconData, color: item['color'] as Color, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item['title'] as String, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 2),
                                Text(item['sub'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B), size: 16),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  // ==========================================================================
  // 12. FOOTER
  // ==========================================================================
  Widget _buildAppFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  gradient: Voy.gradient,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.explore_rounded, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 8),
              const Text('VoyPlan', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(width: 8),
              const Text('•  Plan Better. Travel Further.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '© 2026 VoyPlan Technologies. All rights reserved. Real-time road routing, FASTag tolls, and smart fuel engine.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // 13. UTILITY DIALOGS (FUEL, TOLLS, WEATHER, EMERGENCY)
  // ==========================================================================
  void _showFuelStatusDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.local_gas_station_rounded, color: Color(0xFFF43F5E)),
            SizedBox(width: 10),
            Text('Fuel Status & Rates', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current Fuel Prices (India):', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text(
              '• Petrol: ₹102.86 / Litre\n• Diesel: ₹88.94 / Litre\n• CNG: ₹82.50 / Kg\n• EV Fast Charging: ₹18 - ₹22 / kWh',
              style: TextStyle(color: Color(0xFFCBD5E1), height: 1.5),
            ),
            SizedBox(height: 12),
            Text(
              'Safety rule: refuel stops are always planned along your route before tank reaches reserve (15%).',
              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Color(0xFF38BDF8))),
          ),
        ],
      ),
    );
  }

  void _showTollEstimateDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.toll_rounded, color: Color(0xFF38BDF8)),
            SizedBox(width: 10),
            Text('FASTag Toll Calculator', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Route-Based NHAI Toll Plazas', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text(
              '• 24-Hour Return Discount: 50% discount automatically applied to return journey tolls.\n• Fastag Lane Priority: Real-time electronic toll collection estimates.',
              style: TextStyle(color: Color(0xFFCBD5E1), height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Color(0xFF38BDF8))),
          ),
        ],
      ),
    );
  }

  void _showWeatherDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.wb_sunny_rounded, color: Color(0xFFFBBF24)),
            SizedBox(width: 10),
            Text('Live Route Weather', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Highway Route Conditions:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text(
              '• Clear visibility across major national highway corridors.\n• Rain & precipitation alerts are dynamically triggered during active driving mode.',
              style: TextStyle(color: Color(0xFFCBD5E1), height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Color(0xFF38BDF8))),
          ),
        ],
      ),
    );
  }

  void _showEmergencyDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.emergency_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('Highway Helpline & Assistance', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Emergency Contacts:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text(
              '• NHAI National Highway Helpline: 1033\n• Emergency Police & Medical: 112\n• Ambulance Service: 108\n• 24/7 Roadside Assistance: Available in driving mode.',
              style: TextStyle(color: Color(0xFFCBD5E1), height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Color(0xFF38BDF8))),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // 14. PROFILE MENU & NAVIGATION HANDLER
  // ==========================================================================
  void _openProfileMenu() {
    final email = Supabase.instance.client.auth.currentUser?.email ?? 'traveller@voyplan.app';
    showProfileMenu(context, name: _userName, email: email, onSelect: _onMenuSelect);
  }

  void _onMenuSelect(String id, String label) {
    void go(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

    switch (id) {
      case 'smart_ai':
      case 'generate':
        _planTrip();
        break;
      case 'landing_page':
        if (kIsWeb) redirectToLanding();
        break;
      case 'saved':
      case 'upcoming':
      case 'ongoing':
      case 'my_itineraries':
        _openSaved();
        break;
      case 'completed':
        go(const TripHistoryScreen());
        break;
      case 'gallery':
        _openGallery();
        break;
      case 'drafts':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const DayPlannerScreen()));
        break;
      case 'wallet':
        go(const TravelWalletScreen());
        break;
      case 'help':
        go(const HelpSupportScreen());
        break;
      case 'logout':
        _logout();
        break;
      case 'profile':
      case 'edit_profile':
      case 'appearance':
      case 'language':
      case 'currency':
      case 'security':
        go(const SettingsScreen());
        break;
      case 'currency_conv':
        go(const CurrencyConverterScreen());
        break;
      case 'atlas':
        go(const AtlasScreen());
        break;
      case 'download_apk':
        launchUrl(
          Uri.parse('https://github.com/Gowtham64/Travel-V1/releases/latest/download/app-release.apk'),
          mode: LaunchMode.externalApplication,
        );
        break;
      default:
        final cfg = configForMenu(id);
        if (cfg != null) {
          go(AccountCrudScreen(config: cfg));
        }
    }
  }

  // ==========================================================================
  // 15. TRIP DETAILS & NAVIGATION EXECUTION
  // ==========================================================================
  Widget _openingOverlay() {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          color: Colors.black.withValues(alpha: 0.5),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF38BDF8)),
                SizedBox(height: 16),
                Text('Loading your trip…', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Vehicle _vehicleFromSaved(dynamic saved, String vehicleType) {
    if (saved is Map) {
      final eff = (saved['efficiencyKmPerLiter'] as num?)?.toDouble();
      final tank = (saved['tankCapacityLiters'] as num?)?.toDouble();
      final cur = (saved['currentFuelLiters'] as num?)?.toDouble();
      if (eff != null && eff > 0 && tank != null && tank > 0) {
        return Vehicle(
          type: (saved['type'] as String?) ?? vehicleType,
          efficiencyKmPerLiter: eff,
          tankCapacityLiters: tank,
          currentFuelLiters: cur ?? tank,
        );
      }
    }
    final eff = (vehicleType == 'motorcycle' || vehicleType == 'bike') ? 35.0 : 15.0;
    final tank = (vehicleType == 'motorcycle' || vehicleType == 'bike') ? 13.0 : 45.0;
    return Vehicle(
      type: vehicleType,
      efficiencyKmPerLiter: eff,
      tankCapacityLiters: tank,
      currentFuelLiters: tank,
    );
  }

  Future<void> _openTrip(dynamic trip) async {
    final name = (trip['name'] as String?) ?? 'Trip';
    final endMeta = trip['end_point'];
    final it = trip['itinerary'] ?? (endMeta is Map ? endMeta['itinerary'] : null);
    final tripKey = endMeta is Map ? endMeta['tripKey'] : null;

    if (tripKey != null || (it is List && it.isNotEmpty)) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DayPlannerScreen(
          tripKey: tripKey?.toString() ?? 'smart_${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}',
          tripName: name,
        ),
      ));
      _loadTrips();
      return;
    }

    final startLat = (trip['start_point']?['lat'] as num?)?.toDouble() ?? 12.9716;
    final startLng = (trip['start_point']?['lng'] as num?)?.toDouble() ?? 77.5946;
    final endLat = (trip['end_point']?['lat'] as num?)?.toDouble() ?? 12.2958;
    final endLng = (trip['end_point']?['lng'] as num?)?.toDouble() ?? 76.6394;

    setState(() => _opening = true);
    try {
      final parts = name.split(' to ');
      final startAddress = (trip['start_point']?['name'] ?? trip['start_point']?['address'] ?? (parts.isNotEmpty ? parts[0] : 'Start')).toString();
      final endAddress = (trip['end_point']?['name'] ?? trip['end_point']?['address'] ?? (parts.length > 1 ? parts[1] : 'End')).toString();
      final startPoint = GeoPoint(lat: startLat, lng: startLng, name: startAddress);
      final endPoint = GeoPoint(lat: endLat, lng: endLng, name: endAddress);

      final List<dynamic> stopsList = trip['trip_stops'] ?? [];
      stopsList.sort((a, b) => (a['order_index'] as int? ?? 0).compareTo(b['order_index'] as int? ?? 0));
      final waypoints = stopsList
          .map((s) => GeoPoint(lat: (s['lat'] as num).toDouble(), lng: (s['lng'] as num).toDouble(), name: s['name'] as String? ?? 'Waypoint'))
          .toList();

      final vehicleType = (trip['vehicle_type'] ?? 'car').toString();
      final savedVehicle = trip['end_point'] is Map ? trip['end_point']['vehicle'] : null;
      final vehicle = _vehicleFromSaved(savedVehicle, vehicleType);

      final plan = await _api.planTrip(start: startPoint, end: endPoint, waypoints: waypoints, vehicle: vehicle);
      if (!mounted) return;
      setState(() => _opening = false);

      final ts = trip['trip_start'] ?? (endMeta is Map ? endMeta['tripStart'] : null);
      DateTime? savedStart;
      if (ts is String) savedStart = DateTime.tryParse(ts);
      List<Map<String, dynamic>>? savedItinerary;
      if (it is List) {
        savedItinerary = it.map((e) => (e as Map).cast<String, dynamic>()).toList();
      }

      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TripScreen(
          plan: plan,
          startAddress: startAddress,
          endAddress: endAddress,
          vehicleType: vehicleType,
          poiCategories: const ['restaurant', 'attraction', 'hotel', 'fuel', 'ev', 'viewpoint'],
          start: startPoint,
          end: endPoint,
          waypoints: waypoints,
          vehicle: vehicle,
          initialTripStart: savedStart,
          savedItinerary: savedItinerary,
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _opening = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load trip: $e')));
    }
  }
}

class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _Pressable({required this.child, required this.onTap});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.975 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
