import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../models/trip_models.dart';
import '../widgets/trip_modal.dart';
import 'saved_trips_screen.dart';
import 'gallery_screen.dart';
import '../services/trip_extras_store.dart';
import 'atlas_screen.dart';
import 'trek_discovery_screen.dart';
import 'day_planner_screen.dart';
import '../utils/landing_redirect.dart';
import 'trip_screen.dart';
import '../widgets/profile_menu.dart';
import 'account_screens.dart';
import 'trip_history_screen.dart';
import '../services/trip_history_service.dart';
import '../widgets/vehicle_search_sheet.dart';
import 'login_screen.dart';

/// Voyplan home — restructured with Part 7 dashboard requirements:
/// Top: Active Trip banner or Greeting with [✨ Plan a Trip]
/// Second Section: My Trips with 4 tabs (Upcoming, Active, Drafts, Completed)
/// Third Section: Quick Actions (Only: Plan Trip, My Trips, Vehicles, Explore)
/// Fourth Section: Road Trip Utilities (Fuel status, Toll estimate, Weather, Saved places, Nearby services)
/// Removed: Currency converter, World clocks, duplicate CTAs
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

  late final AnimationController _entrance;
  late final AnimationController _ambient;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();
    _ambient = AnimationController(vsync: this, duration: const Duration(seconds: 16))..repeat();
    _loadTrips();
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkWebDeepLinks();
      });
    }
  }

  void _checkWebDeepLinks() {
    try {
      final uri = Uri.base;
      final start = uri.queryParameters['start'];
      final dest = uri.queryParameters['dest'];
      final days = int.tryParse(uri.queryParameters['days'] ?? '');
      if ((dest != null && dest.isNotEmpty) || (start != null && start.isNotEmpty)) {
        _planTrip(start: start, dest: dest, days: days);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _entrance.dispose();
    _ambient.dispose();
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

  // Master Trip Modal Entry Point (One-Way & Round-Trip / Vacation Planner)
  void _planTrip({String? tripType, String? start, String? dest, int? days}) =>
      showVoyPlanTripModal(
        context,
        initialMode: tripType ?? 'one_way',
        initialOrigin: start,
        initialDestination: dest,
        initialDays: days,
      );

  void _openSaved() => Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedTripsScreen()));

  void _openVehicles() => VehicleSearchSheet.show(context);

  void _openExplore() => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrekDiscoveryScreen()));

  void _openGallery() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GalleryScreen(store: TripExtrasStore('global-gallery'), tripName: 'My Travel Gallery'),
        ),
      );

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

  Widget _stagger(int index, Widget child) {
    final start = (index * 0.09).clamp(0.0, 0.6);
    final anim = CurvedAnimation(parent: _entrance, curve: Interval(start, (start + 0.55).clamp(0.0, 1.0), curve: Curves.easeOutCubic));
    return AnimatedBuilder(
      animation: anim,
      builder: (_, c) => Opacity(
        opacity: anim.value,
        child: Transform.translate(offset: Offset(0, 26 * (1 - anim.value)), child: c),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Voy.bg,
      body: Stack(
        children: [
          Positioned.fill(child: _aurora()),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: RefreshIndicator(
                  color: Voy.brand,
                  backgroundColor: Voy.surface,
                  onRefresh: _loadTrips,
                  child: ListView(
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 40),
                    children: [
                      _stagger(0, _topBar()),
                      const SizedBox(height: 18),
                      // TOP SECTION (Part 7: Active Trip HUD or Greeting + Plan a Trip)
                      _stagger(1, _topSection()),
                      const SizedBox(height: 22),
                      // THIRD SECTION (Part 7: Exactly 4 Quick Actions)
                      _stagger(2, _quickActionsSection()),
                      const SizedBox(height: 24),
                      // SECOND SECTION (Part 7: My Trips with 4 Tabs: Upcoming, Active, Drafts, Completed)
                      _stagger(3, _myTripsSection()),
                      const SizedBox(height: 24),
                      // FOURTH SECTION (Part 7: Road Trip Utilities)
                      _stagger(4, _roadTripUtilitiesSection()),
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

  // ---------- animated aurora background ----------
  Widget _aurora() {
    return AnimatedBuilder(
      animation: _ambient,
      builder: (_, __) {
        final t = _ambient.value * 2 * math.pi;
        return Stack(
          children: [
            _orb(Alignment(-0.85 + 0.18 * math.sin(t), -0.95 + 0.12 * math.cos(t)), Voy.violet, 360),
            _orb(Alignment(0.95, -0.5 + 0.22 * math.sin(t + 1.6)), Voy.brand, 320),
            _orb(Alignment(0.15 + 0.25 * math.cos(t), 0.95), Voy.pink, 380),
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
          gradient: RadialGradient(colors: [color.withValues(alpha: 0.30), color.withValues(alpha: 0.0)]),
        ),
      ),
    );
  }

  Widget _glass({required Widget child, double radius = 22, EdgeInsetsGeometry? padding, Border? border}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(radius),
            border: border ?? Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: child,
        ),
      ),
    );
  }

  // ---------- top bar ----------
  Widget _topBar() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: Voy.gradient,
            borderRadius: BorderRadius.circular(13),
            boxShadow: [BoxShadow(color: Voy.brand.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: const Icon(Icons.explore_rounded, color: Colors.white, size: 23),
        ),
        const SizedBox(width: 11),
        const Text('Voyplan', style: TextStyle(color: Voy.ink, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
        const Spacer(),
        _Pressable(
          onTap: _openProfileMenu,
          child: _glass(
            radius: 13,
            padding: EdgeInsets.zero,
            child: SizedBox(
              width: 42,
              height: 42,
              child: Center(child: Text(_userName[0].toUpperCase(), style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.w800, fontSize: 16))),
            ),
          ),
        ),
      ],
    );
  }

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

  // ---------- TOP SECTION (PART 7) ----------
  Widget _topSection() {
    if (_activeTrip != null) {
      final name = (_activeTrip!['name'] ?? 'Active Road Trip').toString();
      final remainingKm = _activeTrip!['remainingKm'] ?? 68.0;
      final eta = _activeTrip!['eta'] ?? '11:45 AM';

      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E1B4B), Color(0xFF312E81), Color(0xFF4338CA)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: const Color(0xFF312E81).withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8)),
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
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('ACTIVE TRIP', style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                ],
              ),
              const SizedBox(height: 10),
              Text(name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
              const SizedBox(height: 6),
              Text('${remainingKm.toStringAsFixed(0)} km remaining • ETA $eta', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _openTrip(_activeTrip!),
                icon: const Icon(Icons.navigation_rounded, size: 18),
                label: const Text('Continue Navigation', style: TextStyle(fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Voy.brand,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Default Greeting when no active trip
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Stack(
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 210),
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF5B3BE8), Color(0xFF7C3AED), Color(0xFFEC4899), Color(0xFFF59E0B)],
                stops: [0.0, 0.38, 0.72, 1.0],
              ),
            ),
          ),
          Positioned(
            right: -20,
            top: -10,
            child: Icon(Icons.travel_explore_rounded, size: 210, color: Colors.white.withValues(alpha: 0.14)),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$_greeting, $_userName 👋', style: TextStyle(color: Colors.white.withValues(alpha: 0.95), fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text('Where are you going?', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.1)),
                const SizedBox(height: 6),
                Text('Plan road trips with real routes, tolls, fuel & AI itinerary.', style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 13.5)),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _planTrip(tripType: 'one_way'),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                      label: const Text('One Way', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1A1240),
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 4,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _planTrip(tripType: 'round_trip'),
                      icon: const Icon(Icons.sync_alt_rounded, size: 18),
                      label: const Text('Round Trip / Vacation', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.22),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.45), width: 1.5),
                        ),
                        elevation: 0,
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
  }

  // ---------- THIRD SECTION: QUICK ACTIONS (PART 7 - ONLY 4 TILES) ----------
  Widget _quickActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Quick Actions', style: TextStyle(color: Voy.ink, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _quickTile(Icons.add_location_alt_rounded, 'Plan Trip', Voy.brand, () => _planTrip())),
            const SizedBox(width: 10),
            Expanded(child: _quickTile(Icons.bookmark_rounded, 'My Trips', Voy.violet, _openSaved)),
            const SizedBox(width: 10),
            Expanded(child: _quickTile(Icons.directions_car_rounded, 'Vehicles', Voy.coral, _openVehicles)),
            const SizedBox(width: 10),
            Expanded(child: _quickTile(Icons.explore_rounded, 'Explore', Voy.pink, _openExplore)),
          ],
        ),
      ],
    );
  }

  Widget _quickTile(IconData icon, String label, Color color, VoidCallback onTap) {
    return _Pressable(
      onTap: onTap,
      child: _glass(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.65)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 5))],
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: const TextStyle(color: Voy.ink, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- SECOND SECTION: MY TRIPS WITH 4 TABS (PART 7) ----------
  Widget _myTripsSection() {
    final tabs = [
      {'id': 'upcoming', 'label': 'Upcoming'},
      {'id': 'active', 'label': 'Active'},
      {'id': 'drafts', 'label': 'Drafts'},
      {'id': 'completed', 'label': 'Completed'},
    ];

    // Filter trips by tab
    final filtered = _trips.where((t) {
      final status = (t['status'] ?? '').toString().toUpperCase();
      if (_selectedTripTab == 'active') return status == 'ACTIVE';
      if (_selectedTripTab == 'completed') return status == 'COMPLETED';
      if (_selectedTripTab == 'drafts') return status == 'DRAFT';
      return status != 'COMPLETED' && status != 'ACTIVE' && status != 'DRAFT';
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('My Trips', style: TextStyle(color: Voy.ink, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
            const Spacer(),
            TextButton(onPressed: _openSaved, child: const Text('View all')),
          ],
        ),
        const SizedBox(height: 8),
        // 4 Tabs Selector
        Row(
          children: tabs.map((tab) {
            final isSelected = _selectedTripTab == tab['id'];
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: InkWell(
                  onTap: () => setState(() => _selectedTripTab = tab['id']!),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? Voy.brand : Voy.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isSelected ? Voy.brand : Voy.hairline),
                    ),
                    child: Center(
                      child: Text(
                        tab['label']!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected ? Colors.white : Voy.sub,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        // Trips Content
        if (_loadingTrips)
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator(color: Voy.brand)))
        else if (filtered.isEmpty)
          _emptyTripState(_selectedTripTab)
        else
          Column(
            children: filtered.take(4).map((t) => _tripCard(t)).toList(),
          ),
      ],
    );
  }

  Widget _emptyTripState(String tab) {
    String message = 'No upcoming trips scheduled.';
    if (tab == 'active') message = 'No trips currently active.';
    if (tab == 'drafts') message = 'No draft itineraries saved.';
    if (tab == 'completed') message = 'No completed journeys yet.';

    return _glass(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Icon(Icons.route_outlined, color: Voy.sub.withValues(alpha: 0.6), size: 38),
          const SizedBox(height: 10),
          Text(message, style: const TextStyle(color: Voy.sub, fontSize: 13.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => _planTrip(),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Plan Trip'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Voy.brand,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- FOURTH SECTION: ROAD TRIP UTILITIES (PART 7) ----------
  Widget _roadTripUtilitiesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Road Trip Utilities', style: TextStyle(color: Voy.ink, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _utilityTile(
              Icons.local_gas_station_rounded,
              'Fuel Status',
              '₹102.86/L Petrol • Range Check',
              Voy.coral,
              _showFuelStatusDialog,
            ),
            _utilityTile(
              Icons.toll_rounded,
              'Toll Estimate',
              'FASTag Plaza Rates & Discounts',
              Voy.brand,
              _showTollEstimateDialog,
            ),
            _utilityTile(
              Icons.wb_sunny_rounded,
              'Weather',
              'Live Route & Destination Forecast',
              Voy.pink,
              _showWeatherDialog,
            ),
            _utilityTile(
              Icons.bookmark_border_rounded,
              'Saved Places',
              'Bookmarked Attractions & Stays',
              Voy.violet,
              _openSaved,
            ),
            _utilityTile(
              Icons.emergency_rounded,
              'Nearby Services',
              'Roadside Assistance & NHAI Helpline',
              Colors.redAccent,
              _showEmergencyDialog,
            ),
          ],
        ),
      ],
    );
  }

  Widget _utilityTile(IconData icon, String title, String subtitle, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Voy.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Voy.hairline),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Voy.ink, fontSize: 13.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Voy.sub, fontSize: 11.5)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Voy.sub, size: 18),
          ],
        ),
      ),
    );
  }

  // Utility Dialogs
  void _showFuelStatusDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Voy.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.local_gas_station_rounded, color: Voy.coral),
            SizedBox(width: 10),
            Text('Fuel Status & Rates', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current Fuel Prices (India):', style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text('• Petrol: ₹102.86 / Litre\n• Diesel: ₹88.94 / Litre\n• EV Fast Charging: ₹18 - ₹22 / kWh'),
            SizedBox(height: 12),
            Text('Safety rule: refuel stops are always planned along your route before tank reaches reserve (15%).', style: TextStyle(fontSize: 12, color: Voy.sub)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showTollEstimateDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Voy.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.toll_rounded, color: Voy.brand),
            SizedBox(width: 10),
            Text('FASTag Toll Calculator', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Route-Based NHAI Toll Plazas', style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text('• 24-Hour Return Discount: 50% discount automatically applied to return journey tolls.\n• Fastag Lane Priority: Real-time electronic toll collection estimates.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showWeatherDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Voy.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.wb_sunny_rounded, color: Voy.pink),
            SizedBox(width: 10),
            Text('Live Route Weather', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Route Conditions:', style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text('• Favorable visibility for highway driving.\n• Precipitation warnings will automatically alert during active navigation.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showEmergencyDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Voy.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.emergency_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('Nearby Emergency Services', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Highway Helpline & Assistance:', style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text('• NHAI National Highway Helpline: 1033\n• Emergency Police & Medical: 112\n• Ambulance Service: 108\n• 24/7 Roadside Assistance: Available in driving mode.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _tripCard(dynamic trip) {
    final name = (trip['name'] ?? 'Trip').toString();
    final parts = name.split(' to ');
    final start = (trip['start_point']?['name'] ?? trip['start_point']?['address'] ?? (parts.isNotEmpty ? parts.first : 'Start')).toString();
    final end = (trip['end_point']?['name'] ?? trip['end_point']?['address'] ?? (parts.length > 1 ? parts.last : 'End')).toString();
    final vehicleType = (trip['vehicle_type'] ?? 'car').toString();
    final isBike = vehicleType == 'motorcycle' || vehicleType == 'bike';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _Pressable(
        onTap: () => _openTrip(trip),
        child: _glass(
          radius: 16,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: Voy.gradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Voy.brand.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Icon(isBike ? Icons.two_wheeler_rounded : Icons.directions_car_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Voy.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('$start → $end', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Voy.sub, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Voy.sub, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _openingOverlay() {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          color: Colors.black.withValues(alpha: 0.45),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Voy.brand),
                SizedBox(height: 16),
                Text('Loading your trip…', style: TextStyle(color: Voy.ink, fontWeight: FontWeight.w600)),
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
        scale: _down ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
