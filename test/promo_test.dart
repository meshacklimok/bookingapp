import 'package:bookingapp/features/org_dashboard/domain/promo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('code validation', () {
    test('accepts letters, digits, dash and underscore', () {
      for (final ok in ['SAVE20', 'welcome-10', 'a_b', 'ABC']) {
        expect(validatePromoCode(ok), isNull, reason: ok);
      }
      expect(validatePromoCode('  SAVE20  '), isNull);
    });

    test('rejects blanks, short, long and odd characters', () {
      for (final bad in ['', '  ', 'ab', 'x' * 25, 'save 20', 'save!', 'ké']) {
        expect(validatePromoCode(bad), isNotNull, reason: bad);
      }
    });
  });

  test('percentage must be 1 to 100', () {
    expect(validatePercentOff('1'), isNull);
    expect(validatePercentOff('100'), isNull);
    for (final bad in ['0', '101', '-5', 'ten', '', '12.5']) {
      expect(validatePercentOff(bad), isNotNull, reason: bad);
    }
  });

  test('max uses may be empty, otherwise a positive whole number', () {
    expect(validateMaxUses(''), isNull);
    expect(validateMaxUses('50'), isNull);
    for (final bad in ['0', '-1', 'x', '1.5']) {
      expect(validateMaxUses(bad), isNotNull, reason: bad);
    }
  });

  test('a draft is sent upper-cased with exactly one kind of discount', () {
    final pct = const PromoDraft(code: ' save20 ', percentOff: 20, maxUses: 5).toMap('org-1');
    expect(pct['code'], 'SAVE20');
    expect(pct['percent_off'], 20);
    expect(pct['amount_off_cents'], isNull);
    expect(pct['max_uses'], 5);
    expect(pct['org_id'], 'org-1');

    final flat = PromoDraft(code: 'FLAT', amountOffCents: 50000, validUntil: DateTime.utc(2027, 1, 31, 20, 59)).toMap('org-1');
    expect(flat['amount_off_cents'], 50000);
    expect(flat['percent_off'], isNull);
    expect(flat['valid_until'], '2027-01-31T20:59:00.000Z');
  });

  group('PromoCode', () {
    PromoCode code({int? percent = 10, int? amount, int? max, DateTime? until, int uses = 0}) => PromoCode(
          id: 'p',
          code: 'X',
          percentOff: percent,
          amountOffCents: amount,
          maxUses: max,
          validUntil: until,
          isActive: true,
          uses: uses,
        );

    test('describes the discount', () {
      expect(code().discountLabel, '10% off');
      expect(code(percent: null, amount: 50000).discountLabel, 'KES 500 off');
    });

    test('knows when it is spent or past its end date', () {
      expect(code(max: 2, uses: 2).isUsedUp, isTrue);
      expect(code(max: 2, uses: 1).isUsedUp, isFalse);
      expect(code(uses: 99).isUsedUp, isFalse);
      final now = DateTime(2026, 6, 1);
      expect(code(until: DateTime(2026, 5, 31)).isExpired(now), isTrue);
      expect(code(until: DateTime(2026, 6, 2)).isExpired(now), isFalse);
      expect(code().isExpired(now), isFalse);
    });

    test('reads the organization listing', () {
      final c = PromoCode.fromMap({
        'id': 'p1',
        'code': 'SAVE20',
        'percent_off': 20,
        'amount_off_cents': null,
        'max_uses': 10,
        'valid_until': '2027-01-01T00:00:00+00:00',
        'is_active': true,
        'uses': 3,
      });
      expect((c.code, c.percentOff, c.maxUses, c.uses), ('SAVE20', 20, 10, 3));
      expect(c.validUntil!.isUtc, isTrue);
    });
  });
}
