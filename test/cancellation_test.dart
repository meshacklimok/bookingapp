import 'package:bookingapp/features/discover/domain/service.dart';
import 'package:bookingapp/features/booking/domain/booking.dart';
import 'package:bookingapp/features/booking/domain/cancellation.dart';
import 'package:bookingapp/features/org_dashboard/domain/earnings.dart';
import 'package:bookingapp/features/org_dashboard/domain/managed_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> bookingRow({String status = 'confirmed', DateTime? starts, Map<String, dynamic> extra = const {}}) => {
      'id': 'b1',
      'service_id': 's1',
      'starts_at': (starts ?? DateTime.now().add(const Duration(days: 3))).toUtc().toIso8601String(),
      'quantity': 1,
      'status': status,
      'total_cents': 100000,
      'expires_at': null,
      'services': {'title': 'Haircut', 'free_cancel_hours': 48, 'late_refund_pct': 25},
      ...extra,
    };

void main() {
  group('cancellationPolicyText', () {
    test('describes the free window and the late refund', () {
      expect(cancellationPolicyText(24, 50), 'Free cancellation until 24 hours before. After that, 50% is refunded.');
      expect(cancellationPolicyText(72, 0), 'Free cancellation until 3 days before. After that, no refund.');
      expect(cancellationPolicyText(168, 25), 'Free cancellation until 7 days before. After that, 25% is refunded.');
    });

    test('a zero window means free until the start, with nothing after', () {
      expect(cancellationPolicyText(0, 50), 'Free cancellation until it starts.');
    });
  });

  group('RefundState.fromStatuses', () {
    test('is null without refunds', () => expect(RefundState.fromStatuses(const []), isNull));
    test('failed beats pending beats processed', () {
      expect(RefundState.fromStatuses(['processed', 'pending']), RefundState.pending);
      expect(RefundState.fromStatuses(['processed', 'processing']), RefundState.pending);
      expect(RefundState.fromStatuses(['pending', 'failed']), RefundState.failed);
      expect(RefundState.fromStatuses(['processed']), RefundState.processed);
    });
  });

  group('Booking', () {
    test('reads the policy and the nested refund statuses', () {
      final b = Booking.fromMap(bookingRow(status: 'cancelled', extra: {
        'refund_cents': 50000,
        'payments': [
          {
            'refunds': [
              {'status': 'pending'}
            ]
          },
          {'refunds': []},
        ],
      }));
      expect((b.freeCancelHours, b.lateRefundPct, b.refundCents), (48, 25, 50000));
      expect(b.refundState, RefundState.pending);
    });

    test('only a paid, upcoming booking can be cancelled by the customer', () {
      expect(Booking.fromMap(bookingRow()).canCancelPaid, isTrue);
      expect(Booking.fromMap(bookingRow(starts: DateTime.now().subtract(const Duration(hours: 1)))).canCancelPaid, isFalse);
      expect(Booking.fromMap(bookingRow(status: 'cancelled')).canCancelPaid, isFalse);
      expect(Booking.fromMap(bookingRow(status: 'held')).canCancelPaid, isFalse);
    });

    test('defaults are safe when the policy is missing', () {
      final b = Booking.fromMap(bookingRow(extra: {'services': {'title': 'x'}}));
      expect((b.freeCancelHours, b.lateRefundPct, b.refundCents, b.refundState), (24, 0, 0, null));
    });
  });

  test('a service draft writes its cancellation policy', () {
    const draft = ServiceDraft(title: 'x', mode: BookingMode.appointment, freeCancelHours: 12, lateRefundPct: 75);
    final map = draft.toMap('o1');
    expect((map['free_cancel_hours'], map['late_refund_pct']), (12, 75));
  });

  test('earnings carry the refunded amount', () {
    final s = EarningsSummary.fromMap(
        {'booking_count': 1, 'gross_cents': 50000, 'commission_cents': 5000, 'net_cents': 45000, 'refunded_cents': 50000});
    expect(s.refundedCents, 50000);
  });

  test('CancellationQuote reads the database row', () {
    final q = CancellationQuote.fromMap({'refund_cents': 50000, 'full_refund': false, 'by_org': false});
    expect((q.refundCents, q.fullRefund, q.byOrg), (50000, false, false));
  });
}
