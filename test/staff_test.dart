import 'package:bookingapp/core/utils/errors.dart';
import 'package:bookingapp/features/org_dashboard/domain/staff.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('times', () {
    test('parseDbTime reads Postgres time values', () {
      expect(parseDbTime('09:00:00'), 540);
      expect(parseDbTime('9:30'), 570);
      expect(parseDbTime('00:00:00'), 0);
      expect(parseDbTime('24:00:00'), 1440);
    });

    test('parseDbTime rejects anything else', () {
      for (final bad in [null, '', 'noon', '25:00', '12:60', '24:30', '12']) {
        expect(parseDbTime(bad), isNull, reason: '$bad');
      }
    });

    test('formatMinutes round-trips with parseDbTime', () {
      expect(formatMinutes(540), '09:00');
      expect(formatMinutes(1005), '16:45');
      for (final m in [0, 59, 60, 725, 1439]) {
        expect(parseDbTime(formatMinutes(m)), m);
      }
    });
  });

  group('weekday numbering', () {
    test('Postgres dow: Sunday is 0, and the UI lists Monday first', () {
      expect(weekdayNames[0], 'Sunday');
      expect(weekdayNames[6], 'Saturday');
      expect(weekdayOrder.first, 1);
      expect(weekdayOrder.last, 0);
      expect(weekdayOrder.toSet(), {0, 1, 2, 3, 4, 5, 6});
    });

    test('short names', () {
      expect(weekdayShort(1), 'Mon');
      expect(weekdayShort(0), 'Sun');
    });
  });

  group('weekly hours rows', () {
    test('rows are grouped by weekday and sorted by start', () {
      final hours = weeklyHoursFromRows([
        {'weekday': 1, 'start_time': '13:00:00', 'end_time': '17:00:00'},
        {'weekday': 1, 'start_time': '09:00:00', 'end_time': '12:00:00'},
        {'weekday': 0, 'start_time': '10:00:00', 'end_time': '14:00:00'},
      ]);
      expect(hours[1], [const TimeWindow(540, 720), const TimeWindow(780, 1020)]);
      expect(hours[0], [const TimeWindow(600, 840)]);
      expect(hours[2], isNull);
    });

    test('unreadable times are skipped, not fatal', () {
      final hours = weeklyHoursFromRows([
        {'weekday': 1, 'start_time': 'oops', 'end_time': '17:00:00'},
      ]);
      expect(hours, isEmpty);
    });

    test('payload is Monday-first, uses dow numbers and HH:MM', () {
      final payload = weeklyHoursToPayload({
        0: [const TimeWindow(600, 840)],
        1: [const TimeWindow(540, 720), const TimeWindow(780, 1020)],
      });
      expect(payload, [
        {'weekday': 1, 'start_time': '09:00', 'end_time': '12:00'},
        {'weekday': 1, 'start_time': '13:00', 'end_time': '17:00'},
        {'weekday': 0, 'start_time': '10:00', 'end_time': '14:00'},
      ]);
    });

    test('an empty week produces an empty payload (clears all hours)', () {
      expect(weeklyHoursToPayload({}), isEmpty);
    });
  });

  group('validateWindows', () {
    test('a window must end after it starts', () {
      expect(validateWindows([const TimeWindow(720, 540)]), contains('ends before'));
      expect(validateWindows([const TimeWindow(540, 540)]), isNotNull);
    });

    test('overlap is rejected whatever the entry order', () {
      expect(validateWindows([const TimeWindow(660, 780), const TimeWindow(540, 720)]), contains('overlaps'));
    });

    test('touching windows are allowed, as the database allows them', () {
      expect(validateWindows([const TimeWindow(540, 720), const TimeWindow(720, 900)]), isNull);
    });

    test('empty is valid (a day off every week)', () {
      expect(validateWindows([]), isNull);
    });
  });

  test('validateWeeklyHours names the offending day', () {
    final error = validateWeeklyHours({
      3: [const TimeWindow(540, 720), const TimeWindow(600, 800)],
    });
    expect(error, startsWith('Wednesday:'));
    expect(validateWeeklyHours(weekdayPreset()), isNull);
  });

  group('presets and summaries', () {
    test('weekdayPreset is Monday to Friday only', () {
      final p = weekdayPreset();
      expect(p.keys.toSet(), {1, 2, 3, 4, 5});
      expect(p[1], [const TimeWindow(540, 1020)]);
    });

    test('summary collapses identical consecutive days', () {
      expect(summarizeHours(weekdayPreset()), 'Mon–Fri 09:00–17:00');
    });

    test('summary separates different days and shows split shifts', () {
      final hours = {
        ...weekdayPreset(),
        6: [const TimeWindow(540, 720)],
        2: [const TimeWindow(540, 720), const TimeWindow(780, 1020)],
      };
      expect(summarizeHours(hours), 'Mon 09:00–17:00 · Tue 09:00–12:00, 13:00–17:00 · Wed–Fri 09:00–17:00 · Sat 09:00–12:00');
    });

    test('a Sunday-only schedule is not confused with Monday', () {
      expect(summarizeHours({0: [const TimeWindow(600, 840)]}), 'Sun 10:00–14:00');
    });

    test('no hours', () {
      expect(summarizeHours({}), 'Not set');
    });
  });

  group('DayException.fromMap', () {
    test('a day off', () {
      final e = DayException.fromMap({'id': 'e1', 'date': '2026-12-25', 'is_closed': true, 'start_time': null, 'end_time': null});
      expect(e.date, DateTime(2026, 12, 25));
      expect(e.isClosed, isTrue);
      expect(e.window, isNull);
    });

    test('custom hours', () {
      final e = DayException.fromMap({'id': 'e2', 'date': '2026-12-24', 'is_closed': false, 'start_time': '09:00:00', 'end_time': '13:00:00'});
      expect(e.isClosed, isFalse);
      expect(e.window, const TimeWindow(540, 780));
    });
  });

  group('exceptionToRow', () {
    test('no window means closed with no times', () {
      final row = exceptionToRow(orgId: 'o', staffId: 's', isoDate: '2026-12-25');
      expect(row['is_closed'], isTrue);
      expect(row['start_time'], isNull);
      expect(row['end_time'], isNull);
    });

    test('a window means open with those times (the table requires both)', () {
      final row = exceptionToRow(orgId: 'o', staffId: 's', isoDate: '2026-12-24', window: const TimeWindow(540, 780));
      expect(row['is_closed'], isFalse);
      expect(row['start_time'], '09:00');
      expect(row['end_time'], '13:00');
      expect(row['org_id'], 'o');
    });
  });

  test('serviceLinkChanges returns only what differs', () {
    final changes = serviceLinkChanges({'a', 'b'}, {'b', 'c'});
    expect(changes.add, {'c'});
    expect(changes.remove, {'a'});
    final same = serviceLinkChanges({'a'}, {'a'});
    expect(same.add, isEmpty);
    expect(same.remove, isEmpty);
  });

  group('OrgStaff.fromMap', () {
    test('reads the embedded profile name', () {
      final s = OrgStaff.fromMap({'user_id': 'u1', 'role': 'owner', 'profiles': {'full_name': 'Stella'}});
      expect(s.name, 'Stella');
      expect(s.isOwner, isTrue);
    });

    test('falls back when the profile is hidden or unnamed', () {
      expect(OrgStaff.fromMap({'user_id': 'u2', 'role': 'staff', 'profiles': null}).name, 'Unnamed member');
      expect(OrgStaff.fromMap({'user_id': 'u3', 'role': 'staff', 'profiles': {'full_name': '  '}}).name, 'Unnamed member');
    });
  });

  group('friendly errors for staff setup', () {
    String msg(String m) => friendlyError(PostgrestException(message: m));

    test('each backend code has its own message', () {
      expect(msg('user_not_found'), contains('sign up'));
      expect(msg('already_member'), contains('already'));
      expect(msg('staff_has_bookings'), contains('upcoming bookings'));
      expect(msg('violates exclusion constraint "availability_rules_no_overlap"'), contains('overlap'));
      expect(msg('forbidden'), contains('permission'));
    });
  });
}
