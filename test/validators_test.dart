import 'package:bookingapp/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeKenyanPhone', () {
    test('local 07 and 01 numbers get the 254 prefix', () {
      expect(normalizeKenyanPhone('0712345678'), '254712345678');
      expect(normalizeKenyanPhone('0112345678'), '254112345678');
    });

    test('international formats with + and spaces', () {
      expect(normalizeKenyanPhone('+254 712 345 678'), '254712345678');
      expect(normalizeKenyanPhone('254-712-345-678'), '254712345678');
    });

    test('rejects landlines, short numbers and other countries', () {
      expect(normalizeKenyanPhone('0201234567'), isNull);
      expect(normalizeKenyanPhone('071234567'), isNull);
      expect(normalizeKenyanPhone('255712345678'), isNull);
      expect(normalizeKenyanPhone(''), isNull);
    });
  });

  test('validateEmail', () {
    expect(validateEmail('a@b.co'), isNull);
    expect(validateEmail('  a@b.co '), isNull);
    expect(validateEmail('a@b'), isNotNull);
    expect(validateEmail('@'), isNotNull);
    expect(validateEmail(null), isNotNull);
  });

  test('validatePassword needs 6 characters', () {
    expect(validatePassword('12345'), isNotNull);
    expect(validatePassword('123456'), isNull);
  });

  test('validateOptionalPhone allows empty', () {
    expect(validateOptionalPhone(''), isNull);
    expect(validateOptionalPhone(null), isNull);
    expect(validateOptionalPhone('0712345678'), isNull);
    expect(validateOptionalPhone('12345'), isNotNull);
  });
}
