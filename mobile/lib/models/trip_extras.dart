// Data models for the trip workspace add-ons: interactive packing checklist,
// expense tracker (with splitting), and reservations. All are plain, JSON-
// serializable value types persisted locally per trip (see TripExtrasStore).

/// A single packing-list entry the traveller can tick off.
class PackingItem {
  final String id;
  String name;
  String category;
  bool packed;

  PackingItem({
    required this.id,
    required this.name,
    this.category = 'General',
    this.packed = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'packed': packed,
      };

  factory PackingItem.fromJson(Map<String, dynamic> j) => PackingItem(
        id: j['id'].toString(),
        name: (j['name'] ?? '').toString(),
        category: (j['category'] ?? 'General').toString(),
        packed: j['packed'] == true,
      );
}

/// A trip expense, optionally split across a set of travellers.
class Expense {
  final String id;
  String title;
  double amount;
  String currency;
  String paidBy;
  List<String> sharedWith; // names/labels the cost is split between
  String category;
  DateTime date;

  Expense({
    required this.id,
    required this.title,
    required this.amount,
    this.currency = 'INR',
    this.paidBy = 'Me',
    List<String>? sharedWith,
    this.category = 'General',
    DateTime? date,
  })  : sharedWith = sharedWith ?? const [],
        date = date ?? DateTime.now();

  /// Per-person share when split across [sharedWith] (falls back to the whole
  /// amount if nobody is selected).
  double get perPerson =>
      sharedWith.isEmpty ? amount : amount / sharedWith.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'amount': amount,
        'currency': currency,
        'paidBy': paidBy,
        'sharedWith': sharedWith,
        'category': category,
        'date': date.toIso8601String(),
      };

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id: j['id'].toString(),
        title: (j['title'] ?? '').toString(),
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        currency: (j['currency'] ?? 'INR').toString(),
        paidBy: (j['paidBy'] ?? 'Me').toString(),
        sharedWith:
            (j['sharedWith'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        category: (j['category'] ?? 'General').toString(),
        date: DateTime.tryParse((j['date'] ?? '').toString()) ?? DateTime.now(),
      );
}

/// One item within a day in the day-by-day organizer.
class PlanItem {
  final String id;
  String text;
  PlanItem({required this.id, this.text = ''});

  Map<String, dynamic> toJson() => {'id': id, 'text': text};
  factory PlanItem.fromJson(Map<String, dynamic> j) =>
      PlanItem(id: j['id'].toString(), text: (j['text'] ?? '').toString());
}

/// A single day in the day-by-day organizer, holding an ordered list of items
/// the traveller can reorder (drag-and-drop).
class PlanDay {
  final String id;
  String title;
  List<PlanItem> items;
  PlanDay({required this.id, this.title = '', List<PlanItem>? items})
      : items = items ?? [];

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'items': items.map((e) => e.toJson()).toList()};
  factory PlanDay.fromJson(Map<String, dynamic> j) => PlanDay(
        id: j['id'].toString(),
        title: (j['title'] ?? '').toString(),
        items: (j['items'] as List?)
                ?.map((e) => PlanItem.fromJson((e as Map).cast<String, dynamic>()))
                .toList() ??
            [],
      );
}

/// A dated journal entry for the trip (notes / memories, one per moment).
class JournalEntry {
  final String id;
  String title;
  String body;
  DateTime date;

  JournalEntry({
    required this.id,
    this.title = '',
    this.body = '',
    DateTime? date,
  }) : date = date ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'date': date.toIso8601String(),
      };

  factory JournalEntry.fromJson(Map<String, dynamic> j) => JournalEntry(
        id: j['id'].toString(),
        title: (j['title'] ?? '').toString(),
        body: (j['body'] ?? '').toString(),
        date: DateTime.tryParse((j['date'] ?? '').toString()) ?? DateTime.now(),
      );
}

/// A booking: flight, stay, restaurant, activity, or other.
class Reservation {
  final String id;
  String type; // flight | hotel | restaurant | activity | other
  String title;
  String confirmation;
  DateTime? date;
  String notes;

  Reservation({
    required this.id,
    this.type = 'hotel',
    required this.title,
    this.confirmation = '',
    this.date,
    this.notes = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'confirmation': confirmation,
        'date': date?.toIso8601String(),
        'notes': notes,
      };

  factory Reservation.fromJson(Map<String, dynamic> j) => Reservation(
        id: j['id'].toString(),
        type: (j['type'] ?? 'hotel').toString(),
        title: (j['title'] ?? '').toString(),
        confirmation: (j['confirmation'] ?? '').toString(),
        date: (j['date'] == null || j['date'].toString().isEmpty)
            ? null
            : DateTime.tryParse(j['date'].toString()),
        notes: (j['notes'] ?? '').toString(),
      );
}
