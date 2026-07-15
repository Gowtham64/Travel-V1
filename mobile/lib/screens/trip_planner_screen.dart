import 'dart:io' show Platform;
import 'dart:math';
import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/trip_models.dart';
import '../models/vehicles_data.dart';
import '../services/api_service.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'trip_screen.dart';
import 'saved_trips_screen.dart';

class TripPlannerScreen extends StatefulWidget {
  const TripPlannerScreen({super.key});

  @override
  State<TripPlannerScreen> createState() => _TripPlannerScreenState();
}

class _TripPlannerScreenState extends State<TripPlannerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _api = ApiService();

  final List<TextEditingController> _stopControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  // Pre-resolved coordinates for stops added from POI list (keyed by controller hashCode)
  final Map<int, GeoPoint> _resolvedStopCoords = {};

  final _efficiencyController = TextEditingController();
  final _tankController = TextEditingController();
  final _currentFuelController = TextEditingController(text: '30');

  VehicleModel? _selectedVehicle;
  final Set<String> _selectedPOIs = {'fuel', 'restaurant'};
  List<String> _appliedPOIs = ['fuel', 'restaurant'];
  bool _loading = false;
  String? _error;
  
  TripPlan? _currentPlan;
  GeoPoint? _currentStart;
  GeoPoint? _currentEnd;
  List<GeoPoint>? _currentWaypoints;
  Vehicle? _currentVehicle;
  
  Map<String, List<PlaceOfInterest>> _pois = {};
  bool _loadingPOIs = false;
  bool _hasSearchedPOIs = false;
  String? _userName;
  final Map<String, String> _resolvedAddresses = {};
  final Set<String> _requestedAddresses = {};

  final ScrollController _formScrollController = ScrollController();
  
  final String _bgUrl = 'https://images.unsplash.com/photo-1518509562904-e7ef99cdcc86?q=80&w=2000&auto=format&fit=crop';

  @override
  void initState() {
    super.initState();
    _selectedVehicle = predefinedVehicles.firstWhere((v) => v.type == 'car');
    _updateVehicleFields();
    _recordUserSession();
  }

  String _getDeviceAccessInfo() {
    if (kIsWeb) return 'Web Browser';
    try {
      if (Platform.isAndroid) return 'Android Device';
      if (Platform.isIOS) return 'iOS Device';
      if (Platform.isMacOS) return 'macOS App';
      if (Platform.isWindows) return 'Windows App';
      if (Platform.isLinux) return 'Linux App';
      return 'Mobile App';
    } catch (_) {
      return 'Unknown Device';
    }
  }

  Future<void> _recordUserSession() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      // Check if user_details already exists for this user
      final response = await Supabase.instance.client
          .from('user_details')
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (response == null) {
        final name = user.userMetadata?['full_name'] ?? user.userMetadata?['name'] ?? 'Traveler';
        final email = user.email ?? '';
        final phone = user.phone ?? '';
        final deviceAccess = _getDeviceAccessInfo();
        
        await Supabase.instance.client.from('user_details').insert({
          'user_id': user.id,
          'name': name,
          'phone': phone,
          'email': email,
          'password_hash': 'OAuth / Google',
          'location': 'Not Provided',
          'device_access': deviceAccess,
        });
      }
    } catch (e) {
      debugPrint('Failed to record user details: $e');
    }
  }

  void _updateVehicleFields() {
    if (_selectedVehicle != null) {
      _efficiencyController.text = _selectedVehicle!.mileage.toString();
      _tankController.text = _selectedVehicle!.tankCapacity.toString();
    }
  }

  Future<void> _planTrip() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedVehicle == null) {
      setState(() => _error = 'Please select a vehicle');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final List<GeoPoint> geocodedStops = [];
      for (final controller in _stopControllers) {
        final address = controller.text.trim();
        if (address.isNotEmpty) {
          // Use pre-resolved coordinates if available (from POI selection)
          final resolved = _resolvedStopCoords[controller.hashCode];
          if (resolved != null) {
            geocodedStops.add(resolved);
          } else {
            final point = await _api.geocode(address);
            geocodedStops.add(point);
            _resolvedStopCoords[controller.hashCode] = point; // Cache it!
          }
        }
      }

      if (geocodedStops.length < 2) {
        throw Exception("Need at least a starting point and destination");
      }

      final start = geocodedStops.first;
      final end = geocodedStops.last;
      final waypoints = geocodedStops.sublist(1, geocodedStops.length - 1);

      final vehicle = Vehicle(
        type: _selectedVehicle!.type,
        efficiencyKmPerLiter: double.parse(_efficiencyController.text),
        tankCapacityLiters: double.parse(_tankController.text),
        currentFuelLiters: double.parse(_currentFuelController.text),
      );

      final plan = await _api.planTrip(
        start: start,
        end: end,
        waypoints: waypoints,
        vehicle: vehicle,
      );

      if (!mounted) return;

      if (MediaQuery.of(context).size.width > 900) {
        setState(() {
          _currentPlan = plan;
          _appliedPOIs = _selectedPOIs.toList();
          _currentStart = start;
          _currentEnd = end;
          _currentWaypoints = waypoints;
          _currentVehicle = vehicle;
        });
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TripScreen(
              plan: plan,
              startAddress: _stopControllers.first.text.trim(),
              endAddress: _stopControllers.last.text.trim(),
              vehicleType: _selectedVehicle!.type,
              poiCategories: _selectedPOIs.toList(),
              start: start,
              end: end,
              waypoints: waypoints,
              vehicle: vehicle,
              initialPois: _pois.isNotEmpty ? _pois : null,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }



  Future<void> _findPlacesBeforeTrip() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedVehicle == null) {
      setState(() => _error = 'Please select a vehicle');
      return;
    }

    setState(() {
      _loadingPOIs = true;
      _error = null;
    });

    try {
      final List<GeoPoint> geocodedStops = [];
      for (final controller in _stopControllers) {
        final address = controller.text.trim();
        if (address.isNotEmpty) {
          final resolved = _resolvedStopCoords[controller.hashCode];
          if (resolved != null) {
            geocodedStops.add(resolved);
          } else {
            final point = await _api.geocode(address);
            geocodedStops.add(point);
            _resolvedStopCoords[controller.hashCode] = point; // Cache it!
          }
        }
      }

      if (geocodedStops.length < 2) {
        throw Exception("Need at least a starting point and destination");
      }

      final start = geocodedStops.first;
      final end = geocodedStops.last;
      final waypoints = geocodedStops.sublist(1, geocodedStops.length - 1);

      final vehicle = Vehicle(
        type: _selectedVehicle!.type,
        efficiencyKmPerLiter: double.parse(_efficiencyController.text),
        tankCapacityLiters: double.parse(_tankController.text),
        currentFuelLiters: double.parse(_currentFuelController.text),
      );

      final tempPlan = await _api.planTrip(
        start: start,
        end: end,
        waypoints: waypoints,
        vehicle: vehicle,
      );

      final fetchedPois = await _api.fetchPOIs(
        routeCoordinates: tempPlan.coordinates,
        categories: _selectedPOIs.toList(),
      );

      if (mounted) {
        setState(() {
          _pois = fetchedPois;
          _appliedPOIs = _selectedPOIs.toList();
          _hasSearchedPOIs = true;
          _currentPlan = tempPlan;
          _currentStart = start;
          _currentEnd = end;
          _currentWaypoints = waypoints;
          _currentVehicle = vehicle;
          _loadingPOIs = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to find places: $e';
          _loadingPOIs = false;
        });
      }
    }
  }

  void _confirmAddPOIFromPlanner(PlaceOfInterest place) {
    final newWaypoint = GeoPoint(lat: place.lat, lng: place.lng);

    // Get the currently resolved coordinates in order of the active controllers
    final List<GeoPoint> resolvedNodes = [];
    final List<TextEditingController> activeControllers = [];
    for (final controller in _stopControllers) {
      final coord = _resolvedStopCoords[controller.hashCode];
      if (coord != null && controller.text.trim().isNotEmpty) {
        resolvedNodes.add(coord);
        activeControllers.add(controller);
      }
    }

    if (resolvedNodes.length >= 2) {
      // Find the best insertion index among the resolved nodes
      int bestIndex = 0;
      double minDetour = double.infinity;

      double _dist(GeoPoint p1, GeoPoint p2) {
        final dx = p1.lng - p2.lng;
        final dy = p1.lat - p2.lat;
        return sqrt(dx * dx + dy * dy);
      }

      for (int i = 0; i < resolvedNodes.length - 1; i++) {
        final p1 = resolvedNodes[i];
        final p2 = resolvedNodes[i + 1];
        final detour = _dist(p1, newWaypoint) + _dist(newWaypoint, p2) - _dist(p1, p2);
        if (detour < minDetour) {
          minDetour = detour;
          bestIndex = i;
        }
      }

      // Insert the new controller right after the controller corresponding to resolvedNodes[bestIndex]
      final targetController = activeControllers[bestIndex];
      final insertIndex = _stopControllers.indexOf(targetController) + 1;

      setState(() {
        final newController = TextEditingController(text: place.name);
        _resolvedStopCoords[newController.hashCode] = newWaypoint;
        _stopControllers.insert(insertIndex, newController);
      });

      // Offset the scroll position by 76.0 (approx height of a stop input) so the POI card doesn't jump
      Future.delayed(const Duration(milliseconds: 50), () {
        if (_formScrollController.hasClients) {
          _formScrollController.animateTo(
            _formScrollController.offset + 76.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      });
    } else {
      setState(() {
        final newController = TextEditingController(text: place.name);
        _resolvedStopCoords[newController.hashCode] = newWaypoint;
        _stopControllers.insert(_stopControllers.length - 1, newController);
      });
    }

    // Show confirmation without triggering a form rebuild that causes scroll jump
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✓ Added "${place.name}" as a stop'),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF2E75B6),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _addStop() {
    setState(() {
      _stopControllers.insert(_stopControllers.length - 1, TextEditingController());
    });
  }

  void _removeStop(int index) {
    if (_stopControllers.length <= 2) return;
    setState(() {
      final controller = _stopControllers.removeAt(index);
      _resolvedStopCoords.remove(controller.hashCode);
      controller.dispose();
    });
  }

  @override
  void dispose() {
    for (var c in _stopControllers) {
      c.dispose();
    }
    _efficiencyController.dispose();
    _tankController.dispose();
    _currentFuelController.dispose();
    _formScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Trip Planner', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      drawer: _buildDrawer(user),
      body: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: Image.network(
              _bgUrl,
              fit: BoxFit.cover,
            ),
          ),
          // Dark Overlay
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.5),
            ),
          ),
          // Content Layout
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 900) {
                return Row(
                  children: [
                    SizedBox(
                      width: 450,
                      child: SafeArea(child: _buildForm()),
                    ),
                    Expanded(
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 24.0, bottom: 24.0, right: 24.0),
                          child: _buildGlassCard(
                            padding: EdgeInsets.zero,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: _currentPlan == null ? _buildDefaultMap() : _buildTripScreen(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              } else {
                return SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: _buildForm(),
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      controller: _formScrollController,
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildRouteCard(),
            const SizedBox(height: 24),
            _buildVehicleCard(),
            const SizedBox(height: 24),
            _buildPOICard(),
            const SizedBox(height: 32),
            
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red[300]!),
                  ),
                  child: Text(_error!, style: const TextStyle(color: Colors.white)),
                ),
              ),
              
            ElevatedButton(
              onPressed: _loading ? null : _planTrip,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E75B6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 8,
                shadowColor: const Color(0xFF2E75B6).withOpacity(0.5),
              ),
              child: _loading
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('DONE', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultMap() {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Trip Map', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.black.withOpacity(0.4),
        elevation: 0,
      ),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: const LatLng(20.5937, 78.9629), // Center of India
          initialZoom: 4.5,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/tiles/{z}/{x}/{y}?access_token=pk.eyJ1IjoiZ293dGhhbWVjNjQiLCJhIjoiY21yZzhnOG82MGh2dTJ6c2FuM3h6ZXdkayJ9.PmiHwk5A4-eSWu7zLYkSXQ',
            userAgentPackageName: 'com.example.travel_app',
            additionalOptions: const {
              'accessToken': 'pk.eyJ1IjoiZ293dGhhbWVjNjQiLCJhIjoiY21yZzhnOG82MGh2dTJ6c2FuM3h6ZXdkayJ9.PmiHwk5A4-eSWu7zLYkSXQ',
            },
          ),
          RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
        ],
      ),
    );
  }

  Widget _buildTripScreen() {
    return TripScreen(
      plan: _currentPlan!,
      startAddress: _stopControllers.first.text.trim(),
      endAddress: _stopControllers.last.text.trim(),
      vehicleType: _selectedVehicle!.type,
      poiCategories: _appliedPOIs,
      start: _currentStart!,
      end: _currentEnd!,
      waypoints: _currentWaypoints!,
      vehicle: _currentVehicle!,
      initialPois: _pois.isNotEmpty ? _pois : null,
    );
  }

  Widget _buildDrawer(User? user) {
    final initials = (_userName != null && _userName!.isNotEmpty) 
        ? _userName!.substring(0, 1).toUpperCase() 
        : (user?.email != null && user!.email!.isNotEmpty)
            ? user.email!.substring(0, 1).toUpperCase()
            : 'T';

    return Drawer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1E293B), // Slate Dark
              Color(0xFF0F172A), // Deep Obsidian
            ],
          ),
        ),
        child: Column(
          children: [
            // Custom Premium Header
            Container(
              padding: const EdgeInsets.only(top: 80, bottom: 32, left: 24, right: 24),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
              ),
              child: Row(
                children: [
                  // Circular Avatar with outer gradient ring
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF2E75B6), Color(0xFF60A5FA)],
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 32,
                      backgroundColor: const Color(0xFF0F172A),
                      child: Text(
                        initials,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _userName ?? 'Traveler',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user?.email ?? 'Not logged in',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Drawer Options
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.white.withOpacity(0.03),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      leading: const Icon(Icons.map_outlined, color: Color(0xFF60A5FA), size: 24),
                      title: const Text(
                        'Saved Trips',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: Colors.white30, size: 20),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedTripsScreen()));
                      },
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // Log Out Button at Bottom
            Padding(
              padding: const EdgeInsets.all(24),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
                  color: Colors.redAccent.withOpacity(0.05),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  leading: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 22),
                  title: const Text(
                    'Log out',
                    style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  onTap: () async {
                    await Supabase.instance.client.auth.signOut();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildGlassCard({required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(24.0)}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.08),
                Colors.white.withOpacity(0.02),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    Color? iconColor,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14),
        floatingLabelStyle: const TextStyle(color: Color(0xFF2E75B6), fontWeight: FontWeight.bold),
        prefixIcon: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Icon(icon, color: iconColor ?? Colors.white.withOpacity(0.6), size: 22),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 40),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF2E75B6), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 2),
        ),
      ),
    );
  }

  Widget _buildRouteCard() {
    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.route, color: Colors.white),
              SizedBox(width: 12),
              Text('Your Route', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 24),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _stopControllers.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex -= 1;
                final item = _stopControllers.removeAt(oldIndex);
                _stopControllers.insert(newIndex, item);
              });
            },
            itemBuilder: (context, index) {
              final isStart = index == 0;
              final isEnd = index == _stopControllers.length - 1;
              String label = isStart ? 'Starting point' : (isEnd ? 'Destination' : 'Stop ${index}');
              IconData icon = isStart ? Icons.trip_origin : (isEnd ? Icons.location_on : Icons.adjust);
              Color iconColor = isStart ? Colors.greenAccent : (isEnd ? Colors.redAccent : Colors.orangeAccent);

              return Container(
                key: ValueKey(_stopControllers[index]),
                margin: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    Icon(Icons.drag_indicator, color: Colors.white.withOpacity(0.5)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildTextField(
                        controller: _stopControllers[index],
                        label: label,
                        icon: icon,
                        iconColor: iconColor,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                    if (!isStart && !isEnd)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                        onPressed: () => _removeStop(index),
                      )
                    else
                      const SizedBox(width: 48), // Padding equivalent to icon button
                  ],
                ),
              );
            },
          ),
          Center(
            child: OutlinedButton.icon(
              onPressed: _addStop,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Add Stop'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withOpacity(0.5)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleCard() {
    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.directions_car, color: Colors.white),
              SizedBox(width: 12),
              Text('Vehicle Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField<VehicleModel>(
            value: _selectedVehicle,
            isExpanded: true,
            dropdownColor: const Color(0xFF1A1A1A),
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              labelText: 'Select Vehicle',
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
              filled: true,
              fillColor: Colors.black.withOpacity(0.2),
              prefixIcon: Icon(Icons.commute, color: Colors.white.withOpacity(0.7)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withOpacity(0.2))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.white)),
            ),
            items: predefinedVehicles.map((v) {
              return DropdownMenuItem(
                value: v,
                child: Text(v.name),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedVehicle = value;
                _updateVehicleFields();
              });
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _efficiencyController,
                  label: 'Efficiency (km/l)',
                  icon: Icons.speed,
                  keyboardType: TextInputType.number,
                  validator: _numberValidator,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildTextField(
                  controller: _tankController,
                  label: 'Tank (L)',
                  icon: Icons.local_gas_station,
                  keyboardType: TextInputType.number,
                  validator: _numberValidator,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _currentFuelController,
            label: 'Current fuel in tank (L)',
            icon: Icons.water_drop,
            keyboardType: TextInputType.number,
            validator: _numberValidator,
          ),
        ],
      ),
    );
  }

  String? _numberValidator(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final n = double.tryParse(v);
    if (n == null || n <= 0) return 'Enter a valid number';
    return null;
  }

  final List<Map<String, dynamic>> _poiOptions = [
    {'id': 'fuel', 'label': 'Fuel Stations', 'icon': Icons.local_gas_station},
    {'id': 'hotel', 'label': 'Hotels', 'icon': Icons.hotel},
    {'id': 'restaurant', 'label': 'Restaurants', 'icon': Icons.restaurant},
    {'id': 'attraction', 'label': 'Attractions', 'icon': Icons.photo_camera},
    {'id': 'hills', 'label': 'Hills', 'icon': Icons.landscape},
    {'id': 'temple', 'label': 'Temples', 'icon': Icons.account_balance},
    {'id': 'lake', 'label': 'Lakes', 'icon': Icons.water},
    {'id': 'river', 'label': 'Rivers', 'icon': Icons.waves},
    {'id': 'viewpoint', 'label': 'Viewpoints', 'icon': Icons.visibility},
  ];

  Widget _buildPOICard() {
    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.place, color: Colors.white),
              SizedBox(width: 12),
              Text('Places to Visit', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12.0,
            runSpacing: 12.0,
            children: _poiOptions.map((option) {
              final isSelected = _selectedPOIs.contains(option['id']);
              return FilterChip(
                label: Text(option['label']),
                avatar: Icon(option['icon'], size: 18, color: isSelected ? Colors.white : Colors.white70),
                selected: isSelected,
                selectedColor: const Color(0xFF2E75B6),
                checkmarkColor: Colors.white,
                backgroundColor: Colors.black.withOpacity(0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: isSelected ? const Color(0xFF2E75B6) : Colors.white.withOpacity(0.2)),
                ),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedPOIs.add(option['id']);
                    } else {
                      _selectedPOIs.remove(option['id']);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Center(
            child: ElevatedButton.icon(
              onPressed: _loadingPOIs ? null : _findPlacesBeforeTrip,
              icon: _loadingPOIs 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.search),
              label: Text(_loadingPOIs ? 'Searching...' : 'Find Places'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E75B6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          if (_hasSearchedPOIs) ...[
            const SizedBox(height: 24),
            if (_loadingPOIs && _pois.isEmpty)
              const Center(child: CircularProgressIndicator())
            else if (_pois.isNotEmpty)
              Stack(
                alignment: Alignment.center,
                children: [
                  _buildPOIList(),
                  if (_loadingPOIs)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withOpacity(0.5),
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              )
            else
              const Center(child: Text("No places found.", style: TextStyle(color: Colors.white70))),
          ],
        ],
      ),
    );
  }

  Widget _buildPOIList() {
    final allPois = <MapEntry<String, PlaceOfInterest>>[];
    _pois.forEach((category, places) {
      for (final p in places) {
        allPois.add(MapEntry(category, p));
      }
    });

    if (allPois.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: ListView.builder(
        key: const PageStorageKey('poi_list_scroll_key'),
        shrinkWrap: true,
        padding: const EdgeInsets.all(8),
        itemCount: allPois.length,
        itemBuilder: (context, index) {
          final poi = allPois[index];
          final category = poi.key;
          final place = poi.value;
          final option = _poiOptions.firstWhere((o) => o['id'] == category, orElse: () => _poiOptions.first);

          return ListTile(
            leading: Icon(option['icon'], color: Colors.white70),
            title: Text(place.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
            subtitle: Builder(
              builder: (context) {
                final poiKey = '${place.lat},${place.lng}';
                final displayAddress = _resolvedAddresses[poiKey] ?? place.address ?? category.toUpperCase();
                
                final isCoordinateFallback = place.address == null || place.address!.contains('°') || place.address!.contains('N,') || place.address!.contains('S,');
                if (isCoordinateFallback && !_resolvedAddresses.containsKey(poiKey) && !_requestedAddresses.contains(poiKey)) {
                  _requestedAddresses.add(poiKey);
                  _api.reverseGeocode(place.lat, place.lng).then((addr) {
                    if (addr != null && mounted) {
                      setState(() {
                        _resolvedAddresses[poiKey] = addr;
                      });
                    }
                  });
                }

                return Text(
                  displayAddress,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                );
              },
            ),
            trailing: IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Color(0xFF2E75B6)),
              onPressed: () => _confirmAddPOIFromPlanner(place),
            ),
          );
        },
      ),
    );
  }
}
