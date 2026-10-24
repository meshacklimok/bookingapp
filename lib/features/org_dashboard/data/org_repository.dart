import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../discover/domain/service.dart';
import '../domain/earnings.dart';
import '../domain/managed_service.dart';
import '../domain/organization.dart';
import '../domain/payouts.dart';
import '../domain/staff.dart';
import '../../../core/utils/formatters.dart';

class OrgMembership {
  const OrgMembership({required this.orgId, required this.orgName, required this.role, this.status = OrgStatus.approved});

  final String orgId;
  final String? orgName;
  final String role;
  final OrgStatus status;

  factory OrgMembership.fromMap(Map<String, dynamic> m) => OrgMembership(
        orgId: m['org_id'] as String,
        orgName: (m['organizations'] as Map<String, dynamic>?)?['name'] as String?,
        role: m['role'] as String,
        status: OrgStatus.parse((m['organizations'] as Map<String, dynamic>?)?['status'] as String?),
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

/// Everything the staff detail screen shows about one person in one organization.
class StaffSchedule {
  const StaffSchedule({required this.serviceIds, required this.hours, required this.exceptions});

  final Set<String> serviceIds;
  final WeeklyHours hours;
  final List<DayException> exceptions;
}

class OrgRepository {
  OrgRepository(this._client);

  final SupabaseClient _client;

  Future<List<OrgMembership>> memberships() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];
    final rows = await _client.from('org_members').select('org_id, role, organizations(name, status)').eq('user_id', userId);
    return rows.map(OrgMembership.fromMap).toList();
  }

  Future<Organization> organization(String orgId) async {
    final row = await _client
        .from('organizations')
        .select('id, name, slug, description, category, status')
        .eq('id', orgId)
        .single();
    return Organization.fromMap(row);
  }

  /// Registers an organization for the signed-in user. The database creates it as `pending` and adds the
  /// user as owner; a platform admin approves it later. A slug clash is retried with a short random suffix.
  Future<Organization> register({required String name, String? description, String? category}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('not signed in');
    final base = slugify(name);
    for (var attempt = 0;; attempt++) {
      try {
        final row = await _client
            .from('organizations')
            .insert({
              'name': name.trim(),
              'slug': attempt == 0 ? base : '$base-${_suffix()}',
              'description': description,
              'category': category,
              'created_by': userId,
            })
            .select('id, name, slug, description, category, status')
            .single();
        return Organization.fromMap(row);
      } on PostgrestException catch (e) {
        if (e.code != '23505' || attempt >= 3) rethrow;
      }
    }
  }

  static final _random = Random.secure();
  static const _alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';
  static String _suffix() => List.generate(4, (_) => _alphabet[_random.nextInt(_alphabet.length)]).join();

  Future<List<ManagedService>> services(String orgId) async {
    final rows = await _client.from('services').select().eq('org_id', orgId).order('created_at', ascending: false);
    return rows.map(ManagedService.fromMap).toList();
  }

  Future<ManagedService> service(String serviceId) async {
    final row = await _client.from('services').select().eq('id', serviceId).single();
    return ManagedService.fromMap(row);
  }

  Future<List<TicketTier>> tiers(String serviceId) async {
    final rows = await _client.from('ticket_tiers').select().eq('service_id', serviceId).order('price_cents');
    return rows.map(TicketTier.fromMap).toList();
  }

  /// Creates the service, or updates it when [serviceId] is given. Returns its id.
  Future<String> saveService(String orgId, ServiceDraft draft, {String? serviceId}) async {
    final values = draft.toMap(orgId);
    if (serviceId == null) {
      final row = await _client.from('services').insert(values).select('id').single();
      return row['id'] as String;
    }
    // org_id never changes after creation
    values.remove('org_id');
    // .single() makes a row-level-security refusal (zero rows updated) an error instead of a silent no-op
    await _client.from('services').update(values).eq('id', serviceId).select('id').single();
    return serviceId;
  }

  /// Services are deactivated rather than deleted because bookings reference them.
  Future<void> setServiceActive(String serviceId, bool active) =>
      _client.from('services').update({'is_active': active}).eq('id', serviceId).select('id').single();

  /// Makes the saved tiers match [edited]. Writes are not atomic; the form retries from the saved service.
  Future<void> syncTiers(String serviceId, List<TicketTier> saved, List<TierDraft> edited) async {
    final changes = diffTiers(saved, edited);
    for (final id in changes.deletes) {
      await _client.from('ticket_tiers').delete().eq('id', id);
    }
    for (final t in changes.updates) {
      await _client.from('ticket_tiers').update(t.toMap(serviceId)..remove('service_id')).eq('id', t.id!);
    }
    if (changes.inserts.isNotEmpty) {
      await _client.from('ticket_tiers').insert([for (final t in changes.inserts) t.toMap(serviceId)]);
    }
  }

  Future<List<OrgStaff>> staff(String orgId) async {
    final rows = await _client.from('org_members').select('user_id, role, profiles(full_name)').eq('org_id', orgId);
    final staff = rows.map(OrgStaff.fromMap).toList();
    // owners first, then by name
    staff.sort((a, b) {
      if (a.isOwner != b.isOwner) return a.isOwner ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return staff;
  }

  /// The person must already have an account. Throws `user_not_found` / `already_member` otherwise.
  Future<void> addStaff(String orgId, String email) =>
      _client.rpc('add_org_staff', params: {'p_org_id': orgId, 'p_email': email.trim()});

  /// Switches a member between `staff` and `admin`. Owners cannot be changed here; row-level security enforces it.
  Future<void> setMemberRole(String orgId, String userId, String role) async {
    final updated = await _client
        .from('org_members')
        .update({'role': role})
        .eq('org_id', orgId)
        .eq('user_id', userId)
        .neq('role', 'owner')
        .select('user_id');
    if (updated.isEmpty) throw StateError('forbidden');
  }

  /// Also clears their service links and hours for this org; refused while they have upcoming bookings.
  Future<void> removeStaff(String orgId, String userId) async {
    final removed = await _client.from('org_members').delete().eq('org_id', orgId).eq('user_id', userId).select('user_id');
    if (removed.isEmpty) throw StateError('forbidden');
  }

  Future<StaffSchedule> schedule(String orgId, String staffId) async {
    final today = formatIsoDate(DateTime.now());
    final results = await Future.wait([
      _client.from('staff_services').select('service_id, services(org_id)').eq('staff_id', staffId),
      _client.from('availability_rules').select('weekday, start_time, end_time').eq('org_id', orgId).eq('staff_id', staffId),
      _client
          .from('availability_exceptions')
          .select('id, date, is_closed, start_time, end_time')
          .eq('org_id', orgId)
          .eq('staff_id', staffId)
          .gte('date', today)
          .order('date'),
    ]);
    return StaffSchedule(
      // a person can work for several organizations; keep only links to this one's services
      serviceIds: {
        for (final r in results[0])
          if ((r['services'] as Map<String, dynamic>?)?['org_id'] == orgId) r['service_id'] as String,
      },
      hours: weeklyHoursFromRows(results[1]),
      exceptions: results[2].map(DayException.fromMap).toList(),
    );
  }

  Future<void> linkService(String staffId, String serviceId) =>
      _client.from('staff_services').insert({'staff_id': staffId, 'service_id': serviceId});

  Future<void> unlinkService(String staffId, String serviceId) =>
      _client.from('staff_services').delete().eq('staff_id', staffId).eq('service_id', serviceId);

  /// Replaces the staff member's weekly hours in a single transaction.
  Future<void> setHours(String orgId, String staffId, WeeklyHours hours) => _client.rpc('set_staff_hours', params: {
        'p_org_id': orgId,
        'p_staff_id': staffId,
        'p_rules': weeklyHoursToPayload(hours),
      });

  Future<void> saveException(String orgId, String staffId, DateTime date, {TimeWindow? window}) =>
      _client.from('availability_exceptions').upsert(
            exceptionToRow(orgId: orgId, staffId: staffId, isoDate: formatIsoDate(date), window: window),
            onConflict: 'org_id,staff_id,date',
          );

  Future<void> deleteException(String id) => _client.from('availability_exceptions').delete().eq('id', id);

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

  Future<EarningsSummary> earningsSummary(String orgId, EarningsPeriod period) async {
    final (from, to) = period.range(DateTime.now());
    final rows = await _client.rpc('org_earnings_summary', params: {'p_org_id': orgId, 'p_from': from, 'p_to': to});
    return EarningsSummary.fromMap((rows as List).single as Map<String, dynamic>);
  }

  Future<List<EarningsRow>> earningsRows(String orgId, EarningsPeriod period) async {
    final (from, to) = period.range(DateTime.now());
    final rows = await _client.rpc('org_earnings_rows', params: {'p_org_id': orgId, 'p_from': from, 'p_to': to});
    return [for (final r in rows as List) EarningsRow.fromMap(r as Map<String, dynamic>)];
  }

  Future<OrgBalance> balance(String orgId) async {
    final rows = await _client.rpc('org_balance', params: {'p_org_id': orgId});
    return OrgBalance.fromMap((rows as List).single as Map<String, dynamic>);
  }

  Future<List<Payout>> payouts(String orgId) async {
    final rows = await _client.from('payouts').select().eq('org_id', orgId).order('created_at', ascending: false);
    return rows.map(Payout.fromMap).toList();
  }

  Future<void> setOutcome(String bookingId, String status) =>
      _client.rpc('set_booking_outcome', params: {'p_booking_id': bookingId, 'p_status': status});
}

final orgRepositoryProvider = Provider((ref) => OrgRepository(ref.watch(supabaseProvider)));

final membershipsProvider = FutureProvider.autoDispose<List<OrgMembership>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(orgRepositoryProvider).memberships();
});

final organizationProvider = FutureProvider.autoDispose.family<Organization, String>(
  (ref, orgId) => ref.watch(orgRepositoryProvider).organization(orgId),
);

final orgServicesProvider = FutureProvider.autoDispose.family<List<ManagedService>, String>(
  (ref, orgId) => ref.watch(orgRepositoryProvider).services(orgId),
);

/// A service with its ticket tiers, for the edit form.
final serviceEditorProvider = FutureProvider.autoDispose.family<(ManagedService, List<TicketTier>), String>((ref, serviceId) async {
  final repo = ref.watch(orgRepositoryProvider);
  final (service, tiers) = await (repo.service(serviceId), repo.tiers(serviceId)).wait;
  return (service, tiers);
});

final orgStaffProvider = FutureProvider.autoDispose.family<List<OrgStaff>, String>(
  (ref, orgId) => ref.watch(orgRepositoryProvider).staff(orgId),
);

final staffScheduleProvider = FutureProvider.autoDispose.family<StaffSchedule, (String, String)>(
  (ref, key) => ref.watch(orgRepositoryProvider).schedule(key.$1, key.$2),
);

final orgBookingsProvider = FutureProvider.autoDispose.family<List<OrgBooking>, String>(
  (ref, orgId) => ref.watch(orgRepositoryProvider).bookings(orgId),
);

final earningsSummaryProvider = FutureProvider.autoDispose.family<EarningsSummary, (String, EarningsPeriod)>(
  (ref, key) => ref.watch(orgRepositoryProvider).earningsSummary(key.$1, key.$2),
);

final earningsRowsProvider = FutureProvider.autoDispose.family<List<EarningsRow>, (String, EarningsPeriod)>(
  (ref, key) => ref.watch(orgRepositoryProvider).earningsRows(key.$1, key.$2),
);

final orgBalanceProvider = FutureProvider.autoDispose.family<OrgBalance, String>(
  (ref, orgId) => ref.watch(orgRepositoryProvider).balance(orgId),
);

final orgPayoutsProvider = FutureProvider.autoDispose.family<List<Payout>, String>(
  (ref, orgId) => ref.watch(orgRepositoryProvider).payouts(orgId),
);
