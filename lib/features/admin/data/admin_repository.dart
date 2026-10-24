import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../org_dashboard/domain/payouts.dart';
import '../domain/admin.dart';

/// Everything here is guarded in the database: row-level security and the `is_platform_admin()` checks inside the
/// functions. The app only hides the entry point from other users.
class AdminRepository {
  AdminRepository(this._client);

  final SupabaseClient _client;

  Future<List<AdminOrg>> organizations() async {
    final rows = await _client.from('organizations').select('id, name, status, category, created_at');
    return sortAdminOrgs(rows.map(AdminOrg.fromMap).toList());
  }

  /// `.single()` turns a row-level-security refusal (zero rows updated) into an error instead of a silent no-op.
  Future<void> setOrgStatus(String orgId, String status) =>
      _client.from('organizations').update({'status': status}).eq('id', orgId).select('id').single();

  Future<List<AdminRefund>> refunds() async {
    final rows = await _client
        .from('refunds')
        .select('id, amount_cents, reason, status, created_at, payments(provider, phone, reference, profiles(full_name), bookings(services(title)))')
        .order('created_at', ascending: false)
        .limit(100);
    final refunds = rows.map(AdminRefund.fromMap).toList();
    // pending ones first so they are not buried under history
    refunds.sort((a, b) => a.isPending == b.isPending ? 0 : (a.isPending ? -1 : 1));
    return refunds;
  }

  /// Sends a pending Paystack refund through the provider. Throws with the provider's message when it fails.
  Future<void> sendRefund(String refundId) async {
    final res = await _client.functions.invoke('process-refund', body: {'refund_id': refundId});
    final results = (res.data as Map?)?['results'] as List? ?? const [];
    for (final r in results) {
      final error = (r as Map)['error'];
      if (error != null) throw Exception(error);
    }
  }

  Future<void> resolveRefund(String refundId, {required bool processed, String? providerRef}) => _client.rpc('resolve_refund', params: {
        'p_refund_id': refundId,
        'p_status': processed ? 'processed' : 'failed',
        if (providerRef != null && providerRef.isNotEmpty) 'p_provider_ref': providerRef,
      });

  Future<List<AdminBalance>> balances() async {
    final rows = await _client.rpc('admin_org_balances') as List;
    return [for (final r in rows) AdminBalance.fromMap(r as Map<String, dynamic>)];
  }

  Future<void> recordPayout(String orgId, int amountCents, PayoutMethod method, {String? reference, String? note}) =>
      _client.rpc('record_payout', params: {
        'p_org_id': orgId,
        'p_amount_cents': amountCents,
        'p_method': method.name,
        'p_reference': reference,
        'p_note': note,
      });

  Future<List<AdminCommission>> commissions() async {
    final rows = await _client.rpc('admin_commissions') as List;
    return [for (final r in rows) AdminCommission.fromMap(r as Map<String, dynamic>)];
  }

  Future<void> setCommission(String scope, String? scopeId, double pct) =>
      _client.rpc('set_commission', params: {'p_scope': scope, 'p_scope_id': scopeId, 'p_pct': pct});

  Future<void> clearCommission(String scope, String scopeId) =>
      _client.rpc('clear_commission', params: {'p_scope': scope, 'p_scope_id': scopeId});
}

final adminRepositoryProvider = Provider((ref) => AdminRepository(ref.watch(supabaseProvider)));

final adminOrgsProvider = FutureProvider.autoDispose<List<AdminOrg>>((ref) => ref.watch(adminRepositoryProvider).organizations());
final adminRefundsProvider = FutureProvider.autoDispose<List<AdminRefund>>((ref) => ref.watch(adminRepositoryProvider).refunds());
final adminBalancesProvider = FutureProvider.autoDispose<List<AdminBalance>>((ref) => ref.watch(adminRepositoryProvider).balances());
final adminCommissionsProvider = FutureProvider.autoDispose<List<AdminCommission>>((ref) => ref.watch(adminRepositoryProvider).commissions());
