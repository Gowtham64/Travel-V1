import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/trip_models.dart';
import '../models/vehicles_data.dart';
import '../services/api_service.dart';
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

  final _efficiencyController = TextEditingController();
  final _tankController = TextEditingController();
  final _currentFuelController = TextEditingController(text: '30');

  VehicleModel? _selectedVehicle;
  final Set<String> _selectedPOIs = {'fuel', 'restaurant'};
  bool _loading = false;
  String? _error;
  
  final String _bgUrl = 'https://images.unsplash.com/photo-1518509562904-e7ef99cdcc86?q=80&w=2000&auto=format&fit=crop';

  @override
  void initState() {
    super.initState();
    _selectedVehicle = predefinedVehicles.firstWhere((v) => v.type == 'car');
    _updateVehicleFields();
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
          final point = await _api.geocode(address);
          geocodedStops.add(point);
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
          ),
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
          // Form Content
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: SingleChildScrollView(
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
                              ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                              : const Text('PLAN TRIP', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(User? user) {
    return Drawer(
      backgroundColor: const Color(0xFF1A1A1A),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF2E75B6)),
            accountName: const Text('Travel Planner', style: TextStyle(fontWeight: FontWeight.bold)),
            accountEmail: Text(user?.email ?? 'Not logged in'),
            currentAccountPicture: const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.person, size: 40, color: Color(0xFF2E75B6)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.map_outlined, color: Colors.white70),
            title: const Text('Saved Trips', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedTripsScreen()));
            },
          ),
          const Divider(color: Colors.white24),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.white70),
            title: const Text('Log out', style: TextStyle(color: Colors.white)),
            onTap: () async {
              await Supabase.instance.client.auth.signOut();
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildGlassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
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
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
        prefixIcon: Icon(icon, color: iconColor ?? Colors.white.withOpacity(0.7), size: 20),
        filled: true,
        fillColor: Colors.black.withOpacity(0.2),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.white),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent),
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
        ],
      ),
    );
  }
}
