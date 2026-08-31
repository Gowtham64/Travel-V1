import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

// ============================================================================
// Config-driven CRUD for the profile-menu entities.
// ============================================================================
enum FieldKind { text, multiline, number, date, toggle }

class CrudField {
  final String key, label;
  final FieldKind kind;
  final bool required;
  const CrudField(this.key, this.label, {this.kind = FieldKind.text, this.required = false});
}

class CrudConfig {
  final String path;
  final String? type; // sent as `type` on create + used as list filter
  final String title;
  final IconData icon;
  final Color accent;
  final String emptyHint;
  final List<CrudField> fields;
  final String Function(Map<String, dynamic>) titleOf;
  final String? Function(Map<String, dynamic>)? subtitleOf;
  final String? toggleKey; // e.g. 'packed' / 'read' — shows a checkbox

  const CrudConfig({
    required this.path,
    this.type,
    required this.title,
    required this.icon,
    this.accent = Voy.brand,
    required this.emptyHint,
    required this.fields,
    required this.titleOf,
    this.subtitleOf,
    this.toggleKey,
  });
}

String _s(Map<String, dynamic> m, String k) => (m[k] ?? '').toString();

/// Returns the config for a profile-menu item id, or null if it isn't a CRUD list.
CrudConfig? configForMenu(String id) {
  switch (id) {
    case 'wishlist':
      return CrudConfig(
        path: 'favorites', type: 'wishlist', title: 'Wishlist', icon: Icons.favorite_border_rounded, accent: Voy.coral,
        emptyHint: 'Save places you dream of visiting.',
        fields: const [CrudField('name', 'Place', required: true), CrudField('note', 'Note', kind: FieldKind.multiline)],
        titleOf: (m) => _s(m, 'name'), subtitleOf: (m) => _s(m, 'note'),
      );
    case 'saved_hotels':
      return CrudConfig(
        path: 'favorites', type: 'hotel', title: 'Saved Hotels', icon: Icons.hotel_outlined, accent: Voy.coral,
        emptyHint: 'Bookmark hotels you like.',
        fields: const [CrudField('name', 'Hotel', required: true), CrudField('note', 'Note', kind: FieldKind.multiline)],
        titleOf: (m) => _s(m, 'name'), subtitleOf: (m) => _s(m, 'note'),
      );
    case 'saved_dest':
      return CrudConfig(
        path: 'favorites', type: 'destination', title: 'Saved Destinations', icon: Icons.place_outlined, accent: Voy.coral,
        emptyHint: 'Keep a list of destinations.',
        fields: const [CrudField('name', 'Destination', required: true), CrudField('note', 'Note', kind: FieldKind.multiline)],
        titleOf: (m) => _s(m, 'name'), subtitleOf: (m) => _s(m, 'note'),
      );
    case 'flights':
      return CrudConfig(
        path: 'bookings', type: 'flight', title: 'Flights', icon: Icons.flight_rounded,
        emptyHint: 'Add your flight bookings.',
        fields: const [CrudField('title', 'Flight', required: true), CrudField('provider', 'Airline'), CrudField('reference', 'PNR / Ref'), CrudField('from_loc', 'From'), CrudField('to_loc', 'To')],
        titleOf: (m) => _s(m, 'title'), subtitleOf: (m) => [_s(m, 'provider'), _s(m, 'reference')].where((e) => e.isNotEmpty).join(' · '),
      );
    case 'hotels':
      return CrudConfig(
        path: 'bookings', type: 'hotel', title: 'Hotel Bookings', icon: Icons.hotel_rounded,
        emptyHint: 'Add your hotel bookings.',
        fields: const [CrudField('title', 'Hotel', required: true), CrudField('provider', 'Provider'), CrudField('reference', 'Booking ID')],
        titleOf: (m) => _s(m, 'title'), subtitleOf: (m) => [_s(m, 'provider'), _s(m, 'reference')].where((e) => e.isNotEmpty).join(' · '),
      );
    case 'train_bus':
      return CrudConfig(
        path: 'bookings', type: 'train', title: 'Train & Bus', icon: Icons.directions_transit_rounded,
        emptyHint: 'Add train or bus bookings.',
        fields: const [CrudField('title', 'Service', required: true), CrudField('provider', 'Operator'), CrudField('reference', 'PNR / Ref'), CrudField('seat', 'Seat / Coach')],
        titleOf: (m) => _s(m, 'title'), subtitleOf: (m) => [_s(m, 'provider'), _s(m, 'reference')].where((e) => e.isNotEmpty).join(' · '),
      );
    case 'car':
      return CrudConfig(
        path: 'bookings', type: 'car', title: 'Car Rentals', icon: Icons.directions_car_filled_outlined,
        emptyHint: 'Add your car rentals.',
        fields: const [CrudField('title', 'Car', required: true), CrudField('provider', 'Rental company'), CrudField('reference', 'Booking ID')],
        titleOf: (m) => _s(m, 'title'), subtitleOf: (m) => [_s(m, 'provider'), _s(m, 'reference')].where((e) => e.isNotEmpty).join(' · '),
      );
    case 'my_vehicles':
      return CrudConfig(
        path: 'vehicles', title: 'My Vehicles', icon: Icons.directions_car_rounded, accent: Voy.brand,
        emptyHint: 'Save your car or bike so you can pick it while planning trips.',
        fields: const [
          CrudField('name', 'Vehicle name (e.g. My Swift)', required: true),
          CrudField('type', 'Type — car or bike', required: true),
          CrudField('mileage_kmpl', 'Mileage (km/L)', kind: FieldKind.number),
          CrudField('tank_liters', 'Tank capacity (L)', kind: FieldKind.number),
        ],
        titleOf: (m) => _s(m, 'name'),
        subtitleOf: (m) => [
          _s(m, 'type'),
          _s(m, 'mileage_kmpl').isEmpty ? '' : '${_s(m, 'mileage_kmpl')} km/L',
          _s(m, 'tank_liters').isEmpty ? '' : '${_s(m, 'tank_liters')} L',
        ].where((e) => e.isNotEmpty).join(' · '),
      );
    case 'activities':
      return CrudConfig(
        path: 'bookings', type: 'activity', title: 'Activities', icon: Icons.local_activity_outlined,
        emptyHint: 'Add booked activities.',
        fields: const [CrudField('title', 'Activity', required: true), CrudField('provider', 'Provider'), CrudField('price', 'Price', kind: FieldKind.number)],
        titleOf: (m) => _s(m, 'title'), subtitleOf: (m) => _s(m, 'provider'),
      );
    case 'expenses':
      return CrudConfig(
        path: 'expenses', title: 'Expense Tracker', icon: Icons.receipt_long_outlined, accent: Voy.amber,
        emptyHint: 'Log what you spend on the trip.',
        fields: const [CrudField('category', 'Category', required: true), CrudField('amount', 'Amount', kind: FieldKind.number, required: true), CrudField('note', 'Note')],
        titleOf: (m) => _s(m, 'category'), subtitleOf: (m) => '${_s(m, 'currency').isEmpty ? 'INR' : _s(m, 'currency')} ${_s(m, 'amount')}${_s(m, 'note').isEmpty ? '' : ' · ${_s(m, 'note')}'}',
      );
    case 'budget_planner':
      return CrudConfig(
        path: 'budgets', title: 'Budget Planner', icon: Icons.pie_chart_outline_rounded, accent: Voy.amber,
        emptyHint: 'Set budgets for your trips.',
        fields: const [CrudField('total', 'Total budget', kind: FieldKind.number, required: true), CrudField('currency', 'Currency')],
        titleOf: (m) => '${_s(m, 'currency').isEmpty ? 'INR' : _s(m, 'currency')} ${_s(m, 'total')}', subtitleOf: (m) => 'Total budget',
      );
    case 'documents':
      return CrudConfig(
        path: 'documents', title: 'Documents', icon: Icons.description_outlined, accent: Voy.info,
        emptyHint: 'Keep travel documents handy.',
        fields: const [CrudField('title', 'Title', required: true), CrudField('type', 'Type (passport, visa…)'), CrudField('note', 'Note')],
        titleOf: (m) => _s(m, 'title'), subtitleOf: (m) => _s(m, 'type'),
      );
    case 'emergency':
      return CrudConfig(
        path: 'emergency', title: 'Emergency Contacts', icon: Icons.emergency_outlined, accent: Voy.coral,
        emptyHint: 'Add contacts for emergencies.',
        fields: const [CrudField('name', 'Name', required: true), CrudField('phone', 'Phone'), CrudField('relation', 'Relation')],
        titleOf: (m) => _s(m, 'name'), subtitleOf: (m) => [_s(m, 'relation'), _s(m, 'phone')].where((e) => e.isNotEmpty).join(' · '),
      );
    case 'packing':
      return CrudConfig(
        path: 'packing', title: 'Packing Checklist', icon: Icons.checklist_rtl_rounded,
        emptyHint: 'Build your packing list.',
        fields: const [CrudField('name', 'Item', required: true), CrudField('category', 'Category'), CrudField('qty', 'Qty', kind: FieldKind.number)],
        titleOf: (m) => _s(m, 'name'), subtitleOf: (m) => _s(m, 'category'), toggleKey: 'packed',
      );
    case 'notifications':
      return CrudConfig(
        path: 'notifications', title: 'Notifications', icon: Icons.notifications_none_rounded, accent: Voy.violet,
        emptyHint: 'No notifications yet.',
        fields: const [CrudField('title', 'Title', required: true), CrudField('body', 'Message', kind: FieldKind.multiline)],
        titleOf: (m) => _s(m, 'title'), subtitleOf: (m) => _s(m, 'body'), toggleKey: 'read',
      );
  }
  return null;
}

// ============================================================================
// Generic CRUD screen
// ============================================================================
class AccountCrudScreen extends StatefulWidget {
  final CrudConfig config;
  const AccountCrudScreen({super.key, required this.config});

  @override
  State<AccountCrudScreen> createState() => _AccountCrudScreenState();
}

class _AccountCrudScreenState extends State<AccountCrudScreen> {
  final _api = ApiService();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  CrudConfig get c => widget.config;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _api.accountList(c.path, type: c.type);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final data = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CrudFormSheet(config: c),
    );
    if (data == null) return;
    if (c.type != null) data['type'] = c.type;
    try {
      final created = await _api.accountCreate(c.path, data);
      if (mounted) setState(() => _items.insert(0, created));
    } catch (e) {
      _snack(e.toString());
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final id = item['id']?.toString();
    if (id == null) return;
    setState(() => _items.remove(item));
    try {
      await _api.accountDelete(c.path, id);
    } catch (e) {
      _snack(e.toString());
      _load();
    }
  }

  Future<void> _toggle(Map<String, dynamic> item) async {
    final id = item['id']?.toString();
    if (id == null || c.toggleKey == null) return;
    final next = !(item[c.toggleKey] == true);
    setState(() => item[c.toggleKey!] = next);
    try {
      await _api.accountUpdate(c.path, id, {c.toggleKey!: next});
    } catch (e) {
      setState(() => item[c.toggleKey!] = !next);
      _snack(e.toString());
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Voy.bg,
      appBar: AppBar(
        backgroundColor: Voy.bg,
        title: Text(c.title, style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.w800)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: c.accent,
        foregroundColor: const Color(0xFF04211F),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        color: Voy.brand,
        backgroundColor: Voy.surface,
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Voy.brand))
            : _error != null
                ? _errorView()
                : _items.isEmpty
                    ? _emptyView()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 90),
                        itemCount: _items.length,
                        itemBuilder: (_, i) => _card(_items[i]),
                      ),
      ),
    );
  }

  Widget _card(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? UniqueKey().toString();
    final on = item[c.toggleKey] == true;
    final sub = c.subtitleOf?.call(item) ?? '';
    return Dismissible(
      key: ValueKey(id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: Voy.coral.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete_outline_rounded, color: Voy.coral),
      ),
      onDismissed: (_) => _delete(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Voy.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Voy.hairline)),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
              child: Icon(c.icon, color: c.accent, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.titleOf(item), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: on ? Voy.sub : Voy.ink, fontSize: 15, fontWeight: FontWeight.w700, decoration: on ? TextDecoration.lineThrough : null)),
                  if (sub.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 3), child: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Voy.sub, fontSize: 12.5))),
                ],
              ),
            ),
            if (c.toggleKey != null)
              IconButton(
                onPressed: () => _toggle(item),
                icon: Icon(on ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: on ? Voy.success : Voy.sub),
              )
            else
              IconButton(onPressed: () => _delete(item), icon: const Icon(Icons.delete_outline_rounded, color: Voy.sub)),
          ],
        ),
      ),
    );
  }

  Widget _emptyView() => ListView(
        children: [
          const SizedBox(height: 120),
          Icon(c.icon, size: 54, color: Voy.sub.withValues(alpha: 0.6)),
          const SizedBox(height: 14),
          Center(child: Text(c.emptyHint, style: const TextStyle(color: Voy.sub, fontSize: 14))),
          const SizedBox(height: 14),
          Center(
            child: OutlinedButton.icon(onPressed: _add, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add first item')),
          ),
        ],
      );

  Widget _errorView() => ListView(
        children: [
          const SizedBox(height: 120),
          const Icon(Icons.cloud_off_rounded, size: 48, color: Voy.coral),
          const SizedBox(height: 14),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 30), child: Text(_error ?? 'Something went wrong', textAlign: TextAlign.center, style: const TextStyle(color: Voy.sub))),
          const SizedBox(height: 14),
          Center(child: OutlinedButton(onPressed: _load, child: const Text('Retry'))),
        ],
      );
}

// ---- Add form ----
class _CrudFormSheet extends StatefulWidget {
  final CrudConfig config;
  const _CrudFormSheet({required this.config});
  @override
  State<_CrudFormSheet> createState() => _CrudFormSheetState();
}

class _CrudFormSheetState extends State<_CrudFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _ctrls = {};

  @override
  void initState() {
    super.initState();
    for (final f in widget.config.fields) {
      if (f.kind != FieldKind.toggle) _ctrls[f.key] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final data = <String, dynamic>{};
    for (final f in widget.config.fields) {
      final v = _ctrls[f.key]?.text.trim() ?? '';
      if (v.isEmpty) continue;
      data[f.key] = f.kind == FieldKind.number ? (num.tryParse(v) ?? v) : v;
    }
    Navigator.of(context).pop(data);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(color: Voy.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Voy.hairline, borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 14),
              Text('Add to ${widget.config.title}', style: const TextStyle(color: Voy.ink, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              for (final f in widget.config.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    controller: _ctrls[f.key],
                    keyboardType: f.kind == FieldKind.number ? const TextInputType.numberWithOptions(decimal: true) : (f.kind == FieldKind.multiline ? TextInputType.multiline : TextInputType.text),
                    maxLines: f.kind == FieldKind.multiline ? 3 : 1,
                    style: const TextStyle(color: Voy.ink),
                    decoration: InputDecoration(labelText: f.label + (f.required ? ' *' : '')),
                    validator: (v) => (f.required && (v == null || v.trim().isEmpty)) ? 'Required' : null,
                  ),
                ),
              const SizedBox(height: 4),
              ElevatedButton(onPressed: _submit, child: const Text('Save')),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Currency Converter
// ============================================================================
class CurrencyConverterScreen extends StatefulWidget {
  const CurrencyConverterScreen({super.key});
  @override
  State<CurrencyConverterScreen> createState() => _CurrencyConverterScreenState();
}

class _CurrencyConverterScreenState extends State<CurrencyConverterScreen> {
  final _api = ApiService();
  final _amount = TextEditingController(text: '100');
  static const _currencies = ['INR', 'USD', 'EUR', 'GBP', 'AED', 'SGD', 'JPY', 'AUD', 'CAD', 'THB'];
  String _from = 'USD', _to = 'INR';
  String? _result, _rate, _error;
  bool _loading = false;

  Future<void> _convert() async {
    final amt = double.tryParse(_amount.text.trim());
    if (amt == null) {
      setState(() => _error = 'Please enter a valid amount.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.convertCurrency(from: _from, to: _to, amount: amt);
      if (!mounted) return;
      setState(() {
        _result = '${r['result']}';
        _rate = '1 $_from = ${r['rate']} $_to';
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _result = null;
        _rate = null;
        _error = e is ApiException ? e.message : "Couldn't fetch the exchange rate. Please try again.";
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _convert();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Voy.bg,
      appBar: AppBar(backgroundColor: Voy.bg, title: const Text('Currency Converter', style: TextStyle(color: Voy.ink, fontWeight: FontWeight.w800))),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Voy.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: Voy.hairline)),
              child: Column(
                children: [
                  TextField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Voy.ink, fontSize: 20, fontWeight: FontWeight.w800),
                    decoration: const InputDecoration(labelText: 'Amount'),
                    onSubmitted: (_) => _convert(),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: _dropdown(_from, (v) => setState(() => _from = v))),
                      IconButton(
                        onPressed: () => setState(() {
                          final t = _from;
                          _from = _to;
                          _to = t;
                        }),
                        icon: const Icon(Icons.swap_horiz_rounded, color: Voy.brand),
                      ),
                      Expanded(child: _dropdown(_to, (v) => setState(() => _to = v))),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _convert,
                      icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.currency_exchange_rounded, size: 18),
                      label: const Text('Convert'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_result != null) ...[
              Text('$_to $_result', style: const TextStyle(color: Voy.ink, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1)),
              const SizedBox(height: 6),
            ],
            if (_rate != null) Text(_rate!, style: const TextStyle(color: Voy.sub, fontSize: 13)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown(String value, ValueChanged<String> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Voy.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: Voy.hairline)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: Voy.surface,
          style: const TextStyle(color: Voy.ink, fontSize: 16, fontWeight: FontWeight.w700),
          items: [for (final ccy in _currencies) DropdownMenuItem(value: ccy, child: Text(ccy))],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      ),
    );
  }
}

// ============================================================================
// Profile / Settings
// ============================================================================
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _api = ApiService();
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _phone = TextEditingController();
  String _language = 'en', _currency = 'INR', _theme = 'dark';
  bool _loading = true, _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _api.getProfile();
      if (!mounted) return;
      setState(() {
        _name.text = (p['display_name'] ?? '').toString();
        _city.text = (p['home_city'] ?? '').toString();
        _phone.text = (p['phone'] ?? '').toString();
        _language = (p['language'] ?? 'en').toString();
        _currency = (p['currency'] ?? 'INR').toString();
        _theme = (p['theme'] ?? 'dark').toString();
      });
    } catch (_) {
      // Show defaults; save will create the row.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _api.putProfile({
        'display_name': _name.text.trim(),
        'home_city': _city.text.trim(),
        'phone': _phone.text.trim(),
        'language': _language,
        'currency': _currency,
        'theme': _theme,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved ✓')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Voy.bg,
      appBar: AppBar(backgroundColor: Voy.bg, title: const Text('Profile & Settings', style: TextStyle(color: Voy.ink, fontWeight: FontWeight.w800))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Voy.brand))
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                _section('Profile'),
                TextField(controller: _name, style: const TextStyle(color: Voy.ink), decoration: const InputDecoration(labelText: 'Display name')),
                const SizedBox(height: 12),
                TextField(controller: _city, style: const TextStyle(color: Voy.ink), decoration: const InputDecoration(labelText: 'Home city')),
                const SizedBox(height: 12),
                TextField(controller: _phone, keyboardType: TextInputType.phone, style: const TextStyle(color: Voy.ink), decoration: const InputDecoration(labelText: 'Phone')),
                const SizedBox(height: 22),
                _section('Preferences'),
                _pickerRow('Language', _language, const ['en', 'hi', 'kn', 'ta', 'te'], (v) => setState(() => _language = v)),
                _pickerRow('Currency', _currency, const ['INR', 'USD', 'EUR', 'GBP', 'AED'], (v) => setState(() => _currency = v)),
                _pickerRow('Theme', _theme, const ['dark', 'light', 'system'], (v) => setState(() => _theme = v)),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save changes'),
                ),
              ],
            ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(t.toUpperCase(), style: const TextStyle(color: Voy.sub, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
      );

  Widget _pickerRow(String label, String value, List<String> options, ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Voy.ink, fontSize: 14, fontWeight: FontWeight.w600))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: Voy.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: Voy.hairline)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                dropdownColor: Voy.surface,
                style: const TextStyle(color: Voy.ink, fontSize: 14, fontWeight: FontWeight.w700),
                items: [for (final o in options) DropdownMenuItem(value: o, child: Text(o))],
                onChanged: (v) => v == null ? null : onChanged(v),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Travel Wallet Screen
// ============================================================================
class TravelWalletScreen extends StatefulWidget {
  const TravelWalletScreen({super.key});

  @override
  State<TravelWalletScreen> createState() => _TravelWalletScreenState();
}

class _TravelWalletScreenState extends State<TravelWalletScreen> {
  final _api = ApiService();
  List<Map<String, dynamic>> _expenses = [];
  bool _loading = true;
  double _budget = 25000.0;
  double _fastagBalance = 1450.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await _api.accountList('expenses');
      final budgets = await _api.accountList('budgets');
      if (budgets.isNotEmpty) {
        _budget = double.tryParse('${budgets.first['total'] ?? ''}') ?? 25000.0;
      }
      if (mounted) setState(() => _expenses = items);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  double get _totalSpent {
    double sum = 0;
    for (final e in _expenses) {
      sum += double.tryParse('${e['amount'] ?? 0}') ?? 0;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final spent = _totalSpent;
    final remaining = (_budget - spent).clamp(0.0, double.infinity);
    final progress = _budget > 0 ? (spent / _budget).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      backgroundColor: Voy.bg,
      appBar: AppBar(
        backgroundColor: Voy.bg,
        title: const Text('Travel Wallet', style: TextStyle(color: Voy.ink, fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Voy.brand))
          : RefreshIndicator(
              onRefresh: _load,
              color: Voy.brand,
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  // Wallet Balance Card
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6), Color(0xFF06B6D4)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('VOYPLAN TRAVEL PASS', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                              child: const Text('ACTIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const Text('Available Budget', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text('₹${remaining.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Spent: ₹${spent.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                            Text('Total: ₹${_budget.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.white.withValues(alpha: 0.2),
                            valueColor: AlwaysStoppedAnimation<Color>(progress > 0.85 ? Colors.orangeAccent : Colors.white),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // FASTag & Tolls Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Voy.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Voy.hairline),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Voy.brand.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
                          child: const Icon(Icons.toll_rounded, color: Voy.brand, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('FASTag Toll Balance', style: TextStyle(color: Voy.ink, fontSize: 15, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text('₹${_fastagBalance.toStringAsFixed(0)} available', style: const TextStyle(color: Voy.success, fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Voy.brand,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('FASTag Recharge simulator: +₹500 added!'), behavior: SnackBarBehavior.floating),
                            );
                            setState(() => _fastagBalance += 500);
                          },
                          child: const Text('Recharge', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Recent Travel Expenses
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('RECENT EXPENSES', style: TextStyle(color: Voy.sub, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Expense'),
                        onPressed: () async {
                          final cfg = configForMenu('expenses');
                          if (cfg != null) {
                            await Navigator.push(context, MaterialPageRoute(builder: (_) => AccountCrudScreen(config: cfg)));
                            _load();
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_expenses.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(28),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Voy.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: Voy.hairline)),
                      child: const Text('No expenses recorded yet. Tap "+ Add Expense" to track your trip spending.', textAlign: TextAlign.center, style: TextStyle(color: Voy.sub, fontSize: 13)),
                    )
                  else
                    ..._expenses.take(5).map((e) => Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: Voy.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: Voy.hairline)),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Voy.amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                                child: const Icon(Icons.receipt_long_rounded, color: Voy.amber, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${e['category'] ?? 'Expense'}', style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.bold, fontSize: 14)),
                                    if (e['note'] != null && e['note'].toString().isNotEmpty)
                                      Text('${e['note']}', style: const TextStyle(color: Voy.sub, fontSize: 12)),
                                  ],
                                ),
                              ),
                              Text('₹${e['amount'] ?? '0'}', style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.bold, fontSize: 15)),
                            ],
                          ),
                        )),
                ],
              ),
            ),
    );
  }
}

// ============================================================================
// Help & Support Screen
// ============================================================================
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Voy.bg,
      appBar: AppBar(
        backgroundColor: Voy.bg,
        title: const Text('Help & Support', style: TextStyle(color: Voy.ink, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          // Emergency Helpline Banner
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF991B1B), Color(0xFFDC2626)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.emergency_rounded, color: Colors.white, size: 22),
                    SizedBox(width: 8),
                    Text('24x7 Roadside & Emergency Helplines', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
                const SizedBox(height: 12),
                _helplineRow('National Highway Helpline (NHAI)', '1033'),
                _helplineRow('National Emergency Number', '112'),
                _helplineRow('Ambulance / Medical', '108'),
                _helplineRow('Police Assistance', '100'),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // FAQs
          const Text('FREQUENTLY ASKED QUESTIONS', style: TextStyle(color: Voy.sub, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
          const SizedBox(height: 12),
          _faqTile(
            'How does Voyplan calculate FASTag toll costs?',
            'Voyplan queries live NHAI plaza fee schedules along your specific route and vehicle class (Car, SUV, Bus, Truck, Motorcycle).',
          ),
          _faqTile(
            'How do Live Activities & Dynamic Island work?',
            'When you start a trip, Voyplan streams real-time vehicle movement, intermediate stops, distance remaining, and turn guidance directly to your iPhone Lock Screen and Dynamic Island.',
          ),
          _faqTile(
            'How do I add stop points along my route?',
            'In the Trip Planner, tap "+ Add Stop" to insert waypoints, fuel stations, dining, or scenic viewpoints. They are tracked live throughout your journey.',
          ),
          _faqTile(
            'Does Voyplan work offline?',
            'Yes! Your planned routes, downloaded itineraries, and trip history are automatically cached locally on your device.',
          ),
          const SizedBox(height: 24),

          // Contact Support Button
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Voy.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Voy.hairline),
            ),
            child: Column(
              children: [
                const Icon(Icons.support_agent_rounded, size: 36, color: Voy.brand),
                const SizedBox(height: 10),
                const Text('Need further assistance?', style: TextStyle(color: Voy.ink, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                const Text('Our travel operations team is ready to assist you.', style: TextStyle(color: Voy.sub, fontSize: 13)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Support request submitted! We will email you shortly.'), behavior: SnackBarBehavior.floating),
                      );
                    },
                    icon: const Icon(Icons.mail_outline_rounded),
                    label: const Text('Contact Support'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _helplineRow(String title, String number) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      );

  static Widget _faqTile(String question, String answer) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: Voy.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: Voy.hairline)),
        child: ExpansionTile(
          shape: const Border(),
          iconColor: Voy.brand,
          collapsedIconColor: Voy.sub,
          title: Text(question, style: const TextStyle(color: Voy.ink, fontWeight: FontWeight.w600, fontSize: 14)),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(answer, style: const TextStyle(color: Voy.sub, fontSize: 13, height: 1.4)),
            ),
          ],
        ),
      );
}
