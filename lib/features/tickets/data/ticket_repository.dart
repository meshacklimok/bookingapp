import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';

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

class TicketRepository {
  TicketRepository(this._client);

  final SupabaseClient _client;

  static const _columns = 'id, qr_token, status, bookings(starts_at, services(title))';

  Future<List<TicketInfo>> mine() async {
    final rows = await _client
        .from('tickets')
        .select(_columns)
        .eq('customer_id', _client.auth.currentUser!.id)
        .order('created_at', ascending: false);
    return rows.map(TicketInfo.fromMap).toList();
  }

  Future<TicketInfo> get(String id) async {
    final row = await _client.from('tickets').select(_columns).eq('id', id).single();
    return TicketInfo.fromMap(row);
  }

  /// Staff check-in. Returns the backend verdict: ok, already_used, invalid, void or forbidden.
  Future<Map<String, dynamic>> verify(String qrToken) async {
    final res = await _client.rpc('verify_ticket', params: {'p_qr_token': qrToken});
    return Map<String, dynamic>.from(res as Map);
  }
}

final ticketRepositoryProvider = Provider((ref) => TicketRepository(ref.watch(supabaseProvider)));

final myTicketsProvider = FutureProvider.autoDispose<List<TicketInfo>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(ticketRepositoryProvider).mine();
});

final ticketProvider = FutureProvider.autoDispose.family<TicketInfo, String>(
  (ref, id) => ref.watch(ticketRepositoryProvider).get(id),
);
