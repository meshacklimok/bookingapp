import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';

class OrgMembership {
  const OrgMembership({required this.orgId, required this.orgName, required this.role});

  final String orgId;
  final String? orgName;
  final String role;

  factory OrgMembership.fromMap(Map<String, dynamic> m) => OrgMembership(
        orgId: m['org_id'] as String,
        orgName: (m['organizations'] as Map<String, dynamic>?)?['name'] as String?,
        role: m['role'] as String,
      );
}

class OrgBooking {
  const OrgBooking({
    required this.id,
    required this.serviceTitle,
    required this.customerName,
    required this.startsAt,
    required this.status,
    required this.totalCents,
    required this.earningsCents,
  });

  final String id;
  final String? serviceTitle;
  final String? customerName;
  final DateTime startsAt;
  final String status;
  final int totalCents;
  final int? earningsCents;

  factory OrgBooking.fromMap(Map<String, dynamic> m) => OrgBooking(
        id: m['id'] as String,
        serviceTitle: (m['services'] as Map<String, dynamic>?)?['title'] as String?,
        customerName: (m['profiles'] as Map<String, dynamic>?)?['full_name'] as String?,
        startsAt: DateTime.parse(m['starts_at'] as String),
        status: m['status'] as String,
        totalCents: (m['total_cents'] as num).toInt(),
        earningsCents: (m['org_earnings_cents'] as num?)?.toInt(),
      );
}

class OrgRepository {
  OrgRepository(this._client);

  final SupabaseClient _client;

  Future<List<OrgMembership>> memberships() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];
    final rows = await _client.from('org_members').select('org_id, role, organizations(name)').eq('user_id', userId);
    return rows.map(OrgMembership.fromMap).toList();
  }

  Future<List<OrgBooking>> bookings(String orgId) async {
    final rows = await _client
        .from('bookings')
        .select('id, starts_at, status, total_cents, org_earnings_cents, services(title), profiles(full_name)')
        .eq('org_id', orgId)
        .neq('status', 'held')
        .order('starts_at', ascending: false)
        .limit(100);
    return rows.map(OrgBooking.fromMap).toList();
  }

  Future<void> setOutcome(String bookingId, String status) =>
      _client.rpc('set_booking_outcome', params: {'p_booking_id': bookingId, 'p_status': status});
}

final orgRepositoryProvider = Provider((ref) => OrgRepository(ref.watch(supabaseProvider)));

final membershipsProvider = FutureProvider.autoDispose<List<OrgMembership>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(orgRepositoryProvider).memberships();
});

final orgBookingsProvider = FutureProvider.autoDispose.family<List<OrgBooking>, String>(
  (ref, orgId) => ref.watch(orgRepositoryProvider).bookings(orgId),
);
