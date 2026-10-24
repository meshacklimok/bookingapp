import 'package:bookingapp/features/org_dashboard/domain/earnings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EarningsPeriod.range', () {
    // 22:00 UTC on 31 Jan is already 1 Feb in Nairobi
    final lateUtc = DateTime.utc(2026, 1, 31, 22);

    test('uses the Nairobi calendar month', () {
      expect(EarningsPeriod.thisMonth.range(lateUtc), ('2026-02-01', '2026-02-28'));
      expect(EarningsPeriod.thisMonth.range(DateTime.utc(2026, 1, 31, 20)), ('2026-01-01', '2026-01-31'));
    });

    test('last month crosses the year boundary and handles leap years', () {
      expect(EarningsPeriod.lastMonth.range(DateTime.utc(2026, 1, 15)), ('2025-12-01', '2025-12-31'));
      expect(EarningsPeriod.lastMonth.range(DateTime.utc(2024, 3, 10)), ('2024-02-01', '2024-02-29'));
    });

    test('all time leaves both sides open', () {
      expect(EarningsPeriod.allTime.range(lateUtc), (null, null));
    });
  });

  group('parsing', () {
    test('summary reads database counts and sums', () {
      final s = EarningsSummary.fromMap({'booking_count': 3, 'gross_cents': 170000, 'commission_cents': 19000, 'net_cents': 151000});
      expect((s.count, s.grossCents, s.commissionCents, s.netCents), (3, 170000, 19000, 151000));
    });

    test('row keeps the snapshot rate and tolerates missing names', () {
      final r = EarningsRow.fromMap({
        'booking_id': 'b1',
        'starts_at': '2020-03-10T12:00:00+00:00',
        'status': 'completed',
        'service_title': null,
        'customer_name': null,
        'gross_cents': 50000,
        'commission_pct': 12.5,
        'commission_cents': 6250,
        'net_cents': 43750,
      });
      expect(r.commissionPct, 12.5);
      expect(r.serviceTitle, isNull);
      expect(r.grossCents - r.commissionCents, r.netCents);
    });
  });

  test('formatPct drops a trailing .0', () {
    expect(formatPct(10), '10%');
    expect(formatPct(12.5), '12.5%');
  });
}
