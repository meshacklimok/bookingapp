import 'package:bookingapp/features/booking/domain/booking.dart';
import 'package:bookingapp/features/booking/domain/deposit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('depositCents', () {
    test('is the percentage of the price', () {
      expect(depositCents(200000, 25), 50000);
      expect(depositCents(200000, 50), 100000);
    });

    test('rounds up to whole shillings', () {
      // 30% of KES 333.00 is 99.90 -> 100.00
      expect(depositCents(33300, 30), 10000);
      expect(depositCents(100, 10), 100);
    });

    test('never exceeds the price and is zero for a free booking', () {
      expect(depositCents(50, 99), 50);
      expect(depositCents(0, 25), 0);
    });
  });

  group('Booking balance', () {
    Map<String, dynamic> row({int total = 50000, int? balance, String? paidAt}) => {
          'id': 'b1',
          'service_id': 's1',
          'starts_at': '2030-01-01T10:00:00Z',
          'quantity': 1,
          'status': 'confirmed',
          'total_cents': total,
          'expires_at': null,
          if (balance != null) 'balance_cents': balance,
          'balance_paid_at': paidAt,
        };

    test('a booking without a deposit owes nothing at the venue', () {
      final b = Booking.fromMap(row());
      expect(b.balanceCents, 0);
      expect(b.balanceDueCents, 0);
      expect(b.fullPriceCents, 50000);
    });

    test('a deposit leaves a balance until the organization collects it', () {
      final due = Booking.fromMap(row(balance: 150000));
      expect(due.balanceDueCents, 150000);
      expect(due.fullPriceCents, 200000);

      final paid = Booking.fromMap(row(balance: 150000, paidAt: '2030-01-01T10:30:00Z'));
      expect(paid.balancePaid, isTrue);
      expect(paid.balanceDueCents, 0);
    });
  });
}
