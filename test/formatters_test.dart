import 'package:bookingapp/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatKes', () {
    test('whole shillings have no decimals', () {
      expect(formatKes(50000), 'KES 500');
    });

    test('thousands are separated', () {
      expect(formatKes(150000000), 'KES 1,500,000');
    });

    test('cents are kept', () {
      expect(formatKes(1050), 'KES 10.50');
      expect(formatKes(5), 'KES 0.05');
    });

    test('zero', () {
      expect(formatKes(0), 'KES 0');
    });
  });

  test('formatIsoDate pads month and day', () {
    expect(formatIsoDate(DateTime(2026, 3, 4)), '2026-03-04');
  });
}
