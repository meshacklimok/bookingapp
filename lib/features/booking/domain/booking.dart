import '../../discover/domain/service.dart' show BookingMode;
import 'cancellation.dart';

class Slot {
  const Slot({required this.staffId, required this.start, required this.end});

  /// Null for resources, which have no staff.
  final String? staffId;
  final DateTime start;
  final DateTime end;

  factory Slot.fromMap(Map<String, dynamic> m) => Slot(
        staffId: m['staff_id'] as String?,
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
    this.discountCents = 0,
    this.balanceCents = 0,
    this.balancePaid = false,
    this.reviewRating,
    this.endsAt,
    this.mode = BookingMode.appointment,
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
  final int discountCents;

  /// Still to pay at the venue after a deposit; [totalCents] is what is paid online.
  final int balanceCents;
  final bool balancePaid;

  /// The customer's own star rating for this booking, once they left one.
  final int? reviewRating;
  final DateTime? endsAt;
  final BookingMode mode;

  /// Paid, not started, still inside the free-cancellation window, and a kind of booking that has slots to move to.
  bool canReschedule(DateTime now) =>
      status == 'confirmed' &&
      mode != BookingMode.event &&
      !startsAt.subtract(Duration(hours: freeCancelHours)).isBefore(now);

  /// Left to pay at the venue.
  int get balanceDueCents => balancePaid ? 0 : balanceCents;

  /// Price before any deposit split (promo discounts already taken off).
  int get fullPriceCents => totalCents + balanceCents;

  bool get isUnpaid => status == 'held' || status == 'pending_payment';

  /// Paid and not started yet, so the customer can still cancel and get the policy's refund.
  bool get canCancelPaid => status == 'confirmed' && startsAt.isAfter(DateTime.now());

  /// Paid for and over, so the customer can leave (or change) a review.
  bool get canReview =>
      (status == 'confirmed' || status == 'completed') && (endsAt ?? startsAt).isBefore(DateTime.now());

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
        discountCents: (m['discount_cents'] as num?)?.toInt() ?? 0,
        balanceCents: (m['balance_cents'] as num?)?.toInt() ?? 0,
        balancePaid: m['balance_paid_at'] != null,
        reviewRating: _ratingOf(m['reviews']),
        mode: BookingMode.parse(((m['services'] as Map<String, dynamic>?)?['booking_mode'] as String?) ?? 'appointment'),
        endsAt: m['ends_at'] == null ? null : DateTime.parse(m['ends_at'] as String),
      );
}

// A one-to-one embed comes back as a map, a to-many embed as a list; accept both.
int? _ratingOf(Object? embed) {
  final row = embed is List ? (embed.isEmpty ? null : embed.first) : embed;
  return row is Map<String, dynamic> ? (row['rating'] as num?)?.toInt() : null;
}
