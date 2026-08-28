import 'dart:async';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A cloud-stored, shareable trip (day-by-day itinerary or one-way plan).
class SharedTrip {
  final String id;
  final String ownerId;
  final String tripType; // 'itinerary' | 'oneway'
  final String name;
  final String shareCode;
  final bool isPublic;
  final List<String> collaborators;
  final Map<String, dynamic> data;
  final DateTime? updatedAt;
  final String? updatedBy;

  SharedTrip({
    required this.id,
    required this.ownerId,
    required this.tripType,
    required this.name,
    required this.shareCode,
    required this.isPublic,
    required this.collaborators,
    required this.data,
    this.updatedAt,
    this.updatedBy,
  });

  factory SharedTrip.fromRow(Map<String, dynamic> r) => SharedTrip(
        id: r['id'].toString(),
        ownerId: (r['owner_id'] ?? '').toString(),
        tripType: (r['trip_type'] ?? 'itinerary').toString(),
        name: (r['name'] ?? 'Shared trip').toString(),
        shareCode: (r['share_code'] ?? '').toString(),
        isPublic: r['is_public'] == true,
        collaborators: ((r['collaborators'] as List?) ?? const []).map((e) => e.toString()).toList(),
        data: ((r['data'] as Map?) ?? const {}).cast<String, dynamic>(),
        updatedAt: r['updated_at'] != null ? DateTime.tryParse(r['updated_at'].toString()) : null,
        updatedBy: r['updated_by']?.toString(),
      );

  /// Deep link / shareable URL for this trip.
  String get shareUrl => 'https://gowtham64.github.io/Travel-V1/app/?join=$shareCode';
}

/// Create/join/update/subscribe to collaborative trips backed by the
/// `shared_trips` Supabase table (see backend/supabase/shared_trips.sql).
class CollabService {
  SupabaseClient get _db => Supabase.instance.client;
  static const _table = 'shared_trips';

  String? get _uid => _db.auth.currentSession?.user.id;
  bool get isSignedIn => _uid != null;

  String _code() {
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// Push a trip to the cloud and get a shareable record back.
  Future<SharedTrip> createSharedTrip({
    required String tripType,
    required String name,
    required Map<String, dynamic> data,
    bool isPublic = true,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Sign in to share a trip.');
    final row = await _db
        .from(_table)
        .insert({
          'owner_id': uid,
          'trip_type': tripType,
          'name': name,
          'share_code': _code(),
          'is_public': isPublic,
          'data': data,
          'updated_by': uid,
        })
        .select()
        .single();
    return SharedTrip.fromRow(row);
  }

  /// Save new content to an existing shared trip (owner or collaborator).
  Future<void> updateData(String id, Map<String, dynamic> data) async {
    await _db.from(_table).update({'data': data, 'updated_by': _uid}).eq('id', id);
  }

  /// Load a trip by its share code. Works for public (view) or member (edit).
  Future<SharedTrip?> loadByCode(String code) async {
    final rows = await _db.from(_table).select().eq('share_code', code.trim().toUpperCase()).limit(1);
    if (rows.isEmpty) return null;
    return SharedTrip.fromRow((rows.first as Map).cast<String, dynamic>());
  }

  Future<SharedTrip?> loadById(String id) async {
    final rows = await _db.from(_table).select().eq('id', id).limit(1);
    if (rows.isEmpty) return null;
    return SharedTrip.fromRow((rows.first as Map).cast<String, dynamic>());
  }

  /// Join a trip as a collaborator (must be signed in) via its share code.
  Future<SharedTrip?> joinByCode(String code) async {
    if (_uid == null) throw Exception('Sign in to collaborate on a trip.');
    final id = await _db.rpc('join_trip', params: {'p_code': code.trim().toUpperCase()});
    if (id == null) return null;
    return loadById(id.toString());
  }

  /// Whether the current user can edit this trip.
  bool canEdit(SharedTrip t) => _uid != null && (t.ownerId == _uid || t.collaborators.contains(_uid));

  /// Trips owned by or shared with the current user.
  Future<List<SharedTrip>> myTrips() async {
    final uid = _uid;
    if (uid == null) return [];
    final rows = await _db
        .from(_table)
        .select()
        .or('owner_id.eq.$uid,collaborators.cs.{$uid}')
        .order('updated_at', ascending: false);
    return (rows as List).map((r) => SharedTrip.fromRow((r as Map).cast<String, dynamic>())).toList();
  }

  /// Subscribe to live changes on one trip. Returns the channel; call
  /// `channel.unsubscribe()` when done. `onData` fires with the new payload.
  RealtimeChannel subscribe(String id, void Function(Map<String, dynamic> data, String? updatedBy) onData) {
    final channel = _db.channel('shared_trip_$id');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: _table,
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: id),
          callback: (payload) {
            final rec = payload.newRecord;
            final data = ((rec['data'] as Map?) ?? const {}).cast<String, dynamic>();
            onData(data, rec['updated_by']?.toString());
          },
        )
        .subscribe();
    return channel;
  }
}
