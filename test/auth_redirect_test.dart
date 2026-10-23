import 'package:bookingapp/core/router/app_router.dart';
import 'package:flutter_test/flutter_test.dart';

String? redirect(bool loggedIn, String location) => authRedirect(loggedIn: loggedIn, location: Uri.parse(location));

void main() {
  group('guest', () {
    test('can browse public pages', () {
      expect(redirect(false, '/'), isNull);
      expect(redirect(false, '/service/abc'), isNull);
      expect(redirect(false, '/login'), isNull);
    });

    test('is sent to login with the page they wanted', () {
      final to = Uri.parse(redirect(false, '/book/abc')!);
      expect(to.path, '/login');
      expect(to.queryParameters['from'], '/book/abc');
    });

    test('keeps query parameters of the wanted page', () {
      final to = Uri.parse(redirect(false, '/checkout/1?x=2')!);
      expect(to.queryParameters['from'], '/checkout/1?x=2');
    });
  });

  group('signed in', () {
    test('passes through private pages', () {
      expect(redirect(true, '/bookings'), isNull);
      expect(redirect(true, '/profile/edit'), isNull);
    });

    test('leaves login for home', () {
      expect(redirect(true, '/login'), '/');
    });

    test('leaves login for the page they came from', () {
      expect(redirect(true, '/login?from=%2Fbook%2Fabc'), '/book/abc');
    });

    test('ignores external return targets', () {
      expect(redirect(true, '/login?from=https%3A%2F%2Fevil.example'), '/');
      expect(redirect(true, '/login?from=%2F%2Fevil.example'), '/');
    });
  });
}
