import 'package:flutter/material.dart';
import '../models/vehicles_data.dart';
import '../services/vehicle_database_service.dart';
import 'vehicle_image.dart';

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

  static Future<VehicleModel?> show(BuildContext context,
      {VehicleModel? currentVehicle}) {
    FocusManager.instance.primaryFocus?.unfocus();
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
            FocusManager.instance.primaryFocus?.unfocus();
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
  final TextEditingController _customMileageController =
      TextEditingController();

  String _selectedCategory = 'all'; // 'all', 'car', 'motorcycle', 'ev'
  String _selectedFuelFilter =
      'all'; // 'all', 'petrol', 'diesel', 'cng', 'ev', 'hybrid'
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
    if (_selectedVehicle != null) {
      if (_selectedVehicle!.type == 'motorcycle') {
        _selectedCategory = 'motorcycle';
        _selectedTypeFilter = 'motorcycle';
      } else if (_selectedVehicle!.fuelType == 'ev') {
        _selectedCategory = 'ev';
        _selectedFuelFilter = 'ev';
      } else {
        _selectedCategory = 'car';
        _selectedTypeFilter = 'car';
      }

      if (_selectedVehicle!.isUserMileageOverride) {
        _useCustomMileage = true;
        _customMileageController.text =
            _selectedVehicle!.userCustomMileage?.toString() ?? '';
      }
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
      limit: 50,
    );

    if (mounted) {
      setState(() {
        _results = list;
        _loading = false;
      });
    }
  }

  void _onSelectCategory(String cat) {
    setState(() {
      _selectedCategory = cat;
      _selectedBrandFilter = null;
      if (cat == 'motorcycle') {
        _selectedTypeFilter = 'motorcycle';
        if (_selectedFuelFilter == 'diesel') _selectedFuelFilter = 'all';
      } else if (cat == 'car') {
        _selectedTypeFilter = 'car';
      } else if (cat == 'ev') {
        _selectedTypeFilter = 'all';
        _selectedFuelFilter = 'ev';
      } else {
        _selectedTypeFilter = 'all';
        _selectedFuelFilter = 'all';
      }
    });
    _performSearch();
  }

  void _onConfirmSelection() {
    FocusManager.instance.primaryFocus?.unfocus();
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

  void _showAddCustomVehicleDialog() {
    FocusManager.instance.primaryFocus?.unfocus();
    final nameCtrl = TextEditingController();
    final mileageCtrl = TextEditingController(
        text: _selectedTypeFilter == 'motorcycle' ? '35.0' : '15.0');
    final tankCtrl = TextEditingController(
        text: _selectedTypeFilter == 'motorcycle' ? '13.0' : '45.0');
    String customType =
        _selectedTypeFilter == 'motorcycle' ? 'motorcycle' : 'car';
    String customFuel = 'petrol';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E2433),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Colors.white12)),
            title: Row(
              children: [
                Icon(
                  customType == 'motorcycle'
                      ? Icons.two_wheeler_rounded
                      : Icons.directions_car_rounded,
                  color: const Color(0xFF38BDF8),
                  size: 24,
                ),
                const SizedBox(width: 10),
                const Text('Custom Vehicle / Bike',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Vehicle Type',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          avatar:
                              const Icon(Icons.two_wheeler_rounded, size: 16),
                          label: const Text('Bike / Scooter'),
                          selected: customType == 'motorcycle',
                          selectedColor:
                              const Color(0xFFF59E0B).withOpacity(0.3),
                          onSelected: (v) {
                            if (v) {
                              setDlgState(() {
                                customType = 'motorcycle';
                                if (mileageCtrl.text == '15.0')
                                  mileageCtrl.text = '35.0';
                                if (tankCtrl.text == '45.0')
                                  tankCtrl.text = '13.0';
                                if (customFuel == 'diesel')
                                  customFuel = 'petrol';
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          avatar: const Icon(Icons.directions_car_rounded,
                              size: 16),
                          label: const Text('Car / SUV'),
                          selected: customType == 'car',
                          selectedColor:
                              const Color(0xFF3B82F6).withOpacity(0.3),
                          onSelected: (v) {
                            if (v) {
                              setDlgState(() {
                                customType = 'car';
                                if (mileageCtrl.text == '35.0')
                                  mileageCtrl.text = '15.0';
                                if (tankCtrl.text == '13.0')
                                  tankCtrl.text = '45.0';
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('Vehicle Name or Model',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: customType == 'motorcycle'
                          ? 'e.g. Royal Enfield Continental GT'
                          : 'e.g. Mahindra Thar 4x4',
                      hintStyle:
                          const TextStyle(color: Colors.white38, fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF161A26),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Fuel Type',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      _dialogFuelChip('Petrol', 'petrol', customFuel,
                          (f) => setDlgState(() => customFuel = f)),
                      if (customType == 'car')
                        _dialogFuelChip('Diesel', 'diesel', customFuel,
                            (f) => setDlgState(() => customFuel = f)),
                      _dialogFuelChip('CNG', 'cng', customFuel,
                          (f) => setDlgState(() => customFuel = f)),
                      _dialogFuelChip('EV', 'ev', customFuel,
                          (f) => setDlgState(() => customFuel = f)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                customFuel == 'ev'
                                    ? 'Range (km)'
                                    : 'Mileage (km/L)',
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: mileageCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: const Color(0xFF161A26),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                customFuel == 'ev'
                                    ? 'Battery (kWh)'
                                    : 'Tank Size (L)',
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: tankCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: const Color(0xFF161A26),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  final name = nameCtrl.text.trim().isNotEmpty
                      ? nameCtrl.text.trim()
                      : (customType == 'motorcycle'
                          ? 'Custom Motorcycle'
                          : 'Custom Car');
                  final mileage = double.tryParse(mileageCtrl.text) ??
                      (customType == 'motorcycle' ? 35.0 : 15.0);
                  final tank = double.tryParse(tankCtrl.text) ??
                      (customType == 'motorcycle' ? 13.0 : 45.0);

                  final customVehicle = VehicleModel(
                    id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                    name: name,
                    type: customType,
                    fuelType: customFuel,
                    mileage: mileage,
                    tankCapacity: customFuel == 'ev' ? 0.0 : tank,
                    batteryCapacityKwh: customFuel == 'ev' ? tank : null,
                    evRangeKm: customFuel == 'ev' ? mileage.round() : null,
                    seatingCapacity: customType == 'motorcycle' ? 2 : 5,
                    bodyType: customType == 'motorcycle'
                        ? 'Custom Bike'
                        : 'Custom Vehicle',
                    isUserMileageOverride: true,
                    userCustomMileage: mileage,
                    source: 'User Custom',
                  );

                  Navigator.of(ctx).pop();
                  setState(() {
                    _results.insert(0, customVehicle);
                    _selectedVehicle = customVehicle;
                    _useCustomMileage = true;
                    _customMileageController.text = mileage.toString();
                  });
                },
                child: const Text('Select Vehicle',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _dialogFuelChip(String label, String value, String current,
      ValueChanged<String> onSelected) {
    final isSelected = current == value;
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
              fontSize: 11, color: isSelected ? Colors.white : Colors.white70)),
      selected: isSelected,
      selectedColor: const Color(0xFF3B82F6).withOpacity(0.3),
      onSelected: (_) => onSelected(value),
    );
  }

  List<String> _getBrandList() {
    if (_selectedTypeFilter == 'motorcycle') {
      return const [
        'Royal Enfield',
        'KTM',
        'Yamaha',
        'Honda',
        'Bajaj',
        'TVS',
        'Hero',
        'Triumph',
        'BMW',
        'Harley-Davidson',
        'Ather',
        'Ola',
        'Suzuki',
        'Kawasaki',
      ];
    } else if (_selectedTypeFilter == 'car') {
      return const [
        'Tata',
        'Mahindra',
        'Toyota',
        'Hyundai',
        'Maruti Suzuki',
        'Kia',
        'Honda',
        'BMW',
        'Mercedes',
        'Skoda',
        'Volkswagen',
        'MG',
      ];
    }
    return const [
      'Tata',
      'Mahindra',
      'Toyota',
      'Royal Enfield',
      'Hyundai',
      'KTM',
      'Yamaha',
      'Maruti Suzuki',
      'Honda',
      'Bajaj',
      'TVS',
      'Hero',
    ];
  }

  String _getSearchHint() {
    if (_selectedTypeFilter == 'motorcycle') {
      return 'Search bikes & scooters (e.g. Classic 350, Himalayan, Duke, R15, Activa...)';
    } else if (_selectedTypeFilter == 'car') {
      return 'Search cars (e.g. Innova, XUV700, Safari, Swift, Thar, Creta...)';
    } else if (_selectedFuelFilter == 'ev') {
      return 'Search electric vehicles (e.g. Nexon EV, Ola S1, Ather 450X, Ioniq 5...)';
    }
    return 'Search any vehicle (e.g. Innova, Classic 350, Himalayan, Swift, Duke...)';
  }

  IconData _getHeaderIcon() {
    if (_selectedTypeFilter == 'motorcycle') return Icons.two_wheeler_rounded;
    if (_selectedFuelFilter == 'ev') return Icons.bolt_rounded;
    return Icons.directions_car_filled_rounded;
  }

  Color _getHeaderColor() {
    if (_selectedTypeFilter == 'motorcycle') return const Color(0xFFF59E0B);
    if (_selectedFuelFilter == 'ev') return const Color(0xFF8B5CF6);
    return const Color(0xFF60A5FA);
  }

  @override
  Widget build(BuildContext context) {
    final brandList = _getBrandList();

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
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
              const SizedBox(height: 12),

              // Header Bar
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _getHeaderColor().withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_getHeaderIcon(),
                        color: _getHeaderColor(), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Vehicle Database',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _selectedTypeFilter == 'motorcycle'
                              ? 'Motorcycles, Cruisers & Scooters · Full Catalog'
                              : 'Cars, SUVs & Two-Wheelers · CarDekho Catalog',
                          style: const TextStyle(
                              fontSize: 11.5, color: Colors.white60),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // "+ Custom" button
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      backgroundColor: Colors.white.withOpacity(0.06),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.add_rounded,
                        color: Color(0xFF38BDF8), size: 16),
                    label: const Text('Custom',
                        style: TextStyle(
                            color: Color(0xFF38BDF8),
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                    onPressed: _showAddCustomVehicleDialog,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── PRIMARY CATEGORY SELECTOR ──────────────────────────────────
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2433),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  children: [
                    _categorySegment('All', 'all', Icons.apps_rounded),
                    _categorySegment(
                        'Cars', 'car', Icons.directions_car_rounded),
                    _categorySegment('Bikes & Scooters', 'motorcycle',
                        Icons.two_wheeler_rounded),
                    _categorySegment('Electric', 'ev', Icons.bolt_rounded),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Search Bar
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2433),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) {
                    FocusManager.instance.primaryFocus?.unfocus();
                    _performSearch();
                  },
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  onChanged: (_) => _performSearch(),
                  decoration: InputDecoration(
                    hintText: _getSearchHint(),
                    hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.4), fontSize: 13),
                    prefixIcon:
                        Icon(Icons.search, color: _getHeaderColor(), size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                color: Colors.white54, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _performSearch();
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Fuel Filter Chips Bar
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip(
                        'All Fuels', 'all', _selectedFuelFilter == 'all',
                        (val) {
                      setState(() => _selectedFuelFilter = 'all');
                      _performSearch();
                    }),
                    const SizedBox(width: 6),
                    _filterChip(
                        'Petrol', 'petrol', _selectedFuelFilter == 'petrol',
                        (val) {
                      setState(() => _selectedFuelFilter = 'petrol');
                      _performSearch();
                    }, color: const Color(0xFFF59E0B)),
                    if (_selectedTypeFilter != 'motorcycle') ...[
                      const SizedBox(width: 6),
                      _filterChip(
                          'Diesel', 'diesel', _selectedFuelFilter == 'diesel',
                          (val) {
                        setState(() => _selectedFuelFilter = 'diesel');
                        _performSearch();
                      }, color: const Color(0xFF10B981)),
                    ],
                    const SizedBox(width: 6),
                    _filterChip('CNG', 'cng', _selectedFuelFilter == 'cng',
                        (val) {
                      setState(() => _selectedFuelFilter = 'cng');
                      _performSearch();
                    }, color: const Color(0xFF06B6D4)),
                    const SizedBox(width: 6),
                    _filterChip('EV', 'ev', _selectedFuelFilter == 'ev', (val) {
                      setState(() => _selectedFuelFilter = 'ev');
                      _performSearch();
                    }, color: const Color(0xFF8B5CF6)),
                    if (_selectedTypeFilter != 'motorcycle') ...[
                      const SizedBox(width: 6),
                      _filterChip(
                          'Hybrid', 'hybrid', _selectedFuelFilter == 'hybrid',
                          (val) {
                        setState(() => _selectedFuelFilter = 'hybrid');
                        _performSearch();
                      }, color: const Color(0xFFEC4899)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Dynamic Brand Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (int i = 0; i < brandList.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      _brandChip(brandList[i], brandList[i]),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Vehicle List View
              Expanded(
                child: _loading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: Color(0xFF3B82F6)))
                    : _results.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _selectedTypeFilter == 'motorcycle'
                                      ? Icons.two_wheeler_outlined
                                      : Icons.directions_car_outlined,
                                  size: 48,
                                  color: Colors.white.withOpacity(0.2),
                                ),
                                const SizedBox(height: 12),
                                Text('No matching vehicles found',
                                    style: TextStyle(
                                        color: Colors.white.withOpacity(0.6))),
                                const SizedBox(height: 6),
                                Text(
                                  'Try adjusting your search terms or use "+ Custom" above',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white.withOpacity(0.4)),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: _results.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (ctx, idx) {
                              final v = _results[idx];
                              final isSelected = _selectedVehicle?.id == v.id;
                              return _buildVehicleCard(v, isSelected);
                            },
                          ),
              ),

              // Bottom Selected Action Bar with User Mileage Override
              if (_selectedVehicle != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2433),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: const Color(0xFF3B82F6).withOpacity(0.5),
                        width: 1.5),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: (_selectedVehicle!.type == 'motorcycle'
                                      ? const Color(0xFFF59E0B)
                                      : const Color(0xFF3B82F6))
                                  .withOpacity(0.18),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _selectedVehicle!.type == 'motorcycle'
                                  ? Icons.two_wheeler_rounded
                                  : Icons.directions_car_rounded,
                              size: 18,
                              color: _selectedVehicle!.type == 'motorcycle'
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFF60A5FA),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedVehicle!.fullDisplayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_selectedVehicle!.fuelType.toUpperCase()} · ${_selectedVehicle!.mileage.toStringAsFixed(1)} km/L · ${_selectedVehicle!.tankCapacity > 0 ? '${_selectedVehicle!.tankCapacity.toStringAsFixed(0)}L Tank' : '${_selectedVehicle!.evRangeKm ?? 400} km Range'}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white.withOpacity(0.7)),
                                ),
                              ],
                            ),
                          ),
                          Tooltip(
                            message: 'Custom Mileage Override',
                            child: Switch(
                              value: _useCustomMileage,
                              activeColor: const Color(0xFF3B82F6),
                              onChanged: (val) {
                                setState(() {
                                  _useCustomMileage = val;
                                  if (val &&
                                      _customMileageController.text.isEmpty) {
                                    _customMileageController.text =
                                        _selectedVehicle!.mileage.toString();
                                  }
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      if (_useCustomMileage) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.edit_road_rounded,
                                size: 16, color: Color(0xFF60A5FA)),
                            const SizedBox(width: 8),
                            const Text('Custom Mileage:',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.white70)),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 90,
                              height: 36,
                              child: TextField(
                                controller: _customMileageController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => FocusManager
                                    .instance.primaryFocus
                                    ?.unfocus(),
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                                decoration: InputDecoration(
                                  suffixText: 'km/L',
                                  suffixStyle: const TextStyle(
                                      fontSize: 10, color: Colors.white54),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  filled: true,
                                  fillColor: Colors.black26,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8)),
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
                          foregroundColor: Colors.white,
                          elevation: 2,
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _onConfirmSelection,
                        child: const Text('Confirm Vehicle Selection',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _categorySegment(String label, String value, IconData icon) {
    final isSelected = _selectedCategory == value;
    return Expanded(
      child: InkWell(
        onTap: () => _onSelectCategory(value),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF3B82F6) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 17,
                color: isSelected ? Colors.white : Colors.white60,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.white : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVehicleCard(VehicleModel v, bool isSelected) {
    final fuelColor = _getFuelColor(v.fuelType);
    final isBike = v.type == 'motorcycle';

    return InkWell(
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
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
            color: isSelected
                ? const Color(0xFF3B82F6)
                : Colors.white.withOpacity(0.07),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Vehicle image from the Vahan Details catalog, with an icon
            // fallback for custom/offline records.
            Container(
              width: 78,
              height: 54,
              margin: const EdgeInsets.only(top: 2, right: 10),
              decoration: BoxDecoration(
                color: isBike
                    ? const Color(0xFFF59E0B).withOpacity(0.12)
                    : (v.fuelType == 'ev'
                        ? const Color(0xFF8B5CF6).withOpacity(0.12)
                        : const Color(0xFF3B82F6).withOpacity(0.12)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: VehicleImage(
                vehicle: v,
                fallback: Icon(
                  isBike
                      ? Icons.two_wheeler_rounded
                      : (v.fuelType == 'ev'
                          ? Icons.bolt_rounded
                          : Icons.directions_car_rounded),
                  size: 28,
                  color: isBike
                      ? const Color(0xFFF59E0B)
                      : (v.fuelType == 'ev'
                          ? const Color(0xFFA78BFA)
                          : const Color(0xFF60A5FA)),
                ),
              ),
            ),
            // Details
            Expanded(
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
                            color: isSelected
                                ? Colors.white
                                : Colors.white.withOpacity(0.95),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: fuelColor.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: fuelColor.withOpacity(0.4)),
                        ),
                        child: Text(
                          v.fuelType.toUpperCase(),
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: fuelColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (v.fuelType == 'ev') ...[
                        _specBadge(Icons.bolt, '${v.evRangeKm ?? 150} km Range',
                            const Color(0xFF8B5CF6)),
                        if (v.batteryCapacityKwh != null)
                          _specBadge(Icons.battery_charging_full,
                              '${v.batteryCapacityKwh} kWh', Colors.white60),
                      ] else ...[
                        _specBadge(
                            Icons.speed_rounded,
                            '${v.mileage.toStringAsFixed(1)} km/L',
                            const Color(0xFF10B981)),
                        _specBadge(
                            Icons.local_gas_station_outlined,
                            '${v.tankCapacity.toStringAsFixed(0)}L Tank',
                            Colors.white60),
                      ],
                      if (v.seatingCapacity != null)
                        _specBadge(Icons.event_seat_outlined,
                            '${v.seatingCapacity} Seats', Colors.white60),
                      if (v.transmission != null)
                        _specBadge(
                          Icons.tune_rounded,
                          v.transmission!.contains('Auto') ||
                                  v.transmission!.contains('AT') ||
                                  v.transmission!.contains('CVT')
                              ? 'AT'
                              : 'MT',
                          Colors.white60,
                        ),
                    ],
                  ),
                ],
              ),
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
        Text(text,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _filterChip(String label, String value, bool isSelected,
      ValueChanged<bool> onSelected,
      {Color? color}) {
    final chipColor = color ?? const Color(0xFF3B82F6);
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.white : Colors.white70)),
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
          color: isSelected
              ? const Color(0xFF3B82F6).withOpacity(0.25)
              : const Color(0xFF1F2433),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isSelected
                  ? const Color(0xFF3B82F6)
                  : Colors.white.withOpacity(0.08)),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isSelected ? const Color(0xFF60A5FA) : Colors.white70),
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
