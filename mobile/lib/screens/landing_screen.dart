import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/trip_modal.dart';
import '../screens/login_screen.dart';
import '../screens/trek_discovery_screen.dart';
import '../screens/saved_trips_screen.dart';
import '../screens/saved_places_screen.dart';
import '../screens/smart_itinerary_screen.dart';
import '../services/stop_catalog_service.dart';
import '../widgets/trip_inspiration_modal.dart';
import '../widgets/voyplan_navigation.dart';

class LandingScreen extends StatefulWidget {
  final VoidCallback? onLogin;
  final VoidCallback? onPlanTrip;

  const LandingScreen({
    super.key,
    this.onLogin,
    this.onPlanTrip,
  });

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _howItWorksKey = GlobalKey();
  final GlobalKey _featuresKey = GlobalKey();
  final GlobalKey _exploreKey = GlobalKey();
  VoyPlanNavigationItem _activeNavigation = VoyPlanNavigationItem.home;

  // Interactive Card Controller State
  final TextEditingController _fromController =
      TextEditingController(text: 'Bangalore, Karnataka');
  final TextEditingController _toController =
      TextEditingController(text: 'Coorg, Karnataka');
  String _selectedTransport = 'Car';
  int _travelers = 2;

  @override
  void dispose() {
    _scrollController.dispose();
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  void _scrollToSection(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _handlePlanTrip({String? tripType, String? from, String? to}) {
    if (widget.onPlanTrip != null) {
      widget.onPlanTrip!();
      return;
    }
    // Launch directly via showVoyPlanTripModal
    showVoyPlanTripModal(
      context,
      initialMode: tripType ?? 'one_way',
      initialOrigin: from ?? _fromController.text.trim(),
      initialDestination: to ?? _toController.text.trim(),
    );
  }

  void _handleLogin() {
    if (widget.onLogin != null) {
      widget.onLogin!();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _handleExplore() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const TrekDiscoveryScreen(),
      ),
    );
  }

  void _setActiveNavigation(VoyPlanNavigationItem item) {
    if (mounted) setState(() => _activeNavigation = item);
  }

  void _resetNavigationAfterRoute() {
    if (mounted) _setActiveNavigation(VoyPlanNavigationItem.home);
  }

  void _handleNavigation(VoyPlanNavigationItem item) {
    _setActiveNavigation(item);
    switch (item) {
      case VoyPlanNavigationItem.home:
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
        );
        break;
      case VoyPlanNavigationItem.planTrip:
        _handlePlanTrip();
        break;
      case VoyPlanNavigationItem.destinations:
        Navigator.of(context)
            .push(
                MaterialPageRoute(builder: (_) => const TrekDiscoveryScreen()))
            .whenComplete(_resetNavigationAfterRoute);
        break;
      case VoyPlanNavigationItem.tripInspiration:
        showTripInspirationModal(context)
            .whenComplete(_resetNavigationAfterRoute);
        break;
      case VoyPlanNavigationItem.myTrips:
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const SavedTripsScreen()))
            .whenComplete(_resetNavigationAfterRoute);
        break;
      case VoyPlanNavigationItem.savedPlaces:
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const SavedPlacesScreen()))
            .whenComplete(_resetNavigationAfterRoute);
        break;
      case VoyPlanNavigationItem.features:
        _scrollToSection(_featuresKey);
        break;
      case VoyPlanNavigationItem.aiCopilot:
        Navigator.of(context)
            .push(
                MaterialPageRoute(builder: (_) => const SmartItineraryScreen()))
            .whenComplete(_resetNavigationAfterRoute);
        break;
    }
  }

  void _openSignIn() {
    _handleLogin();
  }

  void _openGetStarted() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen(startInSignUp: true)),
    );
  }

  void _showThemeStatus() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('VoyPlan is using the dark travel theme.')),
    );
  }

  void _handleDestinationClick(String destination) {
    _handlePlanTrip(
      tripType: 'vacation',
      from: 'Bangalore, Karnataka',
      to: destination,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1024;
    final isTablet = screenWidth >= 700 && screenWidth < 1024;
    final hasExpandedNavigation = screenWidth >= 1440;

    return Scaffold(
      backgroundColor: Voy.bg,
      endDrawer: !hasExpandedNavigation ? _buildMobileDrawer() : null,
      body: Stack(
        children: [
          // Subtle Royal Background Glow
          Positioned(
            top: -150,
            left: -150,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Voy.gold.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 400,
            right: -200,
            child: Container(
              width: 600,
              height: 600,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Voy.navyLight.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Main Scrollable Page
          Scrollbar(
            controller: _scrollController,
            thumbVisibility: isDesktop,
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const ClampingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Navigation Header
                  _buildHeader(isDesktop: hasExpandedNavigation),

                  // 2. Hero Section
                  _buildHero(isDesktop: isDesktop, isTablet: isTablet),

                  // 3. Value Strip
                  _buildValueStrip(isDesktop: isDesktop),

                  // 4. How It Works
                  Container(
                    key: _howItWorksKey,
                    child: _buildHowItWorks(isDesktop: isDesktop),
                  ),

                  // 5. One Way Trip Showcase
                  _buildOneWaySection(isDesktop: isDesktop),

                  // 6. Vacation Showcase (Strictly Vacation, NO Round Trip)
                  _buildVacationSection(isDesktop: isDesktop),

                  // 7. AI Itinerary Planner Showcase
                  _buildAIPlannerSection(isDesktop: isDesktop),

                  // 8. Smart Stop Points Showcase
                  _buildSmartStopsSection(isDesktop: isDesktop),

                  // 9. Fuel + Budget Engine Showcase
                  _buildFuelAndBudgetSection(isDesktop: isDesktop),

                  // 10. Explore Destinations
                  Container(
                    key: _exploreKey,
                    child: _buildExploreSection(isDesktop: isDesktop),
                  ),

                  // 11. Feature Grid
                  Container(
                    key: _featuresKey,
                    child: _buildFeatureGrid(isDesktop: isDesktop),
                  ),

                  // 12. Final CTA
                  _buildFinalCTA(isDesktop: isDesktop),

                  // 13. Footer
                  _buildFooter(isDesktop: isDesktop),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // 1. HEADER
  // ==========================================================================
  Widget _buildHeader({required bool isDesktop}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 48 : 20,
        vertical: 18,
      ),
      decoration: BoxDecoration(
        color: Voy.bg.withValues(alpha: 0.85),
        border: Border(
            bottom: BorderSide(color: Voy.hairline.withValues(alpha: 0.6))),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // VoyPlan Logo & Wordmark
            InkWell(
              onTap: () => _handleNavigation(VoyPlanNavigationItem.home),
              borderRadius: BorderRadius.circular(12),
              child: _buildBrandLockup(),
            ),
            const Spacer(),

            // Desktop Navigation Links
            if (isDesktop) ...[
              ...voyPlanPrimaryNavigation.map(
                (item) => _navLink(
                  item.label,
                  () => _handleNavigation(item),
                  isActive: _activeNavigation == item,
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Search',
                onPressed: _handleExplore,
                icon: const Icon(Icons.search_rounded, color: Voy.ink),
              ),
              IconButton(
                tooltip: 'Theme switcher',
                onPressed: _showThemeStatus,
                icon: const Icon(Icons.dark_mode_outlined, color: Voy.ink),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _openSignIn,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Voy.gold.withValues(alpha: 0.5)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  'Sign In',
                  style: TextStyle(
                    color: Voy.gold,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              ElevatedButton(
                onPressed: _openGetStarted,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Voy.gold,
                  foregroundColor: const Color(0xFF070D18),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Get Started',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Mobile Hamburger
              Builder(
                builder: (context) => IconButton(
                  icon:
                      const Icon(Icons.menu_rounded, color: Voy.ink, size: 28),
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBrandLockup() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset(
            'assets/icon/voyplan_dark.png',
            width: 38,
            height: 38,
            fit: BoxFit.contain,
            semanticLabel: 'VoyPlan',
          ),
        ),
        const SizedBox(width: 10),
        const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'VoyPlan',
              style: TextStyle(
                color: Voy.ink,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
            ),
            Text(
              'DISCOVER. DESIGN. DRIVE.',
              style: TextStyle(
                color: Voy.gold,
                fontSize: 7.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.9,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _navLink(String label, VoidCallback onTap, {bool isActive = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? Voy.gold : Voy.ink,
              fontSize: 14,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  // Mobile Slide Navigation Drawer
  Widget _buildMobileDrawer() {
    return Drawer(
      backgroundColor: Voy.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: ListView(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildBrandLockup(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Voy.sub),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(color: Voy.hairline, height: 32),
              ...voyPlanPrimaryNavigation.map(
                (item) => _drawerItem(item.icon, item.label, () {
                  Navigator.of(context).pop();
                  _handleNavigation(item);
                }, isActive: _activeNavigation == item),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Search',
                    onPressed: () {
                      Navigator.of(context).pop();
                      _handleExplore();
                    },
                    icon: const Icon(Icons.search_rounded, color: Voy.ink),
                  ),
                  IconButton(
                    tooltip: 'Theme switcher',
                    onPressed: _showThemeStatus,
                    icon: const Icon(Icons.dark_mode_outlined, color: Voy.ink),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _openSignIn();
                  },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Voy.gold.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Sign In',
                      style: TextStyle(
                          color: Voy.gold, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _openGetStarted();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Voy.gold,
                    foregroundColor: const Color(0xFF070D18),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Get Started',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String label, VoidCallback onTap,
      {bool isActive = false}) {
    return ListTile(
      leading: Icon(icon, color: isActive ? Voy.gold : Voy.sub, size: 22),
      title: Text(label,
          style: TextStyle(
              color: isActive ? Voy.gold : Voy.ink,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
              fontSize: 16)),
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
    );
  }

  // ==========================================================================
  // 2. HERO SECTION + MAP VISUAL + INTERACTIVE PLANNER CARD
  // ==========================================================================
  Widget _buildHero({required bool isDesktop, required bool isTablet}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 48 : 20,
        vertical: isDesktop ? 56 : 32,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: isDesktop
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Left Column: Royal Headline, Subheading, CTAs
                    Expanded(
                      flex: 52,
                      child: _buildHeroLeftContent(isDesktop: true),
                    ),
                    const SizedBox(width: 48),
                    // Right Column: Visual Map + Interactive Trip Card
                    Expanded(
                      flex: 48,
                      child: _buildHeroVisualAndCard(),
                    ),
                  ],
                )
              : Column(
                  children: [
                    _buildHeroLeftContent(isDesktop: false),
                    const SizedBox(height: 36),
                    _buildHeroVisualAndCard(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildHeroLeftContent({required bool isDesktop}) {
    return Column(
      crossAxisAlignment:
          isDesktop ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        // Royal Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Voy.gold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Voy.gold.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.compass_calibration_rounded,
                  color: Voy.gold, size: 16),
              const SizedBox(width: 8),
              Text(
                'THE INTELLIGENT TRAVEL COMPANION',
                style: TextStyle(
                  color: Voy.gold,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Hero Heading
        Text(
          'Plan Smarter.\nTravel Better.',
          textAlign: isDesktop ? TextAlign.start : TextAlign.center,
          style: Voy.royalSerif(
            fontSize: isDesktop ? 54 : 36,
            fontWeight: FontWeight.w900,
            height: 1.12,
            letterSpacing: -0.5,
            color: Voy.ink,
          ),
        ),
        const SizedBox(height: 20),

        // Supporting Message
        Text(
          'Your intelligent travel companion for planning routes, discovering meaningful stops, calculating costs, and building unforgettable journeys.',
          textAlign: isDesktop ? TextAlign.start : TextAlign.center,
          style: TextStyle(
            color: Voy.sub,
            fontSize: isDesktop ? 17 : 15,
            height: 1.6,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 32),

        // CTAs
        Wrap(
          spacing: 16,
          runSpacing: 12,
          alignment: isDesktop ? WrapAlignment.start : WrapAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => _handlePlanTrip(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Voy.gold,
                foregroundColor: const Color(0xFF070D18),
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                elevation: 6,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.near_me_rounded, size: 18),
                  SizedBox(width: 10),
                  Text(
                    'Plan Your Trip',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
            OutlinedButton(
              onPressed: _handleExplore,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Voy.hairline, width: 1.5),
                backgroundColor: Voy.surface.withValues(alpha: 0.6),
                foregroundColor: Voy.ink,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.travel_explore_rounded, size: 18, color: Voy.gold),
                  SizedBox(width: 8),
                  Text(
                    'Explore Destinations',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Visual Map Journey + Floating Interactive Planner Card
  Widget _buildHeroVisualAndCard() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Background Map Canvas Visual
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Voy.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Voy.hairline),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Compass & Map Route Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.explore, color: Voy.gold, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'ROUTE CORRIDOR & WAYPOINTS',
                        style: TextStyle(
                          color: Voy.gold,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Voy.surface2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Voy.hairline),
                    ),
                    child: const Text(
                      'NH-275 • 268 km',
                      style: TextStyle(
                          color: Voy.sub,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Visual Route Progression Nodes
              _buildRouteVisualStep(
                icon: Icons.trip_origin_rounded,
                iconColor: const Color(0xFF10B981),
                title: 'Starting Point',
                subtitle: 'Bangalore (0 km • 06:30 AM)',
                isLast: false,
              ),
              _buildRouteVisualStep(
                icon: Icons.local_gas_station_rounded,
                iconColor: const Color(0xFFF59E0B),
                title: 'Fuel & EV Fast Charge Stop',
                subtitle: 'BPCL Highway Oasis (+1m detour)',
                isLast: false,
              ),
              _buildRouteVisualStep(
                icon: Icons.restaurant_rounded,
                iconColor: const Color(0xFF38BDF8),
                title: 'Breakfast & Rest Stop',
                subtitle: 'Kamat Lokaruchi Heritage Kitchen',
                isLast: false,
              ),
              _buildRouteVisualStep(
                icon: Icons.museum_rounded,
                iconColor: const Color(0xFFEC4899),
                title: 'Scenic Attraction',
                subtitle: 'Bylakuppe Golden Temple (Namdroling)',
                isLast: false,
              ),
              _buildRouteVisualStep(
                icon: Icons.location_on_rounded,
                iconColor: Voy.gold,
                title: 'Destination Arrival',
                subtitle: 'Madikeri, Coorg (268 km • 12:30 PM)',
                isLast: true,
              ),

              const SizedBox(height: 24),
              // Embedded Interactive Quick Planner Form
              _buildInteractiveCardForm(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRouteVisualStep({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isLast,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                    color: iconColor.withValues(alpha: 0.8), width: 1.5),
              ),
              child: Icon(icon, color: iconColor, size: 14),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 26,
                color: Voy.hairline,
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Voy.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Voy.sub,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Interactive Trip Card
  Widget _buildInteractiveCardForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Voy.surface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Voy.gold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: Voy.gold, size: 16),
              const SizedBox(width: 6),
              Text(
                'WHERE ARE YOU GOING?',
                style: TextStyle(
                  color: Voy.gold,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Origin & Destination Inputs
          Row(
            children: [
              Expanded(
                child: _cardInput(
                    'From', _fromController, Icons.my_location_rounded),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _cardInput('To', _toController, Icons.pin_drop_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Mode & Travelers Row
          Row(
            children: [
              // Travel Mode
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Voy.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Voy.hairline),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedTransport,
                      dropdownColor: Voy.surface,
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: Voy.sub),
                      items: ['Car', 'SUV', 'Motorcycle', 'EV']
                          .map((m) => DropdownMenuItem(
                                value: m,
                                child: Text(
                                  m,
                                  style: const TextStyle(
                                      color: Voy.ink,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold),
                                ),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedTransport = v);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Travelers Counter
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Voy.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Voy.hairline),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Icon(Icons.people_rounded,
                          color: Voy.gold, size: 16),
                      Text(
                        '$_travelers Travelers',
                        style: const TextStyle(
                            color: Voy.ink,
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold),
                      ),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _travelers = _travelers >= 6 ? 1 : _travelers + 1;
                          });
                        },
                        child: const Icon(Icons.add_circle_outline,
                            color: Voy.gold, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Action Button connecting to real Trip Modal
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _handlePlanTrip(
                tripType: 'one_way',
                from: _fromController.text.trim(),
                to: _toController.text.trim(),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Voy.gold,
                foregroundColor: const Color(0xFF070D18),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text(
                'Plan My Trip',
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardInput(String label, TextEditingController ctrl, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Voy.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Voy.hairline),
      ),
      child: TextField(
        controller: ctrl,
        style: const TextStyle(
            color: Voy.ink, fontSize: 13, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          icon: Icon(icon, color: Voy.gold, size: 16),
          labelText: label,
          labelStyle: const TextStyle(color: Voy.sub, fontSize: 11),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
        ),
      ),
    );
  }

  // ==========================================================================
  // 3. VALUE STRIP
  // ==========================================================================
  Widget _buildValueStrip({required bool isDesktop}) {
    final values = [
      (Icons.auto_awesome_rounded, 'AI-Powered Planning'),
      (Icons.alt_route_rounded, 'Smart Routes'),
      (Icons.place_rounded, 'Stop Point Discovery'),
      (Icons.local_gas_station_rounded, 'Fuel Planning'),
      (Icons.account_balance_wallet_rounded, 'Budget Estimation'),
      (Icons.navigation_rounded, 'Live Navigation'),
    ];

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: isDesktop ? 48 : 20,
        vertical: 24,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: Voy.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Voy.hairline),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 16,
        alignment: WrapAlignment.spaceAround,
        children: values.map((v) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(v.$1, color: Voy.gold, size: 18),
              const SizedBox(width: 8),
              Text(
                v.$2,
                style: const TextStyle(
                  color: Voy.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ==========================================================================
  // 4. HOW IT WORKS (4 STEPS)
  // ==========================================================================
  Widget _buildHowItWorks({required bool isDesktop}) {
    final steps = [
      (
        '01',
        'Choose Your Journey',
        'Select between a focused One Way road expedition or an immersive multi-day Vacation itinerary.',
        Icons.travel_explore_rounded
      ),
      (
        '02',
        'Set Your Preferences',
        'Specify starting location, destinations, travel dates, passenger count, vehicle specs, mileage, and budget.',
        Icons.tune_rounded
      ),
      (
        '03',
        'Build Your Journey',
        'VoyPlan algorithmically crafts your route corridor, fuel stops, attractions, dining halts, and budget breakdown.',
        Icons.alt_route_rounded
      ),
      (
        '04',
        'Travel With Confidence',
        'Follow synchronized live turn-by-turn navigation with real-time waypoint alerts and fuel reserve protection.',
        Icons.navigation_rounded
      ),
    ];

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 48 : 20,
        vertical: 60,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            children: [
              _sectionHeader(
                tag: 'HOW IT WORKS',
                title: 'From Conception to Destination in Four Steps',
                subtitle:
                    'Engineered for seamless precision, comprehensive stops, and predictable costs.',
              ),
              const SizedBox(height: 48),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 900;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: steps.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount:
                          isWide ? 4 : (constraints.maxWidth >= 550 ? 2 : 1),
                      mainAxisSpacing: 20,
                      crossAxisSpacing: 20,
                      childAspectRatio: isWide ? 0.9 : 1.3,
                    ),
                    itemBuilder: (context, idx) {
                      final s = steps[idx];
                      return Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Voy.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Voy.hairline),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  s.$1,
                                  style: Voy.royalSerif(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    color: Voy.gold,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Voy.surface2,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Voy.hairline),
                                  ),
                                  child: Icon(s.$4, color: Voy.gold, size: 20),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Text(
                              s.$2,
                              style: const TextStyle(
                                color: Voy.ink,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              s.$3,
                              style: const TextStyle(
                                color: Voy.sub,
                                fontSize: 12.5,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // 5. ONE WAY SHOWCASE
  // ==========================================================================
  Widget _buildOneWaySection({required bool isDesktop}) {
    return Container(
      color: Voy.surface,
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 48 : 20,
        vertical: 64,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            children: [
              _sectionHeader(
                tag: 'ONE WAY JOURNEYS',
                title: 'Point-to-Point Precision with Curated Corridor Stops',
                subtitle:
                    'Complete route intelligence: real road distance, ETA, refuel recommendations, tolls, and stop points.',
              ),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Voy.surface2,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Voy.hairline),
                ),
                child: Column(
                  children: [
                    // Corridor Overview
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Bangalore → Coorg Expedition',
                              style: TextStyle(
                                color: Voy.ink,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Corridor: NH-275 • Scenic Ghat Pass',
                              style: TextStyle(color: Voy.sub, fontSize: 12),
                            ),
                          ],
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _handlePlanTrip(
                            tripType: 'one_way',
                            from: 'Bangalore, Karnataka',
                            to: 'Coorg, Karnataka',
                          ),
                          icon: const Icon(Icons.add_road_rounded, size: 16),
                          label: const Text('Plan a One Way Trip'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Voy.gold,
                            foregroundColor: const Color(0xFF070D18),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Divider(color: Voy.hairline),
                    const SizedBox(height: 24),

                    // Metrics Strip
                    Wrap(
                      spacing: 32,
                      runSpacing: 16,
                      children: [
                        _metricBadge(
                            Icons.straighten_rounded, 'Distance', '268 km'),
                        _metricBadge(
                            Icons.timer_rounded, 'Drive Time', '5h 45m'),
                        _metricBadge(Icons.local_gas_station_rounded,
                            'Fuel Required', '17.8 L (15 km/L)'),
                        _metricBadge(
                            Icons.toll_rounded, 'Est. Tolls', '₹440 (FASTag)'),
                        _metricBadge(Icons.account_balance_wallet_rounded,
                            'Est. Budget', '₹3,450 total'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // 6. VACATION SHOWCASE (STRICTLY VACATION)
  // ==========================================================================
  Widget _buildVacationSection({required bool isDesktop}) {
    final itineraryDays = [
      (
        'DAY 1',
        'Bangalore → Mysore Heritage → Coorg Misty Hills',
        'Depart at 06:30 AM • Breakfast at Ramanagara • Mysore Palace Tour • Arrive at Kodagu plantation resort.',
        ['Heritage', 'Scenic Drive', 'Local Cuisine'],
      ),
      (
        'DAY 2',
        'Coorg Immersive Coffee Country Exploration',
        'Abbey Falls morning mist • Dubare Elephant Camp • Coffee plantation guided tasting • Sunset at Raja’s Seat.',
        ['Nature', 'Plantation Tour', 'Viewpoint'],
      ),
      (
        'DAY 3',
        'Coorg → Namdroling Monastery → Bangalore Return',
        'Golden Temple Bylakuppe blessings • Traditional Kodava lunch • Scenic expressway return with refuel check.',
        ['Culture', 'Return Drive', 'FASTag Corridors'],
      ),
    ];

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 48 : 20,
        vertical: 64,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            children: [
              _sectionHeader(
                tag: 'MULTI-DAY VACATIONS',
                title: 'Curated Vacation Itineraries Built for Discoverers',
                subtitle:
                    'Multi-day routing, day-by-day itineraries, verified stays, activities, and synchronized return journeys.',
              ),
              const SizedBox(height: 40),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 900;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: isWide ? 60 : 100,
                        child: Column(
                          children: itineraryDays.map((d) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Voy.surface,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: Voy.hairline),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color:
                                              Voy.gold.withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          d.$1,
                                          style: const TextStyle(
                                            color: Voy.gold,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      Wrap(
                                        spacing: 6,
                                        children: d.$4.map((tag) {
                                          return Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Voy.surface2,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              tag,
                                              style: const TextStyle(
                                                  color: Voy.sub,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    d.$2,
                                    style: const TextStyle(
                                      color: Voy.ink,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    d.$3,
                                    style: const TextStyle(
                                        color: Voy.sub,
                                        fontSize: 13,
                                        height: 1.4),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      if (isWide) ...[
                        const SizedBox(width: 28),
                        Expanded(
                          flex: 40,
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Voy.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: Voy.gold.withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'VACATION HIGHLIGHTS',
                                  style: TextStyle(
                                    color: Voy.gold,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _highlightRow(Icons.hotel_rounded,
                                    'Stay Included', 'Plantation Eco-Resorts'),
                                _highlightRow(Icons.restaurant_rounded,
                                    'Dining', 'Curated Kodava Cuisine'),
                                _highlightRow(Icons.museum_rounded,
                                    'Attractions', '4 Pre-routed Key Sights'),
                                _highlightRow(Icons.local_gas_station_rounded,
                                    'Refuel Corridor', 'Highway Swagat Hubs'),
                                _highlightRow(Icons.keyboard_return_rounded,
                                    'Return Leg', 'Synchronized Schedule'),
                                const SizedBox(height: 24),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: () => _handlePlanTrip(
                                      tripType: 'vacation',
                                      from: 'Bangalore, Karnataka',
                                      to: 'Coorg, Karnataka',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Voy.gold,
                                      foregroundColor: const Color(0xFF070D18),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                    ),
                                    child: const Text('Plan a Vacation',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w900)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _highlightRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Voy.gold, size: 18),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Voy.sub, fontSize: 13)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  color: Voy.ink, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  // ==========================================================================
  // 7. AI PLANNER SHOWCASE
  // ==========================================================================
  Widget _buildAIPlannerSection({required bool isDesktop}) {
    final itinerarySlots = [
      (
        '08:00 AM',
        'Leave Bangalore',
        'Start with full fuel tank from origin',
        Icons.directions_car_rounded
      ),
      (
        '10:30 AM',
        'Breakfast at Ramanagara',
        'Traditional South Indian thali at Kamat Lokaruchi',
        Icons.restaurant_rounded
      ),
      (
        '12:00 PM',
        'Mysore Palace Heritage Stop',
        '1h 30m guided photography walk through palace corridors',
        Icons.museum_rounded
      ),
      (
        '02:00 PM',
        'Scenic Lunch Break',
        'Fresh garden meal along Hunsur highway',
        Icons.local_dining_rounded
      ),
      (
        '04:00 PM',
        'Scenic Valley Overlook',
        'Channapatna craft stalls & panoramic tea gardens',
        Icons.landscape_rounded
      ),
      (
        '06:30 PM',
        'Hotel Check-in',
        'Madikeri plantation resort welcome tea & relaxation',
        Icons.hotel_rounded
      ),
    ];

    return Container(
      color: Voy.surface,
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 48 : 20,
        vertical: 64,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            children: [
              _sectionHeader(
                tag: 'AI ITINERARY ENGINE',
                title: 'Your Journey, Intelligently Planned.',
                subtitle:
                    'Powered by real geographic coordinates, real travel times, and zero hallucinatory routing.',
              ),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Voy.surface2,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Voy.hairline),
                ),
                child: Column(
                  children: itinerarySlots.map((slot) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Voy.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Voy.hairline),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Voy.gold.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              slot.$1,
                              style: const TextStyle(
                                color: Voy.gold,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Icon(slot.$4, color: Voy.sub, size: 20),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  slot.$2,
                                  style: const TextStyle(
                                      color: Voy.ink,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14),
                                ),
                                Text(slot.$3,
                                    style: const TextStyle(
                                        color: Voy.sub, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // 8. SMART STOP POINTS SHOWCASE
  // ==========================================================================
  Widget _buildSmartStopsSection({required bool isDesktop}) {
    final categories =
        StopCatalogService.categories.where((c) => c.key != 'all').toList();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 48 : 20,
        vertical: 64,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            children: [
              _sectionHeader(
                tag: 'STOP POINT CATALOG',
                title: 'The Best Stops Are Part of the Journey.',
                subtitle:
                    'Discover verified locations along your route corridor with minimal detour and guaranteed opening hours.',
              ),
              const SizedBox(height: 40),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 900;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: categories.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount:
                          isWide ? 4 : (constraints.maxWidth >= 550 ? 3 : 2),
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 2.2,
                    ),
                    itemBuilder: (context, idx) {
                      final c = categories[idx];
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Voy.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Voy.hairline),
                        ),
                        child: Row(
                          children: [
                            Icon(c.icon, color: c.color, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                c.label,
                                style: const TextStyle(
                                  color: Voy.ink,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // 9. FUEL + BUDGET ENGINE PREVIEW
  // ==========================================================================
  Widget _buildFuelAndBudgetSection({required bool isDesktop}) {
    return Container(
      color: Voy.surface,
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 48 : 20,
        vertical: 64,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            children: [
              _sectionHeader(
                tag: 'FINANCIAL & FUEL INTELLIGENCE',
                title: 'Transparent Budgeting and Predictive Range',
                subtitle:
                    'Every trip synchronized: distance yields fuel demand, fuel demand determines stops, stops compute the final cost.',
              ),
              const SizedBox(height: 40),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 900;
                  final fuelCard = Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Voy.surface2,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Voy.hairline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.local_gas_station_rounded,
                                color: Voy.gold, size: 20),
                            SizedBox(width: 10),
                            Text(
                              'FUEL PLANNING',
                              style: TextStyle(
                                  color: Voy.ink,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _budgetRow('Vehicle Fuel Efficiency', '15.0 km/L'),
                        _budgetRow('Current Fuel in Tank', '10.0 L'),
                        _budgetRow('Estimated Initial Range', '150 km'),
                        _budgetRow('Required Fuel for Route', '17.8 L'),
                        _budgetRow('Refuel Requirement',
                            '1 Recommended Stop at KM 120'),
                      ],
                    ),
                  );

                  final budgetCard = Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Voy.surface2,
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: Voy.gold.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Flexible(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.account_balance_wallet_rounded,
                                      color: Voy.gold, size: 20),
                                  SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      'ESTIMATED TRIP BUDGET',
                                      style: TextStyle(
                                          color: Voy.ink,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '₹18,450',
                              style: Voy.royalSerif(
                                  fontSize: 20,
                                  color: Voy.gold,
                                  fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _budgetRow('Fuel Cost (17.8 L)', '₹1,825'),
                        _budgetRow('Highway Tolls (FASTag)', '₹440'),
                        _budgetRow('Accommodation (2 Nights)', '₹6,000'),
                        _budgetRow('Dining & Food (2 Travelers)', '₹3,600'),
                        _budgetRow('Activities & Sightseeing', '₹2,500'),
                        _budgetRow('Parking & Incidentals', '₹650'),
                        const Divider(color: Voy.hairline, height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Flexible(
                              child: Text(
                                'Per Traveler (2 People)',
                                style: TextStyle(color: Voy.sub, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text('₹9,225',
                                style: const TextStyle(
                                    color: Voy.ink,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                          ],
                        ),
                      ],
                    ),
                  );

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 50, child: fuelCard),
                        const SizedBox(width: 24),
                        Expanded(flex: 50, child: budgetCard),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        fuelCard,
                        const SizedBox(height: 24),
                        budgetCard,
                      ],
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _budgetRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(color: Voy.sub, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Text(val,
              style: const TextStyle(
                  color: Voy.ink, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }

  // ==========================================================================
  // 10. EXPLORE DESTINATIONS
  // ==========================================================================
  Widget _buildExploreSection({required bool isDesktop}) {
    final destinations = [
      (
        'Coorg, Karnataka',
        'Misty valleys, lush coffee plantations, and roaring waterfalls in Scotland of India.',
        'Oct - Mar',
        'https://images.unsplash.com/photo-1544735716-392fe2489ffa?w=600&q=80',
      ),
      (
        'Mysore, Karnataka',
        'Palatial heritage, regal architecture, and silk bazaars.',
        'Year-round',
        'https://images.unsplash.com/photo-1582510003544-4d00b7f74220?w=600&q=80',
      ),
      (
        'Ooty, Tamil Nadu',
        'Queen of hill stations, Nilgiri mountain railway, and tea gardens.',
        'Sep - May',
        'https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=600&q=80',
      ),
      (
        'Wayanad, Kerala',
        'Ancient caves, spice plantations, and serene bamboo forests.',
        'Oct - May',
        'https://images.unsplash.com/photo-1563986768609-322da13575f3?w=600&q=80',
      ),
      (
        'Chikmagalur, Karnataka',
        'Mullayanagiri peak trails, bababudangiri hills, and fragrant coffee aroma.',
        'Sep - Mar',
        'https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?w=600&q=80',
      ),
      (
        'Goa, India',
        'Sun-kissed beaches, coastal highways, and heritage Portuguese quarters.',
        'Nov - Feb',
        'https://images.unsplash.com/photo-1512343879784-a960bf40e7f2?w=600&q=80',
      ),
    ];

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 48 : 20,
        vertical: 64,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            children: [
              _sectionHeader(
                tag: 'ICONIC DESTINATIONS',
                title: 'Curated Road Trip Escapes',
                subtitle:
                    'Explore pre-verified routes with turnkey itineraries, verified fuel corridors, and top ratings.',
              ),
              const SizedBox(height: 40),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 900;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: destinations.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount:
                          isWide ? 3 : (constraints.maxWidth >= 550 ? 2 : 1),
                      mainAxisSpacing: 20,
                      crossAxisSpacing: 20,
                      childAspectRatio: 0.82,
                    ),
                    itemBuilder: (context, idx) {
                      final d = destinations[idx];
                      return Container(
                        decoration: BoxDecoration(
                          color: Voy.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Voy.hairline),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: 180,
                              width: double.infinity,
                              child: Image.network(
                                d.$4,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Voy.surface2,
                                  child: const Icon(Icons.landscape_rounded,
                                      color: Voy.sub, size: 48),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          d.$1,
                                          style: Voy.royalSerif(
                                              fontSize: 18,
                                              color: Voy.ink,
                                              fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color:
                                              Voy.gold.withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          d.$3,
                                          style: const TextStyle(
                                              color: Voy.gold,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    d.$2,
                                    style: const TextStyle(
                                        color: Voy.sub,
                                        fontSize: 12.5,
                                        height: 1.4),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton(
                                      onPressed: () =>
                                          _handleDestinationClick(d.$1),
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(
                                            color: Voy.gold
                                                .withValues(alpha: 0.4)),
                                      ),
                                      child: const Text('Explore & Plan',
                                          style: TextStyle(
                                              color: Voy.gold,
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // 11. FEATURE GRID (8 PILLARS)
  // ==========================================================================
  Widget _buildFeatureGrid({required bool isDesktop}) {
    final features = [
      (
        Icons.auto_awesome_rounded,
        'AI Trip Planner',
        'Build custom itineraries based on trip type, travelers, and travel pacing.'
      ),
      (
        Icons.alt_route_rounded,
        'Smart Routes',
        'Reliable road corridors with accurate distance, ETA, and road condition insights.'
      ),
      (
        Icons.storefront_rounded,
        'Stop Point Catalog',
        '13 categories of route-aware food, stay, sightseeing, EV, and fuel stops.'
      ),
      (
        Icons.local_gas_station_rounded,
        'Fuel Planning',
        'Calculate fuel required, current tank range, and guaranteed refuel halts.'
      ),
      (
        Icons.account_balance_wallet_rounded,
        'Budget Engine',
        'Comprehensive expense breakdown across fuel, tolls, stay, meals, and tickets.'
      ),
      (
        Icons.navigation_rounded,
        'Live Navigation',
        'Active GPS guidance, live speed, upcoming waypoint HUD, and turn indicators.'
      ),
      (
        Icons.bookmark_rounded,
        'Saved Places',
        'Bookmark your favorite viewpoints, boutique stays, and roadside diners.'
      ),
      (
        Icons.history_rounded,
        'My Trips',
        'Review, reopen, duplicate, and modify complete past and upcoming expeditions.'
      ),
    ];

    return Container(
      color: Voy.surface,
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 48 : 20,
        vertical: 64,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            children: [
              _sectionHeader(
                tag: 'PLATFORM CAPABILITIES',
                title: 'Engineered for Every Stage of the Road',
                subtitle:
                    'A single unified travel operating system replacing scattered spreadsheets and maps.',
              ),
              const SizedBox(height: 48),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 900;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: features.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount:
                          isWide ? 4 : (constraints.maxWidth >= 550 ? 2 : 1),
                      mainAxisSpacing: 20,
                      crossAxisSpacing: 20,
                      childAspectRatio: isWide ? 1.05 : 1.3,
                    ),
                    itemBuilder: (context, idx) {
                      final f = features[idx];
                      return Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: Voy.surface2,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Voy.hairline),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Voy.gold.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(f.$1, color: Voy.gold, size: 22),
                            ),
                            const Spacer(),
                            Text(
                              f.$2,
                              style: const TextStyle(
                                  color: Voy.ink,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              f.$3,
                              style: const TextStyle(
                                  color: Voy.sub, fontSize: 12, height: 1.4),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // 12. FINAL CTA
  // ==========================================================================
  Widget _buildFinalCTA({required bool isDesktop}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 48 : 20,
        vertical: 80,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 48 : 24,
              vertical: 48,
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0D1726), Color(0xFF172A45)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                  color: Voy.gold.withValues(alpha: 0.4), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Voy.gold.withValues(alpha: 0.1),
                  blurRadius: 40,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                const Icon(Icons.explore_rounded, color: Voy.gold, size: 42),
                const SizedBox(height: 20),
                Text(
                  'Your Next Journey Starts Here.',
                  textAlign: TextAlign.center,
                  style: Voy.royalSerif(
                    fontSize: isDesktop ? 38 : 26,
                    fontWeight: FontWeight.w900,
                    color: Voy.ink,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Build your route, discover meaningful stops, understand your costs, and travel with confidence.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Voy.sub,
                    fontSize: isDesktop ? 16 : 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () => _handlePlanTrip(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Voy.gold,
                        foregroundColor: const Color(0xFF070D18),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 18),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Plan Your Trip',
                          style: TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 15)),
                    ),
                    OutlinedButton(
                      onPressed: _handleExplore,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Voy.gold),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 18),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Explore VoyPlan',
                          style: TextStyle(
                              color: Voy.gold,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // 13. FOOTER
  // ==========================================================================
  Widget _buildFooter({required bool isDesktop}) {
    return Container(
      color: const Color(0xFF050910),
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 48 : 20,
        vertical: 48,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Brand Col
                  Expanded(
                    flex: isDesktop ? 40 : 100,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.explore_rounded,
                                color: Voy.gold, size: 22),
                            const SizedBox(width: 10),
                            Text(
                              'VoyPlan',
                              style: Voy.royalSerif(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Discover. Design. Drive. Intelligent routes, multi-day vacations, and transparent road trip economics.',
                          style: TextStyle(
                              color: Voy.sub, fontSize: 13, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  if (isDesktop) ...[
                    const Spacer(),
                    // Product Links
                    _footerCol('PRODUCT', [
                      ('Plan Trip', () => _handlePlanTrip()),
                      ('One Way', () => _handlePlanTrip(tripType: 'one_way')),
                      ('Vacation', () => _handlePlanTrip(tripType: 'vacation')),
                      ('Explore', _handleExplore),
                      (
                        'My Trips',
                        () {
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => const SavedTripsScreen()));
                        }
                      ),
                      (
                        'Saved Places',
                        () {
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => const SavedPlacesScreen()));
                        }
                      ),
                    ]),
                    const SizedBox(width: 48),
                    // Company Links
                    _footerCol('COMPANY', [
                      ('About', () => _scrollToSection(_howItWorksKey)),
                      ('Features', () => _scrollToSection(_featuresKey)),
                      ('Contact', () {}),
                    ]),
                    const SizedBox(width: 48),
                    // Support Links
                    _footerCol('SUPPORT', [
                      ('Help Center', () {}),
                      ('Privacy Policy', () {}),
                      ('Terms of Service', () {}),
                    ]),
                  ],
                ],
              ),
              const SizedBox(height: 36),
              const Divider(color: Voy.hairline),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 12,
                children: [
                  Text(
                    '© ${DateTime.now().year} VoyPlan. All rights reserved.',
                    style: const TextStyle(color: Voy.sub, fontSize: 12),
                  ),
                  const Text(
                    'DISCOVER. DESIGN. DRIVE. • voyplan.in',
                    style: TextStyle(
                        color: Voy.gold,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footerCol(String title, List<(String, VoidCallback)> links) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
              color: Voy.ink,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 1.0),
        ),
        const SizedBox(height: 14),
        ...links.map((link) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: link.$2,
              child: Text(
                link.$1,
                style: const TextStyle(color: Voy.sub, fontSize: 13),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _sectionHeader({
    required String tag,
    required String title,
    required String subtitle,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: Voy.gold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Voy.gold.withValues(alpha: 0.3)),
          ),
          child: Text(
            tag,
            style: const TextStyle(
              color: Voy.gold,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Voy.royalSerif(
              fontSize: 30, fontWeight: FontWeight.w800, color: Voy.ink),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Voy.sub, fontSize: 14, height: 1.5),
          ),
        ),
      ],
    );
  }

  Widget _metricBadge(IconData icon, String label, String val) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Voy.gold, size: 18),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Voy.sub, fontSize: 11)),
            Text(val,
                style: const TextStyle(
                    color: Voy.ink, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ],
    );
  }
}
