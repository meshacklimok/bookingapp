import 'package:bookingapp/features/discover/domain/service.dart';
import 'package:bookingapp/features/discover/domain/service_filters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('searchPattern', () {
    test('wraps plain text in wildcards', () => expect(searchPattern('haircut'), '%haircut%'));
    test('trims and collapses whitespace', () => expect(searchPattern('  hair   cut '), '%hair cut%'));
    test('strips characters that break PostgREST filters', () {
      expect(searchPattern('a,b(c)*d%e"f'), '%a b c d e f%');
    });
    test('returns null for empty or symbol-only input', () {
      expect(searchPattern('   '), isNull);
      expect(searchPattern('%,()'), isNull);
    });
  });

  group('ServiceFilters', () {
    test('defaults have no active filters', () => expect(const ServiceFilters().activeCount, 0));

    test('counts mode, price and sort but not query or category', () {
      const f = ServiceFilters(
        query: 'x',
        category: 'Beauty',
        mode: BookingMode.event,
        maxPriceCents: 100,
        sort: ServiceSort.priceLow,
      );
      expect(f.activeCount, 3);
    });

    test('copyWith can clear nullable fields', () {
      const f = ServiceFilters(category: 'Beauty', mode: BookingMode.event, maxPriceCents: 100);
      final cleared = f.copyWith(category: null, mode: null, maxPriceCents: null);
      expect(cleared.category, isNull);
      expect(cleared.mode, isNull);
      expect(cleared.maxPriceCents, isNull);
    });

    test('copyWith leaves untouched fields alone', () {
      const f = ServiceFilters(category: 'Beauty', query: 'a');
      final next = f.copyWith(query: 'b');
      expect(next.category, 'Beauty');
      expect(next.query, 'b');
    });

    test('equal filters compare equal', () {
      expect(const ServiceFilters(query: 'a'), const ServiceFilters(query: 'a'));
      expect(const ServiceFilters(query: 'a'), isNot(const ServiceFilters(query: 'b')));
    });
  });
}
