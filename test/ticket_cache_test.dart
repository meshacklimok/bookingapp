import 'package:bookingapp/features/tickets/data/ticket_cache.dart';
import 'package:bookingapp/features/tickets/data/ticket_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> row(String id, {String status = 'valid'}) => {
      'id': id,
      'qr_token': 'tok-$id',
      'status': status,
      'bookings': {
        'starts_at': '2026-11-01T07:00:00Z',
        'services': {'title': 'Haircut'},
      },
    };

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('TicketCache', () {
    test('saves and loads rows per user with the time they were saved', () async {
      final cache = TicketCache();
      final at = DateTime.utc(2026, 10, 25, 9);
      await cache.save('u1', [row('t1')], now: at);

      final saved = await cache.load('u1');
      expect(saved!.rows.single['qr_token'], 'tok-t1');
      expect(saved.savedAt, at);
      expect(await cache.load('u2'), isNull);
    });

    test('clear removes every user\'s tickets but leaves other settings', () async {
      SharedPreferences.setMockInitialValues({'theme': 'dark'});
      final cache = TicketCache();
      await cache.save('u1', [row('t1')]);
      await cache.save('u2', [row('t2')]);
      await cache.clear();

      expect(await cache.load('u1'), isNull);
      expect(await cache.load('u2'), isNull);
      expect((await SharedPreferences.getInstance()).getString('theme'), 'dark');
    });

    test('an unreadable saved copy counts as none', () async {
      SharedPreferences.setMockInitialValues({'tickets.v1.u1': 'not json'});
      expect(await TicketCache().load('u1'), isNull);
    });
  });

  group('loadWallet', () {
    test('returns fresh tickets and saves them', () async {
      final cache = TicketCache();
      final wallet = await loadWallet(userId: 'u1', cache: cache, fetch: () async => [row('t1')]);

      expect(wallet.isSavedCopy, isFalse);
      expect(wallet.tickets.single.serviceTitle, 'Haircut');
      expect((await cache.load('u1'))!.rows, hasLength(1));
    });

    test('falls back to the saved copy when the server cannot be reached', () async {
      final cache = TicketCache();
      await cache.save('u1', [row('t1'), row('t2', status: 'used')]);

      final wallet = await loadWallet(userId: 'u1', cache: cache, fetch: () => Future.error(Exception('offline')));
      expect(wallet.isSavedCopy, isTrue);
      expect(wallet.tickets.map((t) => t.status), ['valid', 'used']);
    });

    test('rethrows when offline with nothing saved', () async {
      expect(
        loadWallet(userId: 'u1', cache: TicketCache(), fetch: () => Future.error(Exception('offline'))),
        throwsException,
      );
    });

    test('a fresh empty list replaces old saved tickets', () async {
      final cache = TicketCache();
      await cache.save('u1', [row('t1')]);
      await loadWallet(userId: 'u1', cache: cache, fetch: () async => []);
      expect((await cache.load('u1'))!.rows, isEmpty);
    });
  });
}
