import 'package:flutter/material.dart';
import '../models/trip_expense_models.dart';
import '../models/trip_models.dart';
import '../services/trip_expense_service.dart';

/// Modal dialog displaying the full 17-point Trip Expense Report upon trip completion.
class TripExpenseReportDialog extends StatelessWidget {
  final TripExpenseReport report;
  final VoidCallback? onClose;

  const TripExpenseReportDialog({
    super.key,
    required this.report,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sym = report.currencySymbol;
    final isOver = report.isOverBudget;
    final diff = report.difference.abs();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 780),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131927) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isOver ? Colors.orange.withOpacity(0.5) : const Color(0xFF10B981).withOpacity(0.5),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            _buildHeader(context),

            // Scrollable 17-Question Report Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Grand Summary Banner
                    _buildSummaryBanner(sym, isOver, diff),
                    const SizedBox(height: 16),

                    // Q1 - Q3: Route & Navigation Stop Summary
                    _buildSectionHeader(Icons.map_rounded, '1. Route & Confirmed Navigation Stops'),
                    _buildRouteSection(),
                    const SizedBox(height: 16),

                    // Q4: Grand Totals (Estimated vs Actual vs Variance)
                    _buildSectionHeader(Icons.account_balance_wallet_rounded, '2. Total Expense Comparison'),
                    _buildGrandTotalsCard(sym),
                    const SizedBox(height: 16),

                    // Q5 - Q8: Fuel Price, Litres & Refuel Stops
                    _buildSectionHeader(Icons.local_gas_station_rounded, '3. Fuel Analysis & Refuel Stops'),
                    _buildFuelSection(sym),
                    const SizedBox(height: 16),

                    // Q9 - Q10: Toll Calculation & Plazas
                    _buildSectionHeader(Icons.toll_rounded, '4. Toll Expenses & Plazas Encountered'),
                    _buildTollSection(sym),
                    const SizedBox(height: 16),

                    // Q11 - Q14: Meals & Break Expenses
                    _buildSectionHeader(Icons.restaurant_rounded, '5. Meals & Rest Break Expenses'),
                    _buildMealsSection(sym),
                    const SizedBox(height: 16),

                    // Q15: Other & Miscellaneous
                    _buildSectionHeader(Icons.more_horiz_rounded, '6. Parking & Miscellaneous'),
                    _buildOtherSection(sym),
                    const SizedBox(height: 16),

                    // Q16: Outbound vs Return (Round Trips)
                    if (report.isRoundTrip) ...[
                      _buildSectionHeader(Icons.swap_horiz_rounded, '7. Outbound vs Return Breakdown'),
                      _buildRoundTripBreakdown(sym),
                      const SizedBox(height: 16),
                    ],

                    // Q17: Final Assessment
                    _buildSectionHeader(Icons.insights_rounded, 'Final Assessment & Savings'),
                    _buildAssessmentCard(sym),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // Actions Footer
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Final Trip Expense Report',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${report.startAddress} → ${report.endAddress}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: () {
              Navigator.of(context).pop();
              onClose?.call();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBanner(String sym, bool isOver, double diff) {
    final bgColor = isOver ? const Color(0xFF7C2D12).withOpacity(0.35) : const Color(0xFF064E3B).withOpacity(0.35);
    final borderColor = isOver ? Colors.orange : const Color(0xFF10B981);
    final statusText = isOver
        ? 'Over Budget by $sym${diff.toStringAsFixed(0)}'
        : 'Under Budget • Saved $sym${diff.toStringAsFixed(0)}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Row(
        children: [
          Icon(
            isOver ? Icons.warning_amber_rounded : Icons.savings_rounded,
            color: borderColor,
            size: 32,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: TextStyle(
                    color: borderColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Estimated: $sym${report.totalEstimated.toStringAsFixed(0)}  |  Actual Spent: $sym${report.totalActual.toStringAsFixed(0)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF60A5FA)),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF93C5FD),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _infoTile('Total Distance', '${report.distanceKm.toStringAsFixed(1)} km'),
              _infoTile('Duration', '${report.durationMinutes ~/ 60}h ${report.durationMinutes % 60}m'),
              _infoTile('Trip Type', report.isRoundTrip ? 'Round / Around Trip' : 'One-way Trip'),
            ],
          ),
          const Divider(color: Colors.white12, height: 20),
          Row(
            children: [
              Icon(
                report.routedThroughAllStops ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                color: report.routedThroughAllStops ? const Color(0xFF10B981) : Colors.amber,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                report.routedThroughAllStops
                    ? 'All ${report.confirmedStops.length} confirmed waypoints completed'
                    : '${report.confirmedStops.length} confirmed stops routed',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          if (report.confirmedStops.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: report.confirmedStops.map((stop) => Chip(
                avatar: const Icon(Icons.check, size: 14, color: Color(0xFF10B981)),
                label: Text(stop, style: const TextStyle(color: Colors.white, fontSize: 11)),
                backgroundColor: const Color(0xFF0F172A),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGrandTotalsCard(String sym) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _expenseCol('Estimated Total', '$sym${report.totalEstimated.toStringAsFixed(0)}', Colors.white70),
              _expenseCol('Actual Total', '$sym${report.totalActual.toStringAsFixed(0)}', Colors.white, isBold: true),
              _expenseCol(
                'Difference',
                '${report.difference >= 0 ? "+" : "-"}$sym${report.difference.abs().toStringAsFixed(0)}',
                report.difference <= 0 ? const Color(0xFF10B981) : Colors.orangeAccent,
                isBold: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFuelSection(String sym) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _infoTile('Fuel Required', '${report.fuelRequiredLiters.toStringAsFixed(1)} L'),
              _infoTile('Actual Refueled', '${report.actualFuelPurchasedLiters.toStringAsFixed(1)} L'),
              _infoTile('Pump Price', report.fuelPricePerLiter > 0 ? '$sym${report.fuelPricePerLiter.toStringAsFixed(2)}/L' : 'Market rate'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _infoTile('Est. Fuel Cost', '$sym${report.estimatedFuelCost.toStringAsFixed(0)}'),
              _infoTile('Actual Fuel Cost', '$sym${report.actualFuelCost.toStringAsFixed(0)}'),
              _infoTile(
                'Fuel Variance',
                '${(report.actualFuelCost - report.estimatedFuelCost) >= 0 ? "+" : ""}$sym${(report.actualFuelCost - report.estimatedFuelCost).toStringAsFixed(0)}',
              ),
            ],
          ),
          if (report.fuelEntries.isNotEmpty) ...[
            const Divider(color: Colors.white12, height: 20),
            const Text(
              'Refueling Records:',
              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            ...report.fuelEntries.map((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '⛽ ${e.stationName ?? e.description} (${e.litres?.toStringAsFixed(1) ?? "0"} L @ $sym${e.pricePerLitre?.toStringAsFixed(1) ?? "0"}/L)',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  Text(
                    '$sym${e.actualAmount.toStringAsFixed(0)}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }

  Widget _buildTollSection(String sym) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _infoTile('Est. Toll Cost', '$sym${report.estimatedTollTotal.toStringAsFixed(0)}'),
              _infoTile('Actual Tolls Paid', '$sym${report.actualTollTotal.toStringAsFixed(0)}'),
              _infoTile('Plazas Count', '${report.tollEntries.length} Plazas'),
            ],
          ),
          if (report.tollEntries.isNotEmpty) ...[
            const Divider(color: Colors.white12, height: 20),
            const Text(
              'Encountered Toll Plazas:',
              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            ...report.tollEntries.map((t) {
              final paid = t.actualAmount > 0 ? t.actualAmount : t.estimatedAmount;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '🛣️ ${t.description} (${t.paymentMethod})',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                    Text(
                      '$sym${paid.toStringAsFixed(0)}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildMealsSection(String sym) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _mealRow('🥞 Breakfast', report.estimatedBreakfast, report.actualBreakfast, sym),
          const Divider(color: Colors.white12, height: 12),
          _mealRow('🍛 Lunch', report.estimatedLunch, report.actualLunch, sym),
          const Divider(color: Colors.white12, height: 12),
          _mealRow('☕ Tea & Snacks', report.estimatedTeaSnacks, report.actualTeaSnacks, sym),
          const Divider(color: Colors.white12, height: 12),
          _mealRow('🍲 Dinner', report.estimatedDinner, report.actualDinner, sym),
        ],
      ),
    );
  }

  Widget _mealRow(String label, double est, double act, String sym) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        Row(
          children: [
            Text('Est: $sym${est.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(width: 10),
            Text(
              'Act: $sym${act.toStringAsFixed(0)}',
              style: TextStyle(
                color: act > 0 ? Colors.white : Colors.white38,
                fontWeight: act > 0 ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOtherSection(String sym) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _mealRow('🅿️ Parking & Entry Tickets', report.estimatedParking + report.estimatedTickets, report.actualParking + report.actualTickets, sym),
          const Divider(color: Colors.white12, height: 12),
          _mealRow('📦 Miscellaneous & Buffer', report.estimatedOther, report.actualOther, sym),
        ],
      ),
    );
  }

  Widget _buildRoundTripBreakdown(String sym) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _expenseCol('Outbound Leg', '$sym${report.outboundActualTotal.toStringAsFixed(0)}', Colors.white, isBold: true),
          _expenseCol('Return Leg', '$sym${report.returnActualTotal.toStringAsFixed(0)}', Colors.white, isBold: true),
        ],
      ),
    );
  }

  Widget _buildAssessmentCard(String sym) {
    final isOver = report.isOverBudget;
    final diff = report.difference.abs();
    final advice = isOver
        ? 'Trip expenses exceeded estimated budget by $sym${diff.toStringAsFixed(0)}. Higher fuel/tolls or spontaneous meal stops were the primary contributors.'
        : 'Outstanding budget control! You completed the entire trip with $sym${diff.toStringAsFixed(0)} in savings compared to initial estimates.';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        advice,
        style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onClose?.call();
            },
            child: const Text('Close', style: TextStyle(color: Colors.white70)),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            icon: const Icon(Icons.done_all_rounded, size: 18),
            label: const Text('Done'),
            onPressed: () {
              Navigator.of(context).pop();
              onClose?.call();
            },
          ),
        ],
      ),
    );
  }

  Widget _infoTile(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _expenseCol(String title, String val, Color color, {bool isBold = false}) {
    return Column(
      children: [
        Text(title, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 4),
        Text(
          val,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Modal bottom sheet or dialog for live trip expense dashboard during navigation
class LiveExpenseDashboardSheet extends StatefulWidget {
  final VoidCallback? onExpenseAdded;

  const LiveExpenseDashboardSheet({super.key, this.onExpenseAdded});

  @override
  State<LiveExpenseDashboardSheet> createState() => _LiveExpenseDashboardSheetState();
}

class _LiveExpenseDashboardSheetState extends State<LiveExpenseDashboardSheet> {
  @override
  Widget build(BuildContext context) {
    final summaries = TripExpenseService.instance.getCategorySummaries();
    final grandEstimated = TripExpenseService.instance.getGrandTotalEstimated();
    final grandActual = TripExpenseService.instance.getGrandTotalActual();
    final diff = grandActual - grandEstimated;
    const sym = '₹';

    return Container(
      constraints: const BoxConstraints(maxHeight: 640),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: const BoxDecoration(
        color: Color(0xFF131927),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF60A5FA), size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Trip Expenses & Budget',
                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Grand Total Overview Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _stat('Estimated', '$sym${grandEstimated.toStringAsFixed(0)}', Colors.white70),
                _stat('Actual Spent', '$sym${grandActual.toStringAsFixed(0)}', Colors.white, isBold: true),
                _stat(
                  'Difference',
                  '${diff >= 0 ? "+" : "-"}$sym${diff.abs().toStringAsFixed(0)}',
                  diff <= 0 ? const Color(0xFF10B981) : Colors.orangeAccent,
                  isBold: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Categories Breakdown List
          Expanded(
            child: ListView(
              children: [
                ...summaries.values.map((summary) => _buildCategoryTile(summary)),
              ],
            ),
          ),

          const SizedBox(height: 14),
          // "+ Add Expense" Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add Actual Expense', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => _openAddExpenseDialog(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String val, Color color, {bool isBold = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 2),
        Text(
          val,
          style: TextStyle(color: color, fontSize: 15, fontWeight: isBold ? FontWeight.bold : FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildCategoryTile(CategoryExpenseSummary s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(s.categoryName, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
          Row(
            children: [
              Text('Est: ${s.currencySymbol}${s.estimated.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(width: 10),
              Text(
                'Act: ${s.currencySymbol}${s.actual.toStringAsFixed(0)}',
                style: TextStyle(
                  color: s.actual > 0 ? Colors.white : Colors.white38,
                  fontWeight: s.actual > 0 ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openAddExpenseDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AddExpenseDialog(
        onSaved: () {
          setState(() {});
          widget.onExpenseAdded?.call();
        },
      ),
    );
  }
}

/// Add Expense Dialog for fast logging during navigation
class AddExpenseDialog extends StatefulWidget {
  final VoidCallback? onSaved;
  final ExpenseCategory? initialCategory;
  final String? initialDescription;
  final double? initialAmount;

  const AddExpenseDialog({
    super.key,
    this.onSaved,
    this.initialCategory,
    this.initialDescription,
    this.initialAmount,
  });

  @override
  State<AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<AddExpenseDialog> {
  late ExpenseCategory _selectedCategory;
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _paymentMethod = 'UPI';

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory ?? ExpenseCategory.food;
    if (widget.initialDescription != null) _descCtrl.text = widget.initialDescription!;
    if (widget.initialAmount != null && widget.initialAmount! > 0) {
      _amountCtrl.text = widget.initialAmount!.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF131927),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Record Actual Expense',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),

              // Category dropdown
              DropdownButtonFormField<ExpenseCategory>(
                value: _selectedCategory,
                dropdownColor: const Color(0xFF1E293B),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: _fieldDec('Category'),
                items: ExpenseCategory.values.map((c) => DropdownMenuItem(
                  value: c,
                  child: Text(c.displayName),
                )).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedCategory = val);
                },
              ),
              const SizedBox(height: 12),

              // Description
              TextField(
                controller: _descCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: _fieldDec('Description / Place Name', hint: 'e.g. Hotel Saravana Bhavan'),
              ),
              const SizedBox(height: 12),

              // Amount
              TextField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                decoration: _fieldDec('Amount (₹)', hint: '0.00'),
              ),
              const SizedBox(height: 12),

              // Payment Method
              DropdownButtonFormField<String>(
                value: _paymentMethod,
                dropdownColor: const Color(0xFF1E293B),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: _fieldDec('Payment Method'),
                items: const [
                  DropdownMenuItem(value: 'UPI', child: Text('UPI / Google Pay / PhonePe')),
                  DropdownMenuItem(value: 'Card', child: Text('Credit / Debit Card')),
                  DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'FASTag', child: Text('FASTag')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _paymentMethod = val);
                },
              ),
              const SizedBox(height: 12),

              // Notes
              TextField(
                controller: _notesCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: _fieldDec('Notes (Optional)'),
              ),
              const SizedBox(height: 18),

              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _saveExpense,
                    child: const Text('Save Expense'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDec(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
      hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
      filled: true,
      fillColor: const Color(0xFF1E293B),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  void _saveExpense() {
    final amt = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
    if (amt <= 0) return;

    final item = TripExpenseItem(
      id: 'exp_${DateTime.now().millisecondsSinceEpoch}',
      tripId: TripExpenseService.instance.currentTripId,
      category: _selectedCategory,
      description: _descCtrl.text.trim().isNotEmpty ? _descCtrl.text.trim() : _selectedCategory.displayName,
      actualAmount: amt,
      paymentMethod: _paymentMethod,
      notes: _notesCtrl.text.trim(),
    );

    TripExpenseService.instance.addExpense(item);
    Navigator.of(context).pop();
    widget.onSaved?.call();
  }
}

/// Prompt dialog when vehicle arrives at a fuel stop
class QuickRefuelArrivalDialog extends StatefulWidget {
  final RefuelStop fuelStop;
  final double defaultPricePerLiter;
  final VoidCallback? onCompleted;

  const QuickRefuelArrivalDialog({
    super.key,
    required this.fuelStop,
    required this.defaultPricePerLiter,
    this.onCompleted,
  });

  @override
  State<QuickRefuelArrivalDialog> createState() => _QuickRefuelArrivalDialogState();
}

class _QuickRefuelArrivalDialogState extends State<QuickRefuelArrivalDialog> {
  final _litresCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _totalCtrl = TextEditingController();
  String _fuelType = 'Petrol';
  bool _autoCalc = true;

  @override
  void initState() {
    super.initState();
    final suggestedLitres = widget.fuelStop.refillLiters ?? 25.0;
    _litresCtrl.text = suggestedLitres.toStringAsFixed(1);
    final price = widget.defaultPricePerLiter > 0 ? widget.defaultPricePerLiter : 102.50;
    _priceCtrl.text = price.toStringAsFixed(2);
    _updateTotal();

    _litresCtrl.addListener(_onFieldChanged);
    _priceCtrl.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (_autoCalc) _updateTotal();
  }

  void _updateTotal() {
    final l = double.tryParse(_litresCtrl.text) ?? 0.0;
    final p = double.tryParse(_priceCtrl.text) ?? 0.0;
    _totalCtrl.text = (l * p).toStringAsFixed(0);
  }

  @override
  void dispose() {
    _litresCtrl.dispose();
    _priceCtrl.dispose();
    _totalCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF131927),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.local_gas_station_rounded, color: Colors.orange, size: 24),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Arrived at Fuel Stop',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        widget.fuelStop.name,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _litresCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: _dec('Litres'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: _dec('Price/L (₹)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _totalCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Color(0xFF10B981), fontSize: 16, fontWeight: FontWeight.bold),
              decoration: _dec('Total Amount (₹)'),
              onChanged: (_) => _autoCalc = false,
            ),
            const SizedBox(height: 18),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Skip', style: TextStyle(color: Colors.white54)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _saveRefuel,
                  child: const Text('Record Refuel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _dec(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
      filled: true,
      fillColor: const Color(0xFF1E293B),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  void _saveRefuel() {
    final l = double.tryParse(_litresCtrl.text) ?? 0.0;
    final p = double.tryParse(_priceCtrl.text) ?? 0.0;
    final total = double.tryParse(_totalCtrl.text) ?? (l * p);

    TripExpenseService.instance.recordRefuel(
      stationName: widget.fuelStop.name,
      location: widget.fuelStop.name,
      fuelType: _fuelType,
      litres: l,
      pricePerLitre: p,
      manualTotalAmount: total,
    );

    Navigator.of(context).pop();
    widget.onCompleted?.call();
  }
}
