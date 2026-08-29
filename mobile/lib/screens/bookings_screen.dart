import 'package:flutter/material.dart';
import '../models/trip_extras.dart';
import '../services/api_service.dart';
import '../services/trip_extras_store.dart';
import '../services/auth_guard.dart';
import '../theme/app_theme.dart';

/// A self-contained bookings manager: list saved flight/train/hotel/etc.
/// reservations, add/edit them, and fetch AI-suggested flights, trains and
/// hotels for the journey. Used both as the Trip Workspace "Bookings" tab and
/// as a standalone screen opened from the round-trip day planner.
class BookingsScreen extends StatefulWidget {
  final TripExtrasStore store;
  final String fromName;
  final String toName;
  final int travellers;

  /// When true, renders without its own AppBar (for embedding inside a tab).
  final bool embedded;

  const BookingsScreen({
    super.key,
    required this.store,
    this.fromName = '',
    this.toName = '',
    this.travellers = 1,
    this.embedded = false,
  });

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  List<Reservation> _items = [];
  bool _loading = true;
  bool _suggesting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.store.loadReservations();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  void _persist() => widget.store.saveReservations(_items);

  void _addSuggestion(String type, String title, String notes) {
    if (!AuthGuard.ensure(context, action: 'save bookings')) return;
    setState(() => _items.add(Reservation(
          id: _bkUid(),
          type: type,
          title: title,
          confirmation: '',
          date: null,
          notes: notes,
        )));
    _persist();
  }

  Future<void> _suggest() async {
    if (widget.toName.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This journey has no destination set.')),
      );
      return;
    }
    setState(() => _suggesting = true);
    try {
      final o = await ApiService().aiTravelOptions(
        from: widget.fromName,
        to: widget.toName,
        travellers: widget.travellers,
      );
      if (!mounted) return;
      setState(() => _suggesting = false);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF14121F),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => _SuggestionsSheet(
          from: widget.fromName,
          to: widget.toName,
          flights: o.flights,
          trains: o.trains,
          hotels: o.hotels,
          onAdd: (type, title, notes) {
            _addSuggestion(type, title, notes);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Added "$title" to bookings.')),
            );
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _suggesting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : 'Could not fetch suggestions.')),
      );
    }
  }

  Future<void> _addOrEdit([Reservation? existing]) async {
    if (!AuthGuard.ensure(context, action: 'save bookings')) return;
    final result = await showModalBottomSheet<Reservation>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ReservationSheet(existing: existing),
    );
    if (result == null) return;
    setState(() {
      if (existing != null) {
        final i = _items.indexWhere((e) => e.id == existing.id);
        if (i != -1) _items[i] = result;
      } else {
        _items.add(result);
      }
    });
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    // Embedded: render as a plain column (buttons + list) to sit inside another
    // scrollable panel (e.g. the trip planner's side column). Standalone: a full
    // screen with its own app bar and floating buttons.
    if (widget.embedded) return _embeddedColumn();
    return Scaffold(
      backgroundColor: Voy.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Bookings'),
        foregroundColor: Voy.ink,
      ),
      body: _buildBody(),
    );
  }

  Widget _embeddedColumn() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    final sorted = [..._items]..sort((a, b) {
        if (a.date == null && b.date == null) return 0;
        if (a.date == null) return 1;
        if (b.date == null) return -1;
        return a.date!.compareTo(b.date!);
      });
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          const Icon(Icons.airplane_ticket_outlined, size: 18, color: Colors.white),
          const SizedBox(width: 8),
          const Expanded(child: Text('Bookings', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800))),
          TextButton.icon(
            onPressed: () => _addOrEdit(),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Add'),
            style: TextButton.styleFrom(foregroundColor: Voy.brand, padding: const EdgeInsets.symmetric(horizontal: 8)),
          ),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _suggesting ? null : _suggest,
            icon: _suggesting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text(_suggesting ? 'Finding…' : 'Suggest flights, trains & hotels'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6D5EF6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (sorted.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text('No bookings yet — get AI suggestions above, or add your own.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12.5)),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: sorted.length,
            itemBuilder: (ctx, i) {
              final r = sorted[i];
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: ListTile(
                  dense: true,
                  onTap: () => _addOrEdit(r),
                  leading: Icon(_bkTypeIcon(r.type), color: Voy.brand, size: 20),
                  title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5)),
                  subtitle: Text(
                    [
                      _bkTypeLabel(r.type),
                      if (r.date != null) _bkFmtDate(r.date!),
                      if (r.notes.isNotEmpty) r.notes,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11.5),
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.close_rounded, size: 16, color: Colors.white.withValues(alpha: 0.5)),
                    onPressed: () {
                      setState(() => _items.removeWhere((x) => x.id == r.id));
                      _persist();
                    },
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final sorted = [..._items]..sort((a, b) {
        if (a.date == null && b.date == null) return 0;
        if (a.date == null) return 1;
        if (b.date == null) return -1;
        return a.date!.compareTo(b.date!);
      });

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'bk_suggestAi',
            onPressed: _suggesting ? null : _suggest,
            backgroundColor: const Color(0xFF6D5EF6),
            foregroundColor: Colors.white,
            icon: _suggesting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome_rounded),
            label: Text(_suggesting ? 'Finding…' : 'Suggest flights, trains & hotels'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'bk_addBooking',
            onPressed: () => _addOrEdit(),
            backgroundColor: Voy.brand,
            foregroundColor: const Color(0xFF04211F),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add booking'),
          ),
        ],
      ),
      body: sorted.isEmpty
          ? _bkEmptyState(Icons.confirmation_number_rounded, 'No bookings yet',
              'Tap "Suggest flights, trains & hotels" for AI options, or add your own.')
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: sorted.length,
              itemBuilder: (ctx, i) {
                final r = sorted[i];
                return Dismissible(
                  key: ValueKey(r.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                        color: Voy.danger.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.delete_outline_rounded, color: Voy.danger),
                  ),
                  onDismissed: (_) {
                    setState(() => _items.removeWhere((x) => x.id == r.id));
                    _persist();
                  },
                  child: Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      onTap: () => _addOrEdit(r),
                      leading: CircleAvatar(
                        backgroundColor: Voy.surface2,
                        child: Icon(_bkTypeIcon(r.type), color: Voy.brand, size: 20),
                      ),
                      title: Text(r.title, style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        [
                          _bkTypeLabel(r.type),
                          if (r.date != null) _bkFmtDate(r.date!),
                          if (r.confirmation.isNotEmpty) '#${r.confirmation}',
                          if (r.notes.isNotEmpty) r.notes,
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Voy.sub, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded, color: Voy.sub),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

String _bkUid() => DateTime.now().microsecondsSinceEpoch.toString();

String _bkFmtDate(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

IconData _bkTypeIcon(String t) {
  switch (t) {
    case 'flight':
      return Icons.flight_rounded;
    case 'train':
      return Icons.train_rounded;
    case 'hotel':
      return Icons.hotel_rounded;
    case 'restaurant':
      return Icons.restaurant_rounded;
    case 'activity':
      return Icons.local_activity_rounded;
    default:
      return Icons.confirmation_number_rounded;
  }
}

String _bkTypeLabel(String t) => t.isEmpty ? 'Booking' : t[0].toUpperCase() + t.substring(1);

Widget _bkEmptyState(IconData icon, String title, String subtitle) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Voy.sub),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: Voy.ink, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Voy.sub, fontSize: 13)),
        ],
      ),
    ),
  );
}

/// Bottom sheet showing AI-suggested flights, trains and hotels for a journey.
class _SuggestionsSheet extends StatelessWidget {
  final String from;
  final String to;
  final List<Map<String, String>> flights;
  final List<Map<String, String>> trains;
  final List<Map<String, String>> hotels;
  final void Function(String type, String title, String notes) onAdd;

  const _SuggestionsSheet({
    required this.from,
    required this.to,
    required this.flights,
    required this.trains,
    required this.hotels,
    required this.onAdd,
  });

  String _join(Iterable<String?> parts) =>
      parts.where((p) => p != null && p.trim().isNotEmpty).map((p) => p!.trim()).join(' · ');

  Widget _sectionHeader(IconData icon, String label, Color color) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _card({required String title, required String subtitle, required String trailing, required VoidCallback onTap}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: ListTile(
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14.5)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (subtitle.isNotEmpty)
              Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5)),
            if (trailing.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(trailing, style: const TextStyle(color: Color(0xFF7DD3FC), fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
          ]),
        ),
        trailing: TextButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
          label: const Text('Add'),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF6D5EF6)),
        ),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final empty = flights.isEmpty && trains.isEmpty && hotels.isEmpty;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (ctx, scroll) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: ListView(
          controller: scroll,
          children: [
            Center(
              child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            ),
            const Text('Suggested options', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('${from.isEmpty ? 'Your trip' : from} → $to · typical options, not live prices',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12.5)),
            if (empty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Text('No suggestions returned — try again.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6)))),
              ),
            if (flights.isNotEmpty) _sectionHeader(Icons.flight_rounded, 'Flights', const Color(0xFF38BDF8)),
            for (final f in flights)
              _card(
                title: _join([f['airline'], f['flightNo']]),
                subtitle: _join([
                  f['route'],
                  f['stops']?.toLowerCase() == 'direct'
                      ? 'Direct'
                      : (f['stops'] != null && f['stops']!.isNotEmpty ? 'via ${f['stops']}' : null),
                  f['duration'],
                ]),
                trailing: _join([f['priceRange'], f['note']]),
                onTap: () => onAdd('flight', _join([f['airline'], f['flightNo']]),
                    _join([f['route'], f['stops'], f['duration'], f['priceRange'], f['note']])),
              ),
            if (trains.isNotEmpty) _sectionHeader(Icons.train_rounded, 'Trains', const Color(0xFF34D399)),
            for (final t in trains)
              _card(
                title: _join([t['operator'], t['name']]),
                subtitle: _join([t['route'], t['duration']]),
                trailing: _join([t['priceRange'], t['note']]),
                onTap: () => onAdd('train', _join([t['operator'], t['name']]),
                    _join([t['route'], t['duration'], t['priceRange'], t['note']])),
              ),
            if (hotels.isNotEmpty) _sectionHeader(Icons.hotel_rounded, 'Hotels', const Color(0xFFA78BFA)),
            for (final h in hotels)
              _card(
                title: _join([h['name'], h['rating']]),
                subtitle: _join([h['area'], h['note']]),
                trailing: h['pricePerNight'] != null && h['pricePerNight']!.isNotEmpty ? '${h['pricePerNight']} / night' : '',
                onTap: () => onAdd('hotel', h['name'] ?? 'Hotel',
                    _join([
                      h['area'],
                      h['pricePerNight'] != null && h['pricePerNight']!.isNotEmpty ? '${h['pricePerNight']}/night' : null,
                      h['rating'],
                      h['note'],
                    ])),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Sheet to add or edit a single booking record.
class _ReservationSheet extends StatefulWidget {
  final Reservation? existing;
  const _ReservationSheet({this.existing});
  @override
  State<_ReservationSheet> createState() => _ReservationSheetState();
}

class _ReservationSheetState extends State<_ReservationSheet> {
  late final TextEditingController _title;
  late final TextEditingController _confirmation;
  late final TextEditingController _notes;
  late String _type;
  DateTime? _date;

  static const _types = ['flight', 'train', 'hotel', 'restaurant', 'activity', 'other'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _confirmation = TextEditingController(text: e?.confirmation ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _type = e?.type ?? 'hotel';
    _date = e?.date;
  }

  @override
  void dispose() {
    _title.dispose();
    _confirmation.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _save() {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give the booking a name.')),
      );
      return;
    }
    Navigator.pop(
      context,
      Reservation(
        id: widget.existing?.id ?? _bkUid(),
        type: _type,
        title: _title.text.trim(),
        confirmation: _confirmation.text.trim(),
        date: _date,
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 18, right: 18, top: 18, bottom: MediaQuery.of(context).viewInsets.bottom + 18),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.existing == null ? 'Add booking' : 'Edit booking',
                style: const TextStyle(color: Voy.ink, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _types)
                  ChoiceChip(
                    avatar: Icon(_bkTypeIcon(t), size: 16, color: _type == t ? const Color(0xFF04211F) : Voy.sub),
                    label: Text(_bkTypeLabel(t)),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              style: const TextStyle(color: Voy.ink),
              decoration: const InputDecoration(labelText: 'Name (e.g. Taj Hotel, IndiGo 6E-123)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmation,
              style: const TextStyle(color: Voy.ink),
              decoration: const InputDecoration(labelText: 'Confirmation / PNR (optional)'),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Date'),
                child: Text(
                  _date == null ? 'Tap to pick a date' : _bkFmtDate(_date!),
                  style: TextStyle(color: _date == null ? Voy.sub : Voy.ink),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 3,
              style: const TextStyle(color: Voy.ink),
              decoration: const InputDecoration(labelText: 'Details / notes (route, times, price…)'),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: _save, child: const Text('Save booking')),
            ),
          ],
        ),
      ),
    );
  }
}
