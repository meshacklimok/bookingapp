import 'package:bookingapp/core/utils/errors.dart';
import 'package:bookingapp/features/booking/domain/booking.dart';
import 'package:bookingapp/features/discover/domain/service.dart';
import 'package:bookingapp/features/org_dashboard/domain/managed_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> bookingRow({String status = 'confirmed', Object? reviews, Duration endsIn = const Duration(days: -1)}) {
  final ends = DateTime.now().add(endsIn);
  return {
    'id': 'b1',
    'service_id': 's1',
    'starts_at': ends.subtract(const Duration(hours: 1)).toUtc().toIso8601String(),
    'ends_at': ends.toUtc().toIso8601String(),
    'quantity': 1,
    'status': status,
    'total_cents': 160000,
    'discount_cents': 40000,
    'expires_at': null,
    'services': {'title': 'Tennis court'},
    'reviews': reviews,
  };
}

void main() {
  group('resource slots', () {
    test('have no staff member', () {
      final slot = Slot.fromMap({'staff_id': null, 'slot_start': '2026-07-01T06:00:00+00:00', 'slot_end': '2026-07-01T07:00:00+00:00'});
      expect(slot.staffId, isNull);
      expect(slot.end.difference(slot.start), const Duration(hours: 1));
    });

    test('appointment slots still carry theirs', () {
      final slot = Slot.fromMap({'staff_id': 'st', 'slot_start': '2026-07-01T06:00:00+00:00', 'slot_end': '2026-07-01T07:00:00+00:00'});
      expect(slot.staffId, 'st');
    });
  });

  group('Booking', () {
    test('reads the discount and the review embed, whether it is a row or a list', () {
      expect(Booking.fromMap(bookingRow()).discountCents, 40000);
      expect(Booking.fromMap(bookingRow()).reviewRating, isNull);
      expect(Booking.fromMap(bookingRow(reviews: {'rating': 4})).reviewRating, 4);
      expect(Booking.fromMap(bookingRow(reviews: [{'rating': 2}])).reviewRating, 2);
      expect(Booking.fromMap(bookingRow(reviews: [])).reviewRating, isNull);
    });

    test('can be reviewed once it is paid for and over', () {
      expect(Booking.fromMap(bookingRow()).canReview, isTrue);
      expect(Booking.fromMap(bookingRow(status: 'completed')).canReview, isTrue);
      expect(Booking.fromMap(bookingRow(endsIn: const Duration(days: 2))).canReview, isFalse);
      for (final s in ['held', 'pending_payment', 'cancelled', 'no_show']) {
        expect(Booking.fromMap(bookingRow(status: s)).canReview, isFalse, reason: s);
      }
    });

    test('rows from the live stream have no discount or review columns to worry about', () {
      final row = bookingRow()..remove('discount_cents')..remove('reviews')..remove('ends_at');
      final b = Booking.fromMap(row);
      expect(b.discountCents, 0);
      expect(b.reviewRating, isNull);
    });
  });

  group('rescheduling', () {
    Booking at(Duration fromNow, {String status = 'confirmed', String mode = 'appointment', int freeHours = 24}) {
      final start = DateTime.now().add(fromNow);
      return Booking.fromMap({
        ...bookingRow(status: status),
        'starts_at': start.toUtc().toIso8601String(),
        'services': {'title': 'T', 'booking_mode': mode, 'free_cancel_hours': freeHours},
      });
    }

    test('is offered while a full refund would still apply', () {
      expect(at(const Duration(days: 3)).canReschedule(DateTime.now()), isTrue);
      expect(at(const Duration(days: 3), mode: 'resource').canReschedule(DateTime.now()), isTrue);
      expect(at(const Duration(hours: 5)).canReschedule(DateTime.now()), isFalse);
      expect(at(const Duration(hours: 5), freeHours: 0).canReschedule(DateTime.now()), isTrue);
    });

    test('is not offered for events, unpaid or cancelled bookings', () {
      expect(at(const Duration(days: 3), mode: 'event').canReschedule(DateTime.now()), isFalse);
      for (final s in ['held', 'cancelled', 'completed']) {
        expect(at(const Duration(days: 3), status: s).canReschedule(DateTime.now()), isFalse, reason: s);
      }
    });
  });

  group('Service rating', () {
    Map<String, dynamic> row(Map<String, dynamic> extra) => {
          'id': 's',
          'org_id': 'o',
          'title': 'T',
          'booking_mode': 'resource',
          'price_cents': 1000,
          'duration_min': 60,
          ...extra,
        };

    test('is absent until someone reviews', () {
      final s = Service.fromMap(row({'rating_avg': null, 'rating_count': 0}));
      expect(s.ratingAvg, isNull);
      expect(s.ratingCount, 0);
      expect(s.mode, BookingMode.resource);
    });

    test('reads the average from numeric strings or numbers', () {
      expect(Service.fromMap(row({'rating_avg': 4.5, 'rating_count': 2})).ratingAvg, 4.5);
      expect(Service.fromMap(row({'rating_avg': 4, 'rating_count': 1})).ratingAvg, 4.0);
    });

    test('Review reads the reviewer and comment', () {
      final r = Review.fromMap({'rating': 5, 'comment': null, 'created_at': '2026-07-01T10:00:00+00:00', 'reviewer': 'Alice'});
      expect((r.rating, r.comment, r.reviewer), (5, null, 'Alice'));
    });
  });

  group('resource service form', () {
    test('writes its hours and slot length, and no event dates', () {
      final map = const ServiceDraft(
        title: ' Court ',
        mode: BookingMode.resource,
        priceCents: 200000,
        durationMin: 90,
        bufferMin: 10,
        openTime: '07:30',
        closeTime: '21:00',
      ).toMap('org');
      expect(map['booking_mode'], 'resource');
      expect(map['title'], 'Court');
      expect((map['price_cents'], map['duration_min'], map['buffer_min']), (200000, 90, 10));
      expect((map['open_time'], map['close_time']), ('07:30', '21:00'));
      expect(map['event_starts_at'], isNull);
    });

    test('appointments and events do not send hours', () {
      for (final mode in [BookingMode.appointment, BookingMode.event]) {
        expect(ServiceDraft(title: 'T', mode: mode).toMap('org').containsKey('open_time'), isFalse, reason: mode.name);
      }
    });

    test('reads hours back as HH:MM, with defaults for older rows', () {
      final base = {'id': 's', 'org_id': 'o', 'title': 'T', 'booking_mode': 'resource', 'price_cents': 0, 'duration_min': 60, 'buffer_min': 0, 'is_active': true};
      final s = ManagedService.fromMap({...base, 'open_time': '09:00:00', 'close_time': '17:30:00'});
      expect((s.openTime, s.closeTime), ('09:00', '17:30'));
      final old = ManagedService.fromMap(base);
      expect((old.openTime, old.closeTime), ('08:00', '20:00'));
    });

    test('opening hours must leave room for a slot', () {
      expect(validateOpeningHours('09:00', '17:00'), isNull);
      expect(validateOpeningHours('09:00', '10:00', slotMinutes: 60), isNull);
      expect(validateOpeningHours('09:00', '09:00'), isNotNull);
      expect(validateOpeningHours('17:00', '09:00'), isNotNull);
      expect(validateOpeningHours('09:00', '10:00', slotMinutes: 90), isNotNull);
    });
  });

  group('friendly errors for the new flows', () {
    test('promo and review codes are explained', () {
      for (final code in ['promo_invalid', 'promo_expired', 'promo_used_up', 'promo_already_used', 'cannot_review', 'invalid_rating', 'cannot_apply']) {
        expect(friendlyError(Exception(code)), isNot(startsWith('Something went wrong')), reason: code);
      }
    });
  });
}
