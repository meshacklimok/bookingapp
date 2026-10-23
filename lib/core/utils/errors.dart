import 'package:supabase_flutter/supabase_flutter.dart';

const _friendly = {
  'slot_unavailable': 'That time was just taken. Please pick another slot.',
  'sold_out': 'Sorry, those tickets are sold out.',
  'sales_closed': 'Ticket sales for this option are closed.',
  'service_not_found': 'This service is no longer available.',
  'invalid_quantity': 'Please choose between 1 and 10 tickets.',
  'cannot_cancel': 'This booking can no longer be cancelled.',
  'hold_expired': 'Your hold expired. Please start the booking again.',
  'invalid_phone': 'Enter a valid Safaricom number, e.g. 0712345678.',
  'booking_not_payable': 'This booking can no longer be paid.',
};

/// Turns backend error codes into messages a customer can act on.
String friendlyError(Object error) {
  final raw = switch (error) {
    PostgrestException(:final message) => message,
    FunctionException(:final details) => details is Map ? '${details['error']}' : '$details',
    _ => error.toString(),
  };
  for (final entry in _friendly.entries) {
    if (raw.contains(entry.key)) return entry.value;
  }
  return 'Something went wrong. Please try again.';
}
