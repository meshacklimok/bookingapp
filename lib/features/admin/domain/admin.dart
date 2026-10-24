import '../../org_dashboard/domain/organization.dart';
import '../../org_dashboard/domain/payouts.dart';

class AdminOrg {
  const AdminOrg({required this.id, required this.name, required this.status, required this.createdAt, this.category});

  final String id;
  final String name;
  final OrgStatus status;
  final DateTime createdAt;
  final String? category;

  factory AdminOrg.fromMap(Map<String, dynamic> m) => AdminOrg(
        id: m['id'] as String,
        name: m['name'] as String,
        status: OrgStatus.parse(m['status'] as String?),
        createdAt: DateTime.parse(m['created_at'] as String),
        category: m['category'] as String?,
      );
}

/// Pending organizations first (they need a decision), then by name.
List<AdminOrg> sortAdminOrgs(List<AdminOrg> orgs) => [...orgs]..sort((a, b) {
    final pa = a.status == OrgStatus.pending ? 0 : 1;
    final pb = b.status == OrgStatus.pending ? 0 : 1;
    if (pa != pb) return pa - pb;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

class AdminBalance {
  const AdminBalance({required this.orgId, required this.orgName, required this.balance});

  final String orgId;
  final String orgName;
  final OrgBalance balance;

  factory AdminBalance.fromMap(Map<String, dynamic> m) =>
      AdminBalance(orgId: m['org_id'] as String, orgName: m['org_name'] as String, balance: OrgBalance.fromMap(m));
}

class AdminRefund {
  const AdminRefund({
    required this.id,
    required this.amountCents,
    required this.status,
    required this.createdAt,
    this.reason,
    this.customerName,
    this.phone,
    this.provider,
    this.reference,
    this.serviceTitle,
  });

  final String id;
  final int amountCents;
  final String status;
  final DateTime createdAt;
  final String? reason;
  final String? customerName;
  final String? phone;
  final String? provider;
  final String? reference;
  final String? serviceTitle;

  bool get isPending => status == 'pending';

  /// Sent to the provider and waiting for its answer.
  bool get isProcessing => status == 'processing';

  /// Paystack refunds can be sent from the app; M-Pesa ones are sent by hand.
  bool get canSendAutomatically => isPending && provider == 'paystack';

  factory AdminRefund.fromMap(Map<String, dynamic> m) {
    final payment = m['payments'] as Map<String, dynamic>?;
    return AdminRefund(
      id: m['id'] as String,
      amountCents: (m['amount_cents'] as num).toInt(),
      status: m['status'] as String,
      createdAt: DateTime.parse(m['created_at'] as String),
      reason: m['reason'] as String?,
      customerName: (payment?['profiles'] as Map<String, dynamic>?)?['full_name'] as String?,
      phone: payment?['phone'] as String?,
      provider: payment?['provider'] as String?,
      reference: payment?['reference'] as String?,
      serviceTitle: ((payment?['bookings'] as Map<String, dynamic>?)?['services'] as Map<String, dynamic>?)?['title'] as String?,
    );
  }
}

class AdminCommission {
  const AdminCommission({required this.scope, required this.scopeId, required this.name, required this.pct});

  final String scope;
  final String? scopeId;
  final String? name;
  final double pct;

  bool get isPlatform => scope == 'platform';

  factory AdminCommission.fromMap(Map<String, dynamic> m) => AdminCommission(
        scope: m['scope'] as String,
        scopeId: m['scope_id'] as String?,
        name: m['name'] as String?,
        pct: (m['pct'] as num).toDouble(),
      );
}

/// Accepts "12", "12.5" or "12,5" and returns a rate between 0 and 100 with at most two decimals, else null.
double? parseCommissionPct(String input) {
  final cleaned = input.trim().replaceAll(',', '.').replaceAll('%', '');
  if (!RegExp(r'^\d{1,3}(\.\d{1,2})?$').hasMatch(cleaned)) return null;
  final v = double.parse(cleaned);
  return v > 100 ? null : v;
}
