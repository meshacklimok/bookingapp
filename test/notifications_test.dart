import 'package:bookingapp/core/utils/formatters.dart';
import 'package:bookingapp/features/notifications/domain/app_notification.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> row({Object? route = '/bookings', String? readAt}) => {
      'id': 'n1',
      'title': 'Booking confirmed',
      'body': 'Haircut',
      'created_at': '2026-02-01T10:00:00Z',
      'read_at': readAt,
      'data': {'route': route},
    };

void main() {
  group('safeRoute', () {
    test('keeps in-app paths', () {
      expect(safeRoute('/bookings'), '/bookings');
      expect(safeRoute('/org/abc/payouts'), '/org/abc/payouts');
    });

    test('drops anything that could leave the app', () {
      for (final bad in ['https://evil.example', '//evil.example', 'bookings', '/x?u=http://a', '', null, 42]) {
        expect(safeRoute(bad), isNull, reason: '$bad');
      }
    });
  });

  group('AppNotification', () {
    test('reads the payload and unread state', () {
      final n = AppNotification.fromMap(row());
      expect((n.title, n.body, n.route, n.isUnread), ('Booking confirmed', 'Haircut', '/bookings', true));
      expect(AppNotification.fromMap(row(readAt: '2026-02-01T11:00:00Z')).isUnread, isFalse);
    });

    test('tolerates a missing payload or an unsafe route', () {
      expect(AppNotification.fromMap({...row(), 'data': null}).route, isNull);
      expect(AppNotification.fromMap(row(route: 'https://evil.example')).route, isNull);
    });

    test('unreadCount counts only unread', () {
      expect(unreadCount([AppNotification.fromMap(row()), AppNotification.fromMap(row(readAt: '2026-02-01T11:00:00Z'))]), 1);
    });
  });

  test('formatRelative', () {
    final now = DateTime(2026, 2, 10, 12);
    expect(formatRelative(now.subtract(const Duration(seconds: 20)), now), 'just now');
    expect(formatRelative(now.subtract(const Duration(minutes: 5)), now), '5 min ago');
    expect(formatRelative(now.subtract(const Duration(hours: 3)), now), '3 h ago');
    expect(formatRelative(DateTime(2026, 2, 9, 9), now), 'yesterday');
    expect(formatRelative(DateTime(2026, 2, 3, 9), now), 'Tue 3 Feb');
  });
}
