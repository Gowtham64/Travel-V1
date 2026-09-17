import 'package:flutter/material.dart';

/// Interactive Smart AI Planner Card that exactly matches the Lovable reference & landing page:
/// - Dual-mode pill selector: "Describe it" & "Quick wizard"
/// - Multi-line prompt input with one-tap suggestion chips
/// - Quick wizard with Origin, Destination, Days (1-7), and Travel Style
/// - Live highway calibration badge
/// - Glowing "Build my road trip ->" action button
class SmartAiPlannerCard extends StatefulWidget {
  final void Function({
    required String start,
    required String dest,
    required int days,
    required String vibe,
  }) onBuild;

  const SmartAiPlannerCard({
    super.key,
    required this.onBuild,
  });

  @override
  State<SmartAiPlannerCard> createState() => _SmartAiPlannerCardState();
}

class _SmartAiPlannerCardState extends State<SmartAiPlannerCard> {
  int _tabIndex = 0; // 0: Describe it, 1: Quick wizard

  // "Describe it" controllers
  final _promptCtrl = TextEditingController();

  // "Quick wizard" controllers
  final _startCtrl = TextEditingController(text: 'Bangalore');
  final _destCtrl = TextEditingController(text: 'Coorg');
  int _wizardDays = 3;
  String _wizardStyle = 'Scenic';

  static const List<(String, String)> _suggestionChips = [
    ('🏍️ Weekend bike ride Chennai → Pondi', 'Weekend bike ride Chennai to Pondicherry for 2 days scenic coastal route'),
    ('⛰️ 5-day Delhi → Manali', '5-day Delhi to Manali mountain road trip with scenic viewpoints and adventure stops'),
    ('☕ 3-day Bangalore → Coorg', '3-day scenic drive from Bangalore to Coorg for foodies with coffee plantation stops'),
    ('🏖️ 4-day coastal Mumbai → Goa', '4-day coastal Mumbai to Goa road trip with beachside seafood shacks and relaxed vibe'),
  ];

  static const List<int> _dayOptions = [1, 2, 3, 4, 5, 7];
  static const List<String> _styleOptions = ['Scenic', 'Foodie', 'Adventure', 'Heritage', 'Relaxed'];

  @override
  void dispose() {
    _promptCtrl.dispose();
    _startCtrl.dispose();
    _destCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_tabIndex == 0) {
      final text = _promptCtrl.text.trim();
      final parsed = _parsePrompt(text.isNotEmpty ? text : '3-day scenic drive from Bangalore to Coorg');
      widget.onBuild(
        start: parsed.$1,
        dest: parsed.$2,
        days: parsed.$3,
        vibe: parsed.$4,
      );
    } else {
      final start = _startCtrl.text.trim().isNotEmpty ? _startCtrl.text.trim() : 'Bangalore';
      final dest = _destCtrl.text.trim().isNotEmpty ? _destCtrl.text.trim() : 'Coorg';
      widget.onBuild(
        start: start,
        dest: dest,
        days: _wizardDays,
        vibe: _wizardStyle,
      );
    }
  }

  (String, String, int, String) _parsePrompt(String raw) {
    String text = raw.toLowerCase();
    String start = 'Bangalore';
    String dest = 'Coorg';
    int days = 3;
    String vibe = 'Scenic';

    // Extract days (e.g. "3-day", "5 days", "weekend")
    final dayMatch = RegExp(r'(\d+)\s*[- ]*day').firstMatch(text);
    if (dayMatch != null) {
      days = int.tryParse(dayMatch.group(1)!) ?? 3;
    } else if (text.contains('weekend')) {
      days = 2;
    }

    // Extract route: "from X to Y" or "X to Y" or "X -> Y" or "X → Y"
    final fromToMatch = RegExp(r'(?:from\s+)?([a-zA-Z\s]+?)\s*(?:to|->|→)\s*([a-zA-Z\s]+?)(?:(?:\s+under|\s+for|\s+with|\s+in|\s+trip|\s+road|\s+drive|$))').firstMatch(text);
    if (fromToMatch != null) {
      final s = fromToMatch.group(1)?.trim();
      final d = fromToMatch.group(2)?.trim();
      if (s != null && s.isNotEmpty) start = _capitalize(s.replaceAll(RegExp(r'\b(drive|ride|trip|scenic)\b'), '').trim());
      if (d != null && d.isNotEmpty) dest = _capitalize(d.replaceAll(RegExp(r'\b(drive|ride|trip|scenic)\b'), '').trim());
    } else {
      // Known popular destinations
      if (text.contains('pondi')) {
        start = 'Chennai';
        dest = 'Pondicherry';
      } else if (text.contains('manali')) {
        start = 'Delhi';
        dest = 'Manali';
      } else if (text.contains('goa')) {
        start = 'Mumbai';
        dest = 'Goa';
      } else if (text.contains('coorg')) {
        start = 'Bangalore';
        dest = 'Coorg';
      } else if (text.contains('ooty')) {
        start = 'Bangalore';
        dest = 'Ooty';
      }
    }

    // Extract travel style / vibe
    if (text.contains('food')) {
      vibe = 'Foodie';
    } else if (text.contains('adventure') || text.contains('trek') || text.contains('hike')) {
      vibe = 'Adventure';
    } else if (text.contains('heritage') || text.contains('culture') || text.contains('temple')) {
      vibe = 'Heritage';
    } else if (text.contains('relax') || text.contains('leisure')) {
      vibe = 'Relaxed';
    } else {
      vibe = 'Scenic';
    }

    return (start.isNotEmpty ? start : 'Bangalore', dest.isNotEmpty ? dest : 'Coorg', days.clamp(1, 14), vibe);
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s.split(' ').map((w) => w.isNotEmpty ? (w[0].toUpperCase() + w.substring(1)) : '').join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C1319),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF1E2E3B),
          width: 1.2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 28,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top pill tab selector: [💬 Describe it]  [⭐ Quick wizard]
          Row(
            children: [
              _tabPill(
                index: 0,
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Describe it',
              ),
              const SizedBox(width: 8),
              _tabPill(
                index: 1,
                icon: Icons.star_border_rounded,
                label: 'Quick wizard',
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Main Card Content
          if (_tabIndex == 0) _buildDescribeIt() else _buildQuickWizard(),

          const SizedBox(height: 20),

          // Bottom Bar: Calibration status on left + "Build my road trip ->" on right
          LayoutBuilder(
            builder: (ctx, constraints) {
              final isWide = constraints.maxWidth > 580;
              final statusWidget = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF14B8A6),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Color(0xFF14B8A6), blurRadius: 6, spreadRadius: 1),
                      ],
                    ),
                  ),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      'Live distance, toll estimates, and real-time stops calibrated for Indian highways',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              );

              final buildButton = Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _submit,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF14B8A6), Color(0xFF0D9488)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x4D14B8A6),
                          blurRadius: 18,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('✨', style: TextStyle(fontSize: 15)),
                        SizedBox(width: 8),
                        Text(
                          'Build my road trip',
                          style: TextStyle(
                            color: Color(0xFF022C22),
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        SizedBox(width: 7),
                        Icon(Icons.arrow_forward_rounded, color: Color(0xFF022C22), size: 18),
                      ],
                    ),
                  ),
                ),
              );

              if (isWide) {
                return Row(
                  children: [
                    Expanded(child: statusWidget),
                    const SizedBox(width: 16),
                    buildButton,
                  ],
                );
              } else {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    statusWidget,
                    const SizedBox(height: 16),
                    buildButton,
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _tabPill({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _tabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _tabIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0C2925) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected ? const Color(0xFF14B8A6) : const Color(0xFF1E2E3B),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? const Color(0xFF5EEAD4) : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF5EEAD4) : const Color(0xFF94A3B8),
                fontSize: 13.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDescribeIt() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Dark textarea container
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF070B0E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1E2E3B), width: 1.1),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _promptCtrl,
                minLines: 3,
                maxLines: 5,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  height: 1.45,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'e.g. 3-day scenic drive from Bangalore to Coorg under ₹15,000 for foodies with coffee plantation stops',
                  hintStyle: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 14.5,
                    height: 1.45,
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  'Press Enter or click Build',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.32),
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // "Try asking:" section
        Text(
          'Try asking:',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 9),

        // Suggestion chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _suggestionChips.map((s) {
            return InkWell(
              onTap: () {
                setState(() {
                  _promptCtrl.text = s.$2;
                });
              },
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF111C24),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF223444)),
                ),
                child: Text(
                  s.$1,
                  style: const TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildQuickWizard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Two text fields: Starting Point & Destination
        LayoutBuilder(
          builder: (ctx, constraints) {
            final isWide = constraints.maxWidth > 500;
            final startField = _wizardInputField(
              controller: _startCtrl,
              label: 'Starting point',
              hint: 'e.g. Bangalore, KA',
              icon: Icons.my_location_rounded,
            );
            final destField = _wizardInputField(
              controller: _destCtrl,
              label: 'Destination',
              hint: 'e.g. Coorg, KA',
              icon: Icons.location_on_rounded,
            );

            if (isWide) {
              return Row(
                children: [
                  Expanded(child: startField),
                  const SizedBox(width: 14),
                  Expanded(child: destField),
                ],
              );
            } else {
              return Column(
                children: [
                  startField,
                  const SizedBox(height: 12),
                  destField,
                ],
              );
            }
          },
        ),
        const SizedBox(height: 16),

        // Duration selector (1-7 Days)
        Text(
          'Duration',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _dayOptions.map((d) {
            final isSel = _wizardDays == d;
            return ChoiceChip(
              label: Text('$d ${d == 1 ? "Day" : "Days"}'),
              selected: isSel,
              selectedColor: const Color(0xFF0C2925),
              backgroundColor: const Color(0xFF111C24),
              labelStyle: TextStyle(
                color: isSel ? const Color(0xFF5EEAD4) : const Color(0xFF94A3B8),
                fontSize: 12.5,
                fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
              ),
              side: BorderSide(
                color: isSel ? const Color(0xFF14B8A6) : const Color(0xFF223444),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              onSelected: (_) => setState(() => _wizardDays = d),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        // Travel Style selector
        Text(
          'Travel style',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _styleOptions.map((s) {
            final isSel = _wizardStyle == s;
            return ChoiceChip(
              label: Text(s),
              selected: isSel,
              selectedColor: const Color(0xFF0C2925),
              backgroundColor: const Color(0xFF111C24),
              labelStyle: TextStyle(
                color: isSel ? const Color(0xFF5EEAD4) : const Color(0xFF94A3B8),
                fontSize: 12.5,
                fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
              ),
              side: BorderSide(
                color: isSel ? const Color(0xFF14B8A6) : const Color(0xFF223444),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              onSelected: (_) => setState(() => _wizardStyle = s),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _wizardInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF070B0E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E2E3B)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF14B8A6)),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13.5),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
