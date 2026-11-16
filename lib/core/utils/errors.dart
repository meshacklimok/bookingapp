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
  'has_active_bookings': 'You have upcoming bookings. Cancel them or wait until they are over, then delete your account.',
  'org_has_bookings': 'Your organization has upcoming bookings. Add another owner or let them finish before deleting your account.',
  'cannot_reschedule': 'This booking cannot be rescheduled.',
  'reschedule_window_closed': 'It is too close to the start time to reschedule. You can still cancel under the cancellation policy.',
  'guest_name_required': 'Enter the customer\'s name.',
  'staff_required': 'Choose who the appointment is with.',
  'invalid_amount': 'Enter a valid amount.',
  'tier_not_found': 'Choose a ticket type.',
  'forbidden': 'You do not have permission to do that.',
  'promo_invalid': 'That promo code is not valid for this booking.',
  'promo_expired': 'That promo code has expired.',
  'promo_used_up': 'That promo code has been fully used.',
  'promo_already_used': 'You have already used that promo code.',
  'cannot_apply': 'A promo code can only be changed before payment starts.',
  'deposit_not_offered': 'This service does not take a deposit.',
  'booking_free': 'This booking is free, so there is nothing to pay.',
  'no_balance_due': 'There is no balance left to collect on this booking.',
  'booking_not_free': 'This booking still has to be paid.',
  'cannot_confirm': 'This booking can no longer be confirmed. Please start again.',
  'slot_required': 'Please choose a time first.',
  'cannot_review': 'You can review a booking once it has taken place.',
  'invalid_rating': 'Choose a rating from 1 to 5 stars.',
  'promo_codes_code_idx': 'You already have a promo code with that name.',
  'services_hours_check': 'Closing time must be after opening time.',
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
