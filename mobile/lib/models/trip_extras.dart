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
