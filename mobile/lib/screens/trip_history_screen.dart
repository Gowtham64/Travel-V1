import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/trip_history_service.dart';
import '../widgets/app_design.dart';
import 'trip_planner_screen.dart';

class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  int _selectedFilterIndex = 0; // 0: All, 1: One-Way, 2: Round Trip
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    TripHistoryService.instance.getHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<TripHistoryItem> _filterTrips(List<TripHistoryItem> items) {
    return items.where((trip) {
      if (_selectedFilterIndex == 1 && trip.isRoundTrip) return false;
      if (_selectedFilterIndex == 2 && !trip.isRoundTrip) return false;
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchStart = trip.startAddress.toLowerCase().contains(q);
        final matchEnd = trip.endAddress.toLowerCase().contains(q);
        final matchTitle = trip.title.toLowerCase().contains(q);
        final matchWaypoints = trip.waypoints.any((w) => w.toLowerCase().contains(q));
        if (!matchStart && !matchEnd && !matchTitle && !matchWaypoints) return false;
      }
      return true;
    }).toList();
  }

  String _formatDate(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final day = dt.day;
    final month = months[dt.month - 1];
    final year = dt.year;
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$day $month $year · $hour:$minute';
  }

  String _formatDuration(int min) {
    if (min < 60) return '$min min';
    final h = min ~/ 60;
    final m = min % 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  IconData _vehicleIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('bike') || t.contains('motorcycle') || t.contains('scooter') || t.contains('two_wheeler')) {
      return Icons.two_wheeler_rounded;
    } else if (t.contains('bus')) {
      return Icons.directions_bus_rounded;
    } else if (t.contains('truck')) {
      return Icons.local_shipping_rounded;
    } else if (t.contains('suv')) {
      return Icons.directions_car_filled_rounded;
    }
    return Icons.directions_car_rounded;
  }

  void _showTripDetails(TripHistoryItem trip) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TripDetailsModal(
        trip: trip,
        onReplan: () {
          Navigator.pop(ctx);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TripPlannerScreen(
                initialStart: trip.startAddress,
                initialEnd: trip.endAddress,
                initialTripType: trip.isRoundTrip ? 'roundtrip' : 'oneway',
              ),
            ),
          );
        },
      ),
    );
  }

  void _shareTrip(TripHistoryItem trip) {
    final typeStr = trip.isRoundTrip ? 'Round Trip 🔄' : 'One-Way Trip ➔';
    final text = '🚗 Voyplan Trip Summary:\n'
        '• Route: ${trip.startAddress} → ${trip.endAddress}\n'
        '• Type: $typeStr\n'
        '• Vehicle: ${trip.vehicleType.toUpperCase()}\n'
        '• Distance: ${trip.distanceKm.toStringAsFixed(1)} km\n'
        '• Duration: ${_formatDuration(trip.durationMinutes)}\n'
        '• Tolls (FASTag): ₹${trip.tollCost.toStringAsFixed(0)}\n'
        '• Fuel Cost: ₹${trip.fuelCost.toStringAsFixed(0)}\n'
        '• Total Cost: ₹${trip.totalCost.toStringAsFixed(0)}\n'
        '• Completed: ${_formatDate(trip.completedAt)}\n\n'
        'Planned & navigated with Voyplan!';
    Share.share(text);
  }

  Future<void> _confirmDelete(TripHistoryItem trip) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Delete Trip History', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to remove the trip from "${trip.startAddress}" to "${trip.endAddress}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await TripHistoryService.instance.deleteTrip(trip.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trip deleted from history'),
            backgroundColor: Color(0xFF334155),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Trip History',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white60),
            tooltip: 'Clear All History',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E293B),
                  title: const Text('Clear All Trips', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  content: const Text(
                    'Do you want to permanently clear all completed trip histories?',
                    style: TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Clear All', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await TripHistoryService.instance.clearHistory();
              }
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<List<TripHistoryItem>>(
        valueListenable: TripHistoryService.instance.historyNotifier,
        builder: (context, allTrips, _) {
          final filteredTrips = _filterTrips(allTrips);
          final totalDistance = allTrips.fold<double>(0.0, (acc, t) => acc + t.distanceKm);
          final totalCost = allTrips.fold<double>(0.0, (acc, t) => acc + t.totalCost);

          return Column(
            children: [
              // Summary Stats Dashboard
              if (allTrips.isNotEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    children: [
                      _StatColumn(
                        label: 'Trips',
                        value: '${allTrips.length}',
                        icon: Icons.route_rounded,
                        color: const Color(0xFF38BDF8),
                      ),
                      _VerticalDivider(),
                      _StatColumn(
                        label: 'Total Driven',
                        value: '${totalDistance.toStringAsFixed(0)} km',
                        icon: Icons.speed_rounded,
                        color: const Color(0xFF10B981),
                      ),
                      _VerticalDivider(),
                      _StatColumn(
                        label: 'Total Expense',
                        value: '₹${totalCost.toStringAsFixed(0)}',
                        icon: Icons.account_balance_wallet_rounded,
                        color: const Color(0xFFF59E0B),
                      ),
                    ],
                  ),
                ),

              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search city, stops or routes…',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: Colors.white38, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF38BDF8)),
                    ),
                  ),
                ),
              ),

              // Filter Chips Row
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'All Trips (${allTrips.length})',
                      selected: _selectedFilterIndex == 0,
                      onTap: () => setState(() => _selectedFilterIndex = 0),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'One-Way Trips (${allTrips.where((t) => !t.isRoundTrip).length})',
                      selected: _selectedFilterIndex == 1,
                      onTap: () => setState(() => _selectedFilterIndex = 1),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Round Trips 🔄 (${allTrips.where((t) => t.isRoundTrip).length})',
                      selected: _selectedFilterIndex == 2,
                      onTap: () => setState(() => _selectedFilterIndex = 2),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 6),

              // Trips List or Empty State
              Expanded(
                child: filteredTrips.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                              ),
                              child: const Icon(Icons.history_rounded, size: 48, color: Colors.white24),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'No trips match "$_searchQuery"'
                                  : (_selectedFilterIndex == 2 ? 'No completed round trips yet' : 'No completed trips yet'),
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Trips you navigate or complete will automatically appear here.',
                              style: TextStyle(color: Colors.white54, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              ),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const TripPlannerScreen()),
                              ),
                              icon: const Icon(Icons.add_location_alt_rounded, color: Colors.white, size: 18),
                              label: const Text('Plan a New Trip', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: filteredTrips.length,
                        itemBuilder: (context, index) {
                          final trip = filteredTrips[index];
                          return _TripCard(
                            trip: trip,
                            dateStr: _formatDate(trip.completedAt),
                            durationStr: _formatDuration(trip.durationMinutes),
                            vehicleIcon: _vehicleIcon(trip.vehicleType),
                            onTap: () => _showTripDetails(trip),
                            onShare: () => _shareTrip(trip),
                            onDelete: () => _confirmDelete(trip),
                            onReplan: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => TripPlannerScreen(
                                    initialStart: trip.startAddress,
                                    initialEnd: trip.endAddress,
                                    initialTripType: trip.isRoundTrip ? 'roundtrip' : 'oneway',
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatColumn({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      color: Colors.white.withValues(alpha: 0.1),
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF10B981) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF10B981) : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final TripHistoryItem trip;
  final String dateStr;
  final String durationStr;
  final IconData vehicleIcon;
  final VoidCallback onTap;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback onReplan;

  const _TripCard({
    required this.trip,
    required this.dateStr,
    required this.durationStr,
    required this.vehicleIcon,
    required this.onTap,
    required this.onShare,
    required this.onDelete,
    required this.onReplan,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Card Top Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(vehicleIcon, size: 16, color: const Color(0xFF38BDF8)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    dateStr,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const Spacer(),
                  if (trip.isRoundTrip)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sync_rounded, size: 11, color: Color(0xFF60A5FA)),
                          SizedBox(width: 3),
                          Text('Round Trip', style: TextStyle(color: Color(0xFF60A5FA), fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                      ),
                      child: const Text('One-Way', style: TextStyle(color: Color(0xFF34D399), fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Route Origin & Destination Visual
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      const Icon(Icons.circle, size: 10, color: Color(0xFF10B981)),
                      Container(
                        width: 2,
                        height: trip.waypoints.isNotEmpty ? 36 : 24,
                        color: Colors.white24,
                        margin: const EdgeInsets.symmetric(vertical: 2),
                      ),
                      const Icon(Icons.location_on_rounded, size: 14, color: Colors.redAccent),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trip.startAddress,
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (trip.waypoints.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Via ${trip.waypoints.join(', ')}',
                            style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          trip.endAddress,
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Stats Row
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _MiniStat(label: 'Distance', value: '${trip.distanceKm.toStringAsFixed(1)} km'),
                    _MiniStat(label: 'Duration', value: durationStr),
                    _MiniStat(label: 'Tolls', value: '₹${trip.tollCost.toStringAsFixed(0)}'),
                    _MiniStat(label: 'Total', value: '₹${trip.totalCost.toStringAsFixed(0)}', highlight: true),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Card Actions Row
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.share_outlined, size: 18, color: Colors.white60),
                    tooltip: 'Share Trip',
                    onPressed: onShare,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.white38),
                    tooltip: 'Delete',
                    onPressed: onDelete,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF38BDF8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    onPressed: onTap,
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: const Text('Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 4),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: onReplan,
                    icon: const Icon(Icons.replay_rounded, size: 15),
                    label: const Text('Re-plan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _MiniStat({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: highlight ? const Color(0xFF10B981) : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _TripDetailsModal extends StatelessWidget {
  final TripHistoryItem trip;
  final VoidCallback onReplan;

  const _TripDetailsModal({
    required this.trip,
    required this.onReplan,
  });

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trip.isRoundTrip ? '🔄 Round Trip Details' : '➔ One-Way Trip Details',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Completed on ${_formatDate(trip.completedAt)}',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white12, height: 20),

          // Scrollable Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              children: [
                // Route Visual Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ROUTE ITINERARY', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      const SizedBox(height: 12),
                      _RouteStep(
                        icon: Icons.circle,
                        iconColor: const Color(0xFF10B981),
                        title: 'Starting Point',
                        subtitle: trip.startAddress,
                        isLast: trip.waypoints.isEmpty,
                      ),
                      for (int i = 0; i < trip.waypoints.length; i++)
                        _RouteStep(
                          icon: Icons.stop_circle_rounded,
                          iconColor: const Color(0xFFF59E0B),
                          title: 'Stop ${i + 1}',
                          subtitle: trip.waypoints[i],
                          isLast: i == trip.waypoints.length - 1,
                        ),
                      _RouteStep(
                        icon: Icons.location_on_rounded,
                        iconColor: Colors.redAccent,
                        title: 'Final Destination',
                        subtitle: trip.endAddress,
                        isLast: true,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Cost & Expense Breakdown
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('EXPENSE & TRAVEL BREAKDOWN', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      const SizedBox(height: 12),
                      _CostRow(label: 'Total Distance', value: '${trip.distanceKm.toStringAsFixed(1)} km', icon: Icons.straighten_rounded),
                      _CostRow(label: 'Estimated Fuel Cost', value: '₹${trip.fuelCost.toStringAsFixed(0)}', icon: Icons.local_gas_station_rounded),
                      _CostRow(label: 'FASTag / Toll Fees', value: '₹${trip.tollCost.toStringAsFixed(0)}', icon: Icons.toll_rounded),
                      _CostRow(label: 'Vehicle Used', value: trip.vehicleType.toUpperCase(), icon: Icons.directions_car_rounded),
                      const Divider(color: Colors.white12, height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total Estimated Cost', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                          Text('₹${trip.totalCost.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFF10B981), fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),

          // Bottom Action Button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: onReplan,
                icon: const Icon(Icons.navigation_rounded, color: Colors.white),
                label: const Text('Re-plan This Trip ➔', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteStep extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isLast;

  const _RouteStep({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Icon(icon, size: 16, color: iconColor),
            if (!isLast)
              Container(
                width: 2,
                height: 28,
                color: Colors.white24,
                margin: const EdgeInsets.symmetric(vertical: 2),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }
}

class _CostRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _CostRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white54),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const Spacer(),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
