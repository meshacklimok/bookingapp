import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import 'ticket_cache.dart';

class TicketInfo {
  const TicketInfo({
    required this.id,
    required this.qrToken,
    required this.status,
    required this.serviceTitle,
    required this.startsAt,
  });

  final String id;
  final String qrToken;
  final String status;
  final String? serviceTitle;
  final DateTime? startsAt;

  factory TicketInfo.fromMap(Map<String, dynamic> m) {
    final booking = m['bookings'] as Map<String, dynamic>?;
    return TicketInfo(
      id: m['id'] as String,
      qrToken: m['qr_token'] as String,
      status: m['status'] as String,
      serviceTitle: (booking?['services'] as Map<String, dynamic>?)?['title'] as String?,
      startsAt: booking?['starts_at'] == null ? null : DateTime.parse(booking!['starts_at'] as String),
    );
  }
}

/// Tickets to show, and when they were saved if they came from the device instead of the server.
class TicketWallet {
  const TicketWallet(this.tickets, {this.savedAt});

  final List<TicketInfo> tickets;
  final DateTime? savedAt;

  bool get isSavedCopy => savedAt != null;
}

/// Loads [fetch] and saves it; when that fails, falls back to the saved copy (or rethrows if there is none).
Future<TicketWallet> loadWallet({
  required String userId,
  required Future<List<Map<String, dynamic>>> Function() fetch,
  required TicketCache cache,
}) async {
  final List<Map<String, dynamic>> rows;
  try {
    rows = await fetch();
  } catch (_) {
    final saved = await cache.load(userId);
    if (saved == null) rethrow;
    return TicketWallet(saved.rows.map(TicketInfo.fromMap).toList(), savedAt: saved.savedAt);
  }
  try {
    await cache.save(userId, rows);
  } catch (_) {
    // A full or broken disk only costs the offline copy.
  }
  return TicketWallet(rows.map(TicketInfo.fromMap).toList());
}

class TicketRepository {
  TicketRepository(this._client, this._cache);

  final SupabaseClient _client;
  final TicketCache _cache;

  static const _columns = 'id, qr_token, status, bookings(starts_at, services(title))';

  Future<TicketWallet> mine() {
    final userId = _client.auth.currentUser!.id;
    return loadWallet(
      userId: userId,
      cache: _cache,
      fetch: () =>
          _client.from('tickets').select(_columns).eq('customer_id', userId).order('created_at', ascending: false),
    );
  }

  /// One ticket, from the saved wallet when the server cannot be reached.
  Future<({TicketInfo ticket, bool isSavedCopy})> get(String id) async {
    try {
      final row = await _client.from('tickets').select(_columns).eq('id', id).single();
      return (ticket: TicketInfo.fromMap(row), isSavedCopy: false);
    } catch (_) {
      final saved = await _cache.load(_client.auth.currentUser!.id);
      final row = saved?.rows.where((r) => r['id'] == id).firstOrNull;
      if (row == null) rethrow;
      return (ticket: TicketInfo.fromMap(row), isSavedCopy: true);
    }
  }

  /// Staff check-in. Returns the backend verdict: ok, already_used, invalid, void or forbidden.
  Future<Map<String, dynamic>> verify(String qrToken) async {
    final res = await _client.rpc('verify_ticket', params: {'p_qr_token': qrToken});
    return Map<String, dynamic>.from(res as Map);
  }
}

final ticketCacheProvider = Provider((ref) => TicketCache());

final ticketRepositoryProvider =
    Provider((ref) => TicketRepository(ref.watch(supabaseProvider), ref.watch(ticketCacheProvider)));

final myTicketsProvider = FutureProvider.autoDispose<TicketWallet>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(ticketRepositoryProvider).mine();
});

final ticketProvider = FutureProvider.autoDispose.family<({TicketInfo ticket, bool isSavedCopy}), String>(
  (ref, id) => ref.watch(ticketRepositoryProvider).get(id),
);
