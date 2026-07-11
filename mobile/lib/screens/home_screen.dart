import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/trip_models.dart';
import '../models/vehicles_data.dart';
import '../services/api_service.dart';
import 'trip_screen.dart';
import 'saved_trips_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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

  @override
  void initState() {
    super.initState();
    // Default to first car
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
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Travel Planner', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        foregroundColor: Theme.of(context).colorScheme.primary,
        elevation: 0,
      ),
      drawer: _buildDrawer(user),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildRouteCard(),
              const SizedBox(height: 16),
              _buildVehicleCard(),
              const SizedBox(height: 16),
              _buildPOICard(),
              const SizedBox(height: 24),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Text(_error!, style: TextStyle(color: Colors.red[800])),
                  ),
                ),
              ElevatedButton(
                onPressed: _loading ? null : _planTrip,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                child: _loading
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                    : const Text('PLAN TRIP', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer(User? user) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
            accountName: const Text('Travel Planner', style: TextStyle(fontWeight: FontWeight.bold)),
            accountEmail: Text(user?.email ?? 'Not logged in'),
            currentAccountPicture: const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.person, size: 40, color: Colors.grey),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.map_outlined),
            title: const Text('Saved Trips'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedTripsScreen()));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Log out'),
            onTap: () async {
              await Supabase.instance.client.auth.signOut();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRouteCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.route, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Text('Your Route', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 16),
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
                Color iconColor = isStart ? Colors.green : (isEnd ? Colors.red : Colors.orange);

                return Container(
                  key: ValueKey(_stopControllers[index]),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.drag_indicator, color: Colors.grey),
                      const SizedBox(width: 8),
                      Icon(icon, color: iconColor, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _stopControllers[index],
                          decoration: InputDecoration(
                            labelText: label,
                            filled: true,
                            fillColor: Colors.grey[50],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                        ),
                      ),
                      if (!isStart && !isEnd)
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
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
              child: TextButton.icon(
                onPressed: _addStop,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Add Stop'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.directions_car, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Text('Vehicle Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<VehicleModel>(
              value: _selectedVehicle,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Select Vehicle',
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                prefixIcon: const Icon(Icons.commute),
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
                  child: TextFormField(
                    controller: _efficiencyController,
                    decoration: InputDecoration(
                      labelText: 'Efficiency (km/l)',
                      filled: true,
                      fillColor: Colors.grey[50],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      prefixIcon: const Icon(Icons.speed, size: 20),
                    ),
                    keyboardType: TextInputType.number,
                    validator: _numberValidator,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _tankController,
                    decoration: InputDecoration(
                      labelText: 'Tank (L)',
                      filled: true,
                      fillColor: Colors.grey[50],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      prefixIcon: const Icon(Icons.local_gas_station, size: 20),
                    ),
                    keyboardType: TextInputType.number,
                    validator: _numberValidator,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _currentFuelController,
              decoration: InputDecoration(
                labelText: 'Current fuel in tank (L)',
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                prefixIcon: const Icon(Icons.water_drop, size: 20),
              ),
              keyboardType: TextInputType.number,
              validator: _numberValidator,
            ),
          ],
        ),
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
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.place, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Text('Places to Visit Along Route', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: _poiOptions.map((option) {
                final isSelected = _selectedPOIs.contains(option['id']);
                return FilterChip(
                  label: Text(option['label']),
                  avatar: Icon(option['icon'], size: 16, color: isSelected ? Colors.white : Theme.of(context).colorScheme.primary),
                  selected: isSelected,
                  selectedColor: Theme.of(context).colorScheme.primary,
                  labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87),
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
      ),
    );
  }
}
