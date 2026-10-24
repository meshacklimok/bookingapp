import 'package:bookingapp/features/discover/domain/service.dart';
import 'package:bookingapp/features/org_dashboard/domain/managed_service.dart';
import 'package:flutter_test/flutter_test.dart';

TicketTier tier(String id, {String name = 'General', int price = 100000, int quantity = 10, int sold = 0}) =>
    TicketTier(id: id, name: name, priceCents: price, quantity: quantity, sold: sold);

void main() {
  group('parseKesToCents', () {
    test('whole shillings', () {
      expect(parseKesToCents('1500'), 150000);
      expect(parseKesToCents('0'), 0);
    });

    test('thousands separators and a KES prefix', () {
      expect(parseKesToCents('1,500'), 150000);
      expect(parseKesToCents('KES 1,500.50'), 150050);
      expect(parseKesToCents('ksh 20'), 2000);
    });

    test('one or two decimals', () {
      expect(parseKesToCents('99.5'), 9950);
      expect(parseKesToCents('99.05'), 9905);
    });

    test('rejects negatives, three decimals, letters and blanks', () {
      for (final bad in ['-5', '1.234', 'abc', '', ' ', '1.', '.5', '12 000']) {
        expect(parseKesToCents(bad), isNull, reason: bad);
      }
    });
  });

  group('field validators', () {
    test('title length', () {
      expect(validateServiceTitle(''), isNotNull);
      expect(validateServiceTitle('A'), isNotNull);
      expect(validateServiceTitle('Haircut'), isNull);
      expect(validateServiceTitle('x' * 81), isNotNull);
    });

    test('duration must be positive and bounded; buffer may be zero', () {
      expect(validatePositiveInt('0'), isNotNull);
      expect(validatePositiveInt('abc'), isNotNull);
      expect(validatePositiveInt('45'), isNull);
      expect(validatePositiveInt('1441'), isNotNull);
      expect(validateNonNegativeInt('0'), isNull);
      expect(validateNonNegativeInt('-1'), isNotNull);
    });
  });

  group('validateEventWindow', () {
    final now = DateTime(2026, 11, 1, 12);

    test('needs a start', () {
      expect(validateEventWindow(null, null, now: now), isNotNull);
    });

    test('start must be in the future for a new event', () {
      expect(validateEventWindow(DateTime(2026, 10, 31), null, now: now), isNotNull);
      expect(validateEventWindow(DateTime(2026, 11, 2), null, now: now), isNull);
    });

    test('an event that already started can still be edited', () {
      expect(validateEventWindow(DateTime(2026, 10, 31), null, now: now, requireFuture: false), isNull);
    });

    test('end must be after start', () {
      final start = DateTime(2026, 11, 2, 18);
      expect(validateEventWindow(start, start, now: now), isNotNull);
      expect(validateEventWindow(start, start.subtract(const Duration(hours: 1)), now: now), isNotNull);
      expect(validateEventWindow(start, start.add(const Duration(hours: 3)), now: now), isNull);
    });
  });

  group('validateTiers', () {
    test('needs at least one tier', () {
      expect(validateTiers(const []), isNotNull);
    });

    test('names must be present and unique, ignoring case and spaces', () {
      expect(validateTiers(const [TierDraft(name: ' ', priceCents: 0, quantity: 1)]), isNotNull);
      expect(
        validateTiers(const [
          TierDraft(name: 'VIP', priceCents: 0, quantity: 1),
          TierDraft(name: ' vip ', priceCents: 0, quantity: 1),
        ]),
        contains('"vip"'),
      );
    });

    test('quantity must be at least 1', () {
      expect(validateTiers(const [TierDraft(name: 'GA', priceCents: 0, quantity: 0)]), isNotNull);
    });

    test('quantity cannot drop below tickets already sold', () {
      const edited = [TierDraft(id: 't1', name: 'GA', priceCents: 0, quantity: 4)];
      expect(validateTiers(edited, sold: {'t1': 5}), contains('5 tickets sold'));
      expect(validateTiers(edited, sold: {'t1': 4}), isNull);
    });

    test('free tiers are allowed', () {
      expect(validateTiers(const [TierDraft(name: 'RSVP', priceCents: 0, quantity: 50)]), isNull);
    });
  });

  group('diffTiers', () {
    final saved = [tier('a', name: 'GA'), tier('b', name: 'VIP', price: 500000)];

    test('no edits means no writes', () {
      final changes = diffTiers(saved, [
        const TierDraft(id: 'a', name: 'GA', priceCents: 100000, quantity: 10),
        const TierDraft(id: 'b', name: 'VIP', priceCents: 500000, quantity: 10),
      ]);
      expect(changes.isEmpty, isTrue);
    });

    test('splits into inserts, updates and deletes', () {
      final changes = diffTiers(saved, [
        const TierDraft(id: 'a', name: 'General', priceCents: 100000, quantity: 10),
        const TierDraft(name: 'Student', priceCents: 50000, quantity: 20),
      ]);
      expect(changes.updates.map((t) => t.id), ['a']);
      expect(changes.inserts.map((t) => t.name), ['Student']);
      expect(changes.deletes, ['b']);
    });

    test('a draft with an unknown id is inserted rather than updated', () {
      final changes = diffTiers(saved, [const TierDraft(id: 'gone', name: 'X', priceCents: 0, quantity: 1)]);
      expect(changes.inserts, hasLength(1));
      expect(changes.updates, isEmpty);
    });

    test('a trimmed name is not treated as a change', () {
      final changes = diffTiers([tier('a', name: 'GA')], [const TierDraft(id: 'a', name: ' GA ', priceCents: 100000, quantity: 10)]);
      expect(changes.isEmpty, isTrue);
    });
  });

  test('undeletableTiers lists removed tiers that have sold tickets', () {
    final saved = [tier('a', name: 'GA', sold: 3), tier('b', name: 'VIP'), tier('c', name: 'Early', sold: 1)];
    final edited = [const TierDraft(id: 'c', name: 'Early', priceCents: 100000, quantity: 10)];
    expect(undeletableTiers(saved, edited), ['GA']);
  });

  group('ServiceDraft.toMap', () {
    test('appointment writes price, duration and buffer and clears event dates', () {
      final m = const ServiceDraft(
        title: ' Haircut ',
        mode: BookingMode.appointment,
        priceCents: 100000,
        durationMin: 45,
        bufferMin: 15,
        description: '  ',
      ).toMap('org1');
      expect(m['title'], 'Haircut');
      expect(m['description'], isNull);
      expect(m['price_cents'], 100000);
      expect(m['duration_min'], 45);
      expect(m['buffer_min'], 15);
      expect(m['event_starts_at'], isNull);
      expect(m.containsKey('event_starts_at'), isTrue);
      expect(m['org_id'], 'org1');
    });

    test('event never writes a price (the cheapest tier sets it) and stores UTC dates', () {
      final start = DateTime.utc(2026, 12, 5, 15);
      final m = ServiceDraft(title: 'Gala', mode: BookingMode.event, priceCents: 999, eventStartsAt: start).toMap('org1');
      expect(m.containsKey('price_cents'), isFalse);
      expect(m.containsKey('duration_min'), isFalse);
      expect(m['event_starts_at'], '2026-12-05T15:00:00.000Z');
      expect(m['event_ends_at'], isNull);
    });
  });

  test('ManagedService.fromMap reads every column, including inactive ones', () {
    final s = ManagedService.fromMap({
      'id': 's1',
      'org_id': 'o1',
      'title': 'Gala',
      'booking_mode': 'event',
      'price_cents': 150000,
      'duration_min': 60,
      'buffer_min': 0,
      'is_active': false,
      'event_starts_at': '2026-12-05T15:00:00+00:00',
    });
    expect(s.mode, BookingMode.event);
    expect(s.isActive, isFalse);
    expect(s.eventStartsAt, DateTime.utc(2026, 12, 5, 15));
    expect(s.eventEndsAt, isNull);
  });
}
