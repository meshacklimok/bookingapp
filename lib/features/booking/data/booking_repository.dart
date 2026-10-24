import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/formatters.dart';
import '../domain/booking.dart';
import '../domain/cancellation.dart';

class BookingRepository {
  BookingRepository(this._client);

  final SupabaseClient _client;

  Future<List<Slot>> availableSlots(String serviceId, DateTime date) async {
    final rows = await _client.rpc('get_available_slots', params: {
      'p_service_id': serviceId,
      'p_date': formatIsoDate(date),
    }) as List<dynamic>;
    return rows.map((r) => Slot.fromMap(r as Map<String, dynamic>)).toList();
  }

  /// Creates a 10 minute hold and returns the new booking id.
  Future<String> holdAppointment({required String serviceId, required Slot slot}) async {
    final row = await _client.rpc('create_booking_hold', params: {
      'p_service_id': serviceId,
      'p_starts_at': slot.start.toUtc().toIso8601String(),
      'p_staff_id': slot.staffId,
    }) as Map<String, dynamic>;
    return row['id'] as String;
  }

  Future<String> holdTickets({required String serviceId, required String tierId, required int quantity}) async {
    final row = await _client.rpc('create_booking_hold', params: {
      'p_service_id': serviceId,
      'p_tier_id': tierId,
      'p_quantity': quantity,
    }) as Map<String, dynamic>;
    return row['id'] as String;
  }

  /// Cancels, then asks the server to send any refund back through the provider. The cancellation stands even when
  /// that second step fails: the refund stays pending and a platform admin can retry it.
  Future<void> cancel(String bookingId, {String? reason}) async {
    await _client.rpc('cancel_booking', params: {'p_booking_id': bookingId, if (reason != null) 'p_reason': reason});
    try {
      await _client.functions.invoke('process-refund', body: {'booking_id': bookingId});
    } catch (_) {}
  }

  /// What cancelling now would refund, for the caller's role (customer: policy; organization: everything).
  Future<CancellationQuote> cancellationQuote(String bookingId) async {
    final rows = await _client.rpc('cancellation_quote', params: {'p_booking_id': bookingId});
    return CancellationQuote.fromMap((rows as List).single as Map<String, dynamic>);
  }

  Future<List<Booking>> mine() async {
    final rows = await _client
        .from('bookings')
        .select('*, services(title, free_cancel_hours, late_refund_pct), payments(refunds(status))')
        .eq('customer_id', _client.auth.currentUser!.id)
        .order('starts_at', ascending: false);
    return rows.map(Booking.fromMap).toList();
  }

  /// Live updates for one booking, used while a payment completes.
  Stream<Booking?> watch(String bookingId) {
    return _client
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('id', bookingId)
        .map((rows) => rows.isEmpty ? null : Booking.fromMap(rows.first));
  }

  /// Starts a payment. For Paystack the result contains `authorization_url` to open.
  Future<Map<String, dynamic>> startPayment({
    required String bookingId,
    required String provider,
    String? phone,
  }) async {
    final res = await _client.functions.invoke('create-payment', body: {
      'booking_id': bookingId,
      'provider': provider,
      if (phone != null) 'phone': phone,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }
}

final bookingRepositoryProvider = Provider((ref) => BookingRepository(ref.watch(supabaseProvider)));

final slotsProvider = FutureProvider.autoDispose.family<List<Slot>, ({String serviceId, DateTime date})>(
  (ref, args) => ref.watch(bookingRepositoryProvider).availableSlots(args.serviceId, args.date),
);

final myBookingsProvider = FutureProvider.autoDispose<List<Booking>>(
  (ref) {
    ref.watch(currentUserIdProvider);
    return ref.watch(bookingRepositoryProvider).mine();
  },
);

final bookingStreamProvider = StreamProvider.autoDispose.family<Booking?, String>(
  (ref, id) => ref.watch(bookingRepositoryProvider).watch(id),
);
