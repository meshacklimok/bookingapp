import 'package:supabase_flutter/supabase_flutter.dart';

const _friendly = {
  'slot_unavailable': 'That time was just taken. Please pick another slot.',
  'sold_out': 'Sorry, those tickets are sold out.',
  'sales_closed': 'Ticket sales for this option are closed.',
  'service_not_found': 'This service is no longer available.',
  'invalid_quantity': 'Please choose between 1 and 10 tickets.',
  'cannot_cancel': 'This booking can no longer be cancelled. It may have started or already been cancelled.',
  'hold_expired': 'Your hold expired. Please start the booking again.',
  'invalid_phone': 'Enter a valid Safaricom number, e.g. 0712345678.',
  'booking_not_payable': 'This booking can no longer be paid.',
  'service_has_bookings': 'This service already has bookings, so its type cannot be changed. Deactivate it and create a new one instead.',
  'services_event_window_check': 'The event must end after it starts.',
  'bookings_tier_id_fkey': 'That ticket type has bookings and cannot be removed. Set its quantity to what is sold instead.',
  'user_not_found': 'No account uses that email. Ask them to sign up in the app first, then try again.',
  'already_member': 'That person is already part of this organization.',
  'staff_has_bookings': 'This person has upcoming bookings. Reassign or complete them first.',
  'availability_rules_no_overlap': 'Two time blocks on the same day overlap.',
  'availability_exceptions_org_staff_date_key': 'That date already has a day off or custom hours. Remove it first.',
  'not_org_member': 'That person is not part of this organization.',
  'ticket_used': 'A ticket for this booking has already been scanned, so it cannot be cancelled.',
  'refund_not_pending': 'That refund was already handled.',
  'forbidden': 'You do not have permission to do that.',
  'organizations_slug_key': 'An organization with a very similar name already exists. Try a more specific name.',
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
