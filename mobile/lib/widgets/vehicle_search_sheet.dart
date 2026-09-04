import 'package:flutter/material.dart';
import '../models/vehicles_data.dart';
import '../services/vehicle_database_service.dart';

/// Modal bottom sheet for browsing, searching, and selecting vehicles
/// from the CarDekho / VoyPlan Centralized Vehicle Database.
class VehicleSearchSheet extends StatefulWidget {
  final VehicleModel? currentVehicle;
  final ValueChanged<VehicleModel> onVehicleSelected;

  const VehicleSearchSheet({
    super.key,
    this.currentVehicle,
    required this.onVehicleSelected,
  });

  static Future<VehicleModel?> show(BuildContext context, {VehicleModel? currentVehicle}) {
    return showModalBottomSheet<VehicleModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161A26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.88,
        child: VehicleSearchSheet(
          currentVehicle: currentVehicle,
          onVehicleSelected: (v) {
            Navigator.of(ctx).pop(v);
          },
        ),
      ),
    );
  }

  @override
  State<VehicleSearchSheet> createState() => _VehicleSearchSheetState();
}

class _VehicleSearchSheetState extends State<VehicleSearchSheet> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _customMileageController = TextEditingController();

  String _selectedFuelFilter = 'all'; // 'all', 'petrol', 'diesel', 'cng', 'ev', 'hybrid'
  String _selectedTypeFilter = 'all'; // 'all', 'car', 'motorcycle'
  String? _selectedBrandFilter;

  List<VehicleModel> _results = [];
  bool _loading = false;
  VehicleModel? _selectedVehicle;
  bool _useCustomMileage = false;

  @override
  void initState() {
    super.initState();
    _selectedVehicle = widget.currentVehicle;
    if (_selectedVehicle != null && _selectedVehicle!.isUserMileageOverride) {
      _useCustomMileage = true;
      _customMileageController.text = _selectedVehicle!.userCustomMileage?.toString() ?? '';
    }
    _performSearch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customMileageController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    setState(() => _loading = true);
    final q = _selectedBrandFilter != null && _selectedBrandFilter!.isNotEmpty
        ? '${_selectedBrandFilter!} ${_searchController.text}'.trim()
        : _searchController.text.trim();

    final list = await VehicleDatabaseService.instance.searchVehicles(
      q,
      fuelType: _selectedFuelFilter != 'all' ? _selectedFuelFilter : null,
      type: _selectedTypeFilter != 'all' ? _selectedTypeFilter : null,
      limit: 40,
    );

    if (mounted) {
      setState(() {
        _results = list;
        _loading = false;
      });
    }
  }

  void _onConfirmSelection() {
    if (_selectedVehicle == null) return;

    VehicleModel finalVehicle = _selectedVehicle!;
    if (_useCustomMileage) {
      final customVal = double.tryParse(_customMileageController.text);
      if (customVal != null && customVal > 0) {
        finalVehicle = finalVehicle.copyWith(
          isUserMileageOverride: true,
          userCustomMileage: customVal,
        );
      }
    } else {
      finalVehicle = finalVehicle.copyWith(
        isUserMileageOverride: false,
        userCustomMileage: null,
      );
    }

    widget.onVehicleSelected(finalVehicle);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.directions_car_filled_rounded, color: Color(0xFF60A5FA), size: 22),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vehicle Database',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Text(
                      'Search by Brand, Model, or Variant · CarDekho Catalog',
                      style: TextStyle(fontSize: 11.5, color: Colors.white60),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Search Bar
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1F2433),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                onChanged: (_) => _performSearch(),
                decoration: InputDecoration(
                  hintText: 'Search (e.g. Innova, XUV700, Safari, Swift, Thar, Creta...)',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF60A5FA), size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _performSearch();
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Fuel Filter Chips Bar
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('All Fuels', 'all', _selectedFuelFilter == 'all', (val) {
                    setState(() => _selectedFuelFilter = 'all');
                    _performSearch();
                  }),
                  const SizedBox(width: 6),
                  _filterChip('Petrol', 'petrol', _selectedFuelFilter == 'petrol', (val) {
                    setState(() => _selectedFuelFilter = 'petrol');
                    _performSearch();
                  }, color: const Color(0xFFF59E0B)),
                  const SizedBox(width: 6),
                  _filterChip('Diesel', 'diesel', _selectedFuelFilter == 'diesel', (val) {
                    setState(() => _selectedFuelFilter = 'diesel');
                    _performSearch();
                  }, color: const Color(0xFF10B981)),
                  const SizedBox(width: 6),
                  _filterChip('CNG', 'cng', _selectedFuelFilter == 'cng', (val) {
                    setState(() => _selectedFuelFilter = 'cng');
                    _performSearch();
                  }, color: const Color(0xFF06B6D4)),
                  const SizedBox(width: 6),
                  _filterChip('EV', 'ev', _selectedFuelFilter == 'ev', (val) {
                    setState(() => _selectedFuelFilter = 'ev');
                    _performSearch();
                  }, color: const Color(0xFF8B5CF6)),
                  const SizedBox(width: 6),
                  _filterChip('Hybrid', 'hybrid', _selectedFuelFilter == 'hybrid', (val) {
                    setState(() => _selectedFuelFilter = 'hybrid');
                    _performSearch();
                  }, color: const Color(0xFFEC4899)),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Quick Brand Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _brandChip('Tata', 'Tata'),
                  const SizedBox(width: 6),
                  _brandChip('Mahindra', 'Mahindra'),
                  const SizedBox(width: 6),
                  _brandChip('Toyota', 'Toyota'),
                  const SizedBox(width: 6),
                  _brandChip('Hyundai', 'Hyundai'),
                  const SizedBox(width: 6),
                  _brandChip('Maruti Suzuki', 'Maruti'),
                  const SizedBox(width: 6),
                  _brandChip('Kia', 'Kia'),
                  const SizedBox(width: 6),
                  _brandChip('Honda', 'Honda'),
                  const SizedBox(width: 6),
                  _brandChip('BMW', 'BMW'),
                  const SizedBox(width: 6),
                  _brandChip('Royal Enfield', 'Royal Enfield'),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Vehicle List View
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6)))
                  : _results.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.directions_car_outlined, size: 48, color: Colors.white.withOpacity(0.2)),
                              const SizedBox(height: 12),
                              Text('No matching vehicles found', style: TextStyle(color: Colors.white.withOpacity(0.6))),
                              const SizedBox(height: 6),
                              Text('Try adjusting your search terms or fuel filter',
                                  style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4))),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: _results.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (ctx, idx) {
                            final v = _results[idx];
                            final isSelected = _selectedVehicle?.id == v.id;
                            return _buildVehicleCard(v, isSelected);
                          },
                        ),
            ),

            // Bottom Selected Action Bar with User Mileage Override
            if (_selectedVehicle != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2433),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.4)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedVehicle!.fullDisplayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_selectedVehicle!.fuelType.toUpperCase()} · ${_selectedVehicle!.mileage.toStringAsFixed(1)} km/L · ${_selectedVehicle!.tankCapacity > 0 ? '${_selectedVehicle!.tankCapacity.toStringAsFixed(0)}L Tank' : '${_selectedVehicle!.evRangeKm ?? 400} km Range'}',
                                style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.6)),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _useCustomMileage,
                          activeColor: const Color(0xFF3B82F6),
                          onChanged: (val) {
                            setState(() {
                              _useCustomMileage = val;
                              if (val && _customMileageController.text.isEmpty) {
                                _customMileageController.text = _selectedVehicle!.mileage.toString();
                              }
                            });
                          },
                        ),
                      ],
                    ),
                    if (_useCustomMileage) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.edit_road_rounded, size: 16, color: Color(0xFF60A5FA)),
                          const SizedBox(width: 8),
                          const Text('Custom Mileage:', style: TextStyle(fontSize: 12, color: Colors.white70)),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 80,
                            height: 36,
                            child: TextField(
                              controller: _customMileageController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                suffixText: 'km/L',
                                suffixStyle: const TextStyle(fontSize: 10, color: Colors.white54),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                filled: true,
                                fillColor: Colors.black26,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        minimumSize: const Size.fromHeight(42),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _onConfirmSelection,
                      child: const Text('Confirm Vehicle Selection', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleCard(VehicleModel v, bool isSelected) {
    final fuelColor = _getFuelColor(v.fuelType);

    return InkWell(
      onTap: () {
        setState(() {
          _selectedVehicle = v;
          if (_useCustomMileage) {
            _customMileageController.text = v.mileage.toString();
          }
        });
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E293B) : const Color(0xFF161A26),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFF3B82F6) : Colors.white.withOpacity(0.07),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    v.fullDisplayName,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.white.withOpacity(0.95),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: fuelColor.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: fuelColor.withOpacity(0.4)),
                  ),
                  child: Text(
                    v.fuelType.toUpperCase(),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fuelColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (v.fuelType == 'ev') ...[
                  _specBadge(Icons.bolt, '${v.evRangeKm ?? 450} km Range', const Color(0xFF8B5CF6)),
                  const SizedBox(width: 8),
                  _specBadge(Icons.battery_charging_full, '${v.batteryCapacityKwh ?? 50} kWh', Colors.white60),
                ] else ...[
                  _specBadge(Icons.speed_rounded, '${v.mileage.toStringAsFixed(1)} km/L', const Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  _specBadge(Icons.local_gas_station_outlined, '${v.tankCapacity.toStringAsFixed(0)}L Tank', Colors.white60),
                ],
                if (v.seatingCapacity != null) ...[
                  const SizedBox(width: 8),
                  _specBadge(Icons.event_seat_outlined, '${v.seatingCapacity} Seats', Colors.white60),
                ],
                if (v.transmission != null) ...[
                  const SizedBox(width: 8),
                  _specBadge(Icons.tune_rounded, v.transmission!.contains('Auto') || v.transmission!.contains('AT') || v.transmission!.contains('DCT') ? 'AT' : 'MT', Colors.white60),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _specBadge(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _filterChip(String label, String value, bool isSelected, ValueChanged<bool> onSelected, {Color? color}) {
    final chipColor = color ?? const Color(0xFF3B82F6);
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.white : Colors.white70)),
      selected: isSelected,
      selectedColor: chipColor.withOpacity(0.3),
      backgroundColor: const Color(0xFF1F2433),
      side: BorderSide(color: isSelected ? chipColor : Colors.white10),
      onSelected: onSelected,
    );
  }

  Widget _brandChip(String label, String brandSearch) {
    final isSelected = _selectedBrandFilter == brandSearch;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedBrandFilter = isSelected ? null : brandSearch;
        });
        _performSearch();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3B82F6).withOpacity(0.2) : const Color(0xFF1F2433),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? const Color(0xFF3B82F6) : Colors.white.withOpacity(0.08)),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isSelected ? const Color(0xFF60A5FA) : Colors.white70),
        ),
      ),
    );
  }

  Color _getFuelColor(String fuel) {
    switch (fuel.toLowerCase()) {
      case 'diesel':
        return const Color(0xFF10B981);
      case 'petrol':
        return const Color(0xFFF59E0B);
      case 'cng':
        return const Color(0xFF06B6D4);
      case 'ev':
        return const Color(0xFF8B5CF6);
      case 'hybrid':
        return const Color(0xFFEC4899);
      default:
        return const Color(0xFF60A5FA);
    }
  }
}
