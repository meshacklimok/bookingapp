import 'package:bookingapp/core/utils/errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('maps a known backend code to a customer message', () {
    expect(
      friendlyError(const PostgrestException(message: 'slot_unavailable')),
      'That time was just taken. Please pick another slot.',
    );
  });

  test('maps a code carried in a function error body', () {
    expect(
      friendlyError(const FunctionException(status: 400, details: {'error': 'invalid_phone'})),
      'Enter a valid Safaricom number, e.g. 0712345678.',
    );
  });

  test('hides unknown errors behind a generic message', () {
    expect(friendlyError(Exception('relation "x" does not exist')), 'Something went wrong. Please try again.');
  });
}
