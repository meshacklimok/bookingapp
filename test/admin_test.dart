import 'package:bookingapp/features/admin/domain/admin.dart';
import 'package:bookingapp/features/org_dashboard/domain/organization.dart';
import 'package:bookingapp/features/org_dashboard/domain/payouts.dart';
import 'package:flutter_test/flutter_test.dart';

AdminOrg org(String name, String status) =>
    AdminOrg.fromMap({'id': name, 'name': name, 'status': status, 'created_at': '2026-01-01T00:00:00Z'});

void main() {
  test('pending organizations come first, then alphabetical', () {
    final sorted = sortAdminOrgs([org('Zed', 'pending'), org('alpha', 'approved'), org('Bravo', 'suspended'), org('Mid', 'pending')]);
    expect(sorted.map((o) => o.name), ['Mid', 'Zed', 'alpha', 'Bravo']);
    expect(sorted.first.status, OrgStatus.pending);
  });

  group('parseCommissionPct', () {
    test('accepts whole numbers, decimals and a comma', () {
      expect(parseCommissionPct('10'), 10);
      expect(parseCommissionPct(' 12.5% '), 12.5);
      expect(parseCommissionPct('7,25'), 7.25);
      expect(parseCommissionPct('100'), 100);
      expect(parseCommissionPct('0'), 0);
    });

    test('rejects junk, negatives, over 100 and extra decimals', () {
      for (final bad in ['', 'abc', '-1', '100.5', '101', '1.234', '1e2']) {
        expect(parseCommissionPct(bad), isNull, reason: bad);
      }
    });
  });

  test('a refund reads the customer and service from the nested payment', () {
    final r = AdminRefund.fromMap({
      'id': 'r1',
      'amount_cents': 50000,
      'status': 'pending',
      'created_at': '2026-02-01T10:00:00Z',
      'reason': 'cancelled by customer',
      'payments': {
        'provider': 'mpesa',
        'phone': '254712345678',
        'reference': 'x',
        'profiles': {'full_name': 'Alice'},
        'bookings': {'services': {'title': 'Haircut'}},
      },
    });
    expect((r.customerName, r.serviceTitle, r.phone, r.isPending), ('Alice', 'Haircut', '254712345678', true));
  });

  test('a refund tolerates a missing payment', () {
    final r = AdminRefund.fromMap({'id': 'r1', 'amount_cents': 1, 'status': 'processed', 'created_at': '2026-02-01T10:00:00Z'});
    expect((r.customerName, r.serviceTitle, r.isPending), (null, null, false));
  });

  test('balances and payouts parse database rows', () {
    final b = AdminBalance.fromMap({'org_id': 'o', 'org_name': 'Salon', 'payable_cents': 10000, 'upcoming_cents': 9000, 'paid_out_cents': 20000});
    expect((b.balance.payableCents, b.balance.upcomingCents, b.balance.paidOutCents), (10000, 9000, 20000));
    final p = Payout.fromMap({'id': 'p', 'amount_cents': 500, 'method': 'cheque', 'created_at': '2026-02-01T10:00:00Z'});
    expect(p.method, PayoutMethod.other);
  });

  test('commission rows know the platform default', () {
    final c = AdminCommission.fromMap({'scope': 'platform', 'scope_id': null, 'name': 'Platform default', 'pct': 10.0});
    expect(c.isPlatform, isTrue);
  });
}
