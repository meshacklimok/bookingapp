/// How a payout was sent. Matches the `payouts.method` check constraint.
enum PayoutMethod {
  mpesa('M-Pesa'),
  bank('Bank transfer'),
  other('Other');

  const PayoutMethod(this.label);

  final String label;

  static PayoutMethod parse(String? value) => PayoutMethod.values.firstWhere((m) => m.name == value, orElse: () => PayoutMethod.other);
}

/// What the platform owes an organization. [payableCents] is settled earnings minus payouts already made;
/// [upcomingCents] is earned on bookings that have not happened yet and can still be refunded.
class OrgBalance {
  const OrgBalance({required this.payableCents, required this.upcomingCents, required this.paidOutCents});

  final int payableCents;
  final int upcomingCents;
  final int paidOutCents;

  factory OrgBalance.fromMap(Map<String, dynamic> m) => OrgBalance(
        payableCents: (m['payable_cents'] as num).toInt(),
        upcomingCents: (m['upcoming_cents'] as num).toInt(),
        paidOutCents: (m['paid_out_cents'] as num).toInt(),
      );
}

class Payout {
  const Payout({required this.id, required this.amountCents, required this.method, required this.createdAt, this.reference, this.note});

  final String id;
  final int amountCents;
  final PayoutMethod method;
  final DateTime createdAt;
  final String? reference;
  final String? note;

  factory Payout.fromMap(Map<String, dynamic> m) => Payout(
        id: m['id'] as String,
        amountCents: (m['amount_cents'] as num).toInt(),
        method: PayoutMethod.parse(m['method'] as String?),
        createdAt: DateTime.parse(m['created_at'] as String),
        reference: m['reference'] as String?,
        note: m['note'] as String?,
      );
}
