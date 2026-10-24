import 'cancellation.dart';

class Slot {
  const Slot({required this.staffId, required this.start, required this.end});

  final String staffId;
  final DateTime start;
  final DateTime end;

  factory Slot.fromMap(Map<String, dynamic> m) => Slot(
        staffId: m['staff_id'] as String,
        start: DateTime.parse(m['slot_start'] as String),
        end: DateTime.parse(m['slot_end'] as String),
      );
}

class Booking {
  const Booking({
    required this.id,
    required this.serviceId,
    required this.serviceTitle,
    required this.startsAt,
    required this.quantity,
    required this.status,
    required this.totalCents,
    required this.expiresAt,
    this.refundCents = 0,
    this.refundState,
    this.freeCancelHours = 24,
    this.lateRefundPct = 0,
  });

  final String id;
  final String serviceId;
  final String? serviceTitle;
  final DateTime startsAt;
  final int quantity;
  final String status;
  final int totalCents;
  final DateTime? expiresAt;
  final int refundCents;
  final RefundState? refundState;
  final int freeCancelHours;
  final int lateRefundPct;

  bool get isUnpaid => status == 'held' || status == 'pending_payment';

  /// Paid and not started yet, so the customer can still cancel and get the policy's refund.
  bool get canCancelPaid => status == 'confirmed' && startsAt.isAfter(DateTime.now());

  factory Booking.fromMap(Map<String, dynamic> m) => Booking(
        id: m['id'] as String,
        serviceId: m['service_id'] as String,
        serviceTitle: (m['services'] as Map<String, dynamic>?)?['title'] as String?,
        startsAt: DateTime.parse(m['starts_at'] as String),
        quantity: m['quantity'] as int,
        status: m['status'] as String,
        totalCents: (m['total_cents'] as num).toInt(),
        expiresAt: m['expires_at'] == null ? null : DateTime.parse(m['expires_at'] as String),
        refundCents: (m['refund_cents'] as num?)?.toInt() ?? 0,
        refundState: RefundState.fromStatuses([
          for (final p in (m['payments'] as List?) ?? const [])
            for (final r in ((p as Map<String, dynamic>)['refunds'] as List?) ?? const []) (r as Map<String, dynamic>)['status'] as String,
        ]),
        freeCancelHours: ((m['services'] as Map<String, dynamic>?)?['free_cancel_hours'] as num?)?.toInt() ?? 24,
        lateRefundPct: ((m['services'] as Map<String, dynamic>?)?['late_refund_pct'] as num?)?.toInt() ?? 0,
      );
}
