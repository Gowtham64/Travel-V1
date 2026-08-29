import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Opens the premium, glassmorphic profile menu as a bottom sheet.
/// [onSelect] is called with an item id + label after the sheet closes.
Future<void> showProfileMenu(
  BuildContext context, {
  required String name,
  required String email,
  required void Function(String id, String label) onSelect,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (_) => _ProfileMenuSheet(name: name, email: email, onSelect: onSelect),
  );
}

class _Item {
  final String id, label;
  final IconData icon;
  final Color? accent;
  final Widget? trailing;
  const _Item(this.id, this.label, this.icon, {this.accent, this.trailing});
}

class _Section {
  final String emoji, title;
  final List<_Item> items;
  const _Section(this.emoji, this.title, this.items);
}

class _ProfileMenuSheet extends StatelessWidget {
  final String name;
  final String email;
  final void Function(String id, String label) onSelect;
  const _ProfileMenuSheet({required this.name, required this.email, required this.onSelect});

  static Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
      );

  static Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
      );

  List<_Section> get _sections => [
        _Section('👤', 'Profile', const [
          _Item('profile', 'My Profile', Icons.person_outline_rounded),
          _Item('edit_profile', 'Edit Profile', Icons.edit_outlined),
        ]),
        _Section('✈️', 'Trips', [
          _Item('upcoming', 'Upcoming Trips', Icons.flight_takeoff_rounded, trailing: _pill('2', Voy.brand)),
          _Item('ongoing', 'Ongoing Trips', Icons.navigation_outlined,
              trailing: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Voy.success, shape: BoxShape.circle))),
          const _Item('completed', 'Completed Trips', Icons.check_circle_outline_rounded),
          const _Item('saved', 'Saved Trips', Icons.bookmark_border_rounded),
          const _Item('atlas', 'My Atlas', Icons.public_rounded),
          const _Item('drafts', 'Draft Itineraries', Icons.edit_note_rounded),
        ]),
        _Section('❤️', 'Favorites', const [
          _Item('wishlist', 'Wishlist', Icons.favorite_border_rounded, accent: Voy.coral),
          _Item('saved_hotels', 'Saved Hotels', Icons.hotel_outlined, accent: Voy.coral),
          _Item('saved_dest', 'Saved Destinations', Icons.place_outlined, accent: Voy.coral),
        ]),
        _Section('📄', 'Bookings', const [
          _Item('flights', 'Flights', Icons.flight_rounded),
          _Item('hotels', 'Hotels', Icons.hotel_rounded),
          _Item('train_bus', 'Train & Bus', Icons.directions_transit_rounded),
          _Item('car', 'Car Rentals', Icons.directions_car_filled_outlined),
          _Item('activities', 'Activities', Icons.local_activity_outlined),
        ]),
        _Section('🗺️', 'AI Itinerary', [
          _Item('generate', 'Generate New Trip', Icons.auto_awesome_rounded, accent: Voy.violet, trailing: _pill('AI', Voy.violet)),
          const _Item('my_itineraries', 'My Itineraries', Icons.event_note_rounded, accent: Voy.violet),
          const _Item('import', 'Import', Icons.file_download_outlined, accent: Voy.violet),
          const _Item('export_pdf', 'Export PDF', Icons.picture_as_pdf_outlined, accent: Voy.violet),
        ]),
        _Section('💰', 'Budget', const [
          _Item('expenses', 'Expense Tracker', Icons.receipt_long_outlined),
          _Item('budget_planner', 'Budget Planner', Icons.pie_chart_outline_rounded),
          _Item('wallet', 'Travel Wallet', Icons.account_balance_wallet_outlined),
        ]),
        _Section('🧳', 'Travel Tools', const [
          _Item('my_vehicles', 'My Vehicles', Icons.directions_car_rounded),
          _Item('packing', 'Packing Checklist', Icons.checklist_rtl_rounded),
          _Item('documents', 'Documents', Icons.description_outlined),
          _Item('emergency', 'Emergency Contacts', Icons.emergency_outlined),
          _Item('currency_conv', 'Currency Converter', Icons.currency_exchange_rounded),
        ]),
        _Section('🔔', 'Notifications', [
          _Item('notifications', 'Notifications', Icons.notifications_none_rounded, trailing: _badge('4', Voy.coral)),
        ]),
        _Section('⚙️', 'Settings', const [
          _Item('appearance', 'Appearance', Icons.dark_mode_outlined),
          _Item('language', 'Language', Icons.language_rounded),
          _Item('currency', 'Currency', Icons.paid_outlined),
          _Item('security', 'Security', Icons.lock_outline_rounded),
        ]),
        _Section('❓', 'Support', const [
          _Item('help', 'Help & Support', Icons.help_outline_rounded),
        ]),
      ];

  void _tap(BuildContext context, String id, String label) {
    Navigator.of(context).pop();
    onSelect(id, label);
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.9;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: BoxDecoration(
            color: Voy.surface.withValues(alpha: 0.86),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(99))),
              _header(context),
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                  children: [
                    for (final s in _sections) ...[
                      _sectionLabel(s),
                      for (final it in s.items) _row(context, it),
                      Divider(color: Colors.white.withValues(alpha: 0.06), height: 14, indent: 14, endIndent: 14),
                    ],
                  ],
                ),
              ),
              // footer logout
              Padding(
                padding: EdgeInsets.fromLTRB(10, 4, 10, 10 + MediaQuery.of(context).padding.bottom),
                child: _row(context, const _Item('logout', 'Logout', Icons.logout_rounded, accent: Voy.coral), logout: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final initials = name.isNotEmpty ? name.trim().split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase() : 'V';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Voy.brand.withValues(alpha: 0.16), Colors.transparent], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFEC4899)]),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [BoxShadow(color: const Color(0xFF7C3AED).withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Voy.ink, fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Voy.sub, fontSize: 12)),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Voy.amber.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(999), border: Border.all(color: Voy.amber.withValues(alpha: 0.35))),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.workspace_premium_rounded, color: Voy.amber, size: 12),
                        SizedBox(width: 4),
                        Text('EXPLORER PRO', style: TextStyle(color: Voy.amber, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                      ]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _tap(context, 'profile', 'My Profile'),
              icon: const Icon(Icons.person_outline_rounded, size: 18),
              label: const Text('View profile'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(_Section s) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
        child: Row(children: [
          Text(s.emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 7),
          Text(s.title.toUpperCase(), style: const TextStyle(color: Voy.sub, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
        ]),
      );

  Widget _row(BuildContext context, _Item it, {bool logout = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _tap(context, it.id, it.label),
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: logout ? Voy.coral.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Icon(it.icon, size: 18, color: logout ? Voy.coral : (it.accent ?? Voy.sub)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(it.label,
                    style: TextStyle(color: logout ? Voy.coral : Voy.ink, fontSize: 14, fontWeight: logout ? FontWeight.w700 : FontWeight.w600)),
              ),
              if (it.trailing != null) it.trailing! else if (!logout) Icon(Icons.chevron_right_rounded, color: Voy.sub.withValues(alpha: 0.6), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
