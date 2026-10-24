/// A member of an organization, as listed on the staff screen.
class OrgStaff {
  const OrgStaff({required this.userId, required this.name, required this.role});

  final String userId;
  final String name;
  final String role;

  bool get isOwner => role == 'owner';

  factory OrgStaff.fromMap(Map<String, dynamic> m) {
    final name = (m['profiles'] as Map<String, dynamic>?)?['full_name'] as String?;
    return OrgStaff(
      userId: m['user_id'] as String,
      name: name?.trim().isNotEmpty == true ? name! : 'Unnamed member',
      role: m['role'] as String,
    );
  }
}

/// Weekdays use Postgres numbering (0 = Sunday ... 6 = Saturday), the same as `extract(dow ...)` in
/// get_available_slots. The UI lists Monday first.
const weekdayOrder = [1, 2, 3, 4, 5, 6, 0];
const weekdayNames = {
  0: 'Sunday',
  1: 'Monday',
  2: 'Tuesday',
  3: 'Wednesday',
  4: 'Thursday',
  5: 'Friday',
  6: 'Saturday',
};
String weekdayShort(int weekday) => weekdayNames[weekday]!.substring(0, 3);

/// "09:00:00" or "09:00" -> minutes after midnight. Null if it is not a time of day.
int? parseDbTime(String? value) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$').firstMatch(value ?? '');
  if (m == null) return null;
  final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
  if (h > 24 || min > 59 || (h == 24 && min > 0)) return null;
  return h * 60 + min;
}

/// 570 -> "09:30". Also the format Postgres accepts for a `time` value.
String formatMinutes(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// One block of working time on a day, in minutes after midnight (local Nairobi time).
class TimeWindow {
  const TimeWindow(this.startMin, this.endMin);

  final int startMin;
  final int endMin;

  String get label => '${formatMinutes(startMin)}–${formatMinutes(endMin)}';

  @override
  bool operator ==(Object other) => other is TimeWindow && other.startMin == startMin && other.endMin == endMin;

  @override
  int get hashCode => Object.hash(startMin, endMin);
}

typedef WeeklyHours = Map<int, List<TimeWindow>>;

/// Reads `availability_rules` rows. Rows with an unreadable time are skipped.
WeeklyHours weeklyHoursFromRows(List<Map<String, dynamic>> rows) {
  final hours = <int, List<TimeWindow>>{};
  for (final r in rows) {
    final start = parseDbTime(r['start_time'] as String?), end = parseDbTime(r['end_time'] as String?);
    if (start == null || end == null) continue;
    (hours[(r['weekday'] as num).toInt()] ??= []).add(TimeWindow(start, end));
  }
  for (final windows in hours.values) {
    windows.sort((a, b) => a.startMin.compareTo(b.startMin));
  }
  return hours;
}

/// The jsonb array `set_staff_hours` expects.
List<Map<String, dynamic>> weeklyHoursToPayload(WeeklyHours hours) => [
      for (final day in weekdayOrder)
        for (final w in hours[day] ?? const <TimeWindow>[])
          {'weekday': day, 'start_time': formatMinutes(w.startMin), 'end_time': formatMinutes(w.endMin)},
    ];

/// Each window must end after it starts; windows on one day may touch but not overlap.
String? validateWindows(List<TimeWindow> windows) {
  final sorted = [...windows]..sort((a, b) => a.startMin.compareTo(b.startMin));
  for (final w in sorted) {
    if (w.endMin <= w.startMin) return '${w.label} ends before it starts';
  }
  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i].startMin < sorted[i - 1].endMin) return '${sorted[i - 1].label} overlaps ${sorted[i].label}';
  }
  return null;
}

/// First problem in the whole week, prefixed with the day, or null.
String? validateWeeklyHours(WeeklyHours hours) {
  for (final day in weekdayOrder) {
    final error = validateWindows(hours[day] ?? const []);
    if (error != null) return '${weekdayNames[day]}: $error';
  }
  return null;
}

/// Monday to Friday, one window: the quickest way to a usable schedule.
WeeklyHours weekdayPreset({int startMin = 9 * 60, int endMin = 17 * 60}) => {
      for (final d in [1, 2, 3, 4, 5]) d: [TimeWindow(startMin, endMin)],
    };

/// "Mon–Fri 09:00–17:00 · Sat 09:00–12:00", or "Not set" when there are no hours at all.
String summarizeHours(WeeklyHours hours) {
  String key(int day) => (hours[day] ?? const []).map((w) => w.label).join(', ');
  final parts = <String>[];
  var i = 0;
  while (i < weekdayOrder.length) {
    final k = key(weekdayOrder[i]);
    var j = i;
    while (j + 1 < weekdayOrder.length && key(weekdayOrder[j + 1]) == k) {
      j++;
    }
    if (k.isNotEmpty) {
      final days = i == j ? weekdayShort(weekdayOrder[i]) : '${weekdayShort(weekdayOrder[i])}–${weekdayShort(weekdayOrder[j])}';
      parts.add('$days $k');
    }
    i = j + 1;
  }
  return parts.isEmpty ? 'Not set' : parts.join(' · ');
}

/// A date that overrides the weekly hours: closed all day, or different hours just that day.
class DayException {
  const DayException({required this.id, required this.date, required this.isClosed, this.window});

  final String id;
  final DateTime date; // a calendar date; the time of day is meaningless
  final bool isClosed;
  final TimeWindow? window;

  factory DayException.fromMap(Map<String, dynamic> m) {
    final start = parseDbTime(m['start_time'] as String?), end = parseDbTime(m['end_time'] as String?);
    final parts = (m['date'] as String).split('-').map(int.parse).toList();
    return DayException(
      id: m['id'] as String,
      date: DateTime(parts[0], parts[1], parts[2]),
      isClosed: m['is_closed'] as bool,
      window: start != null && end != null ? TimeWindow(start, end) : null,
    );
  }
}

/// Row for `availability_exceptions`. Pass [window] for custom hours, or null for a day off.
Map<String, dynamic> exceptionToRow({
  required String orgId,
  required String staffId,
  required String isoDate,
  TimeWindow? window,
}) =>
    {
      'org_id': orgId,
      'staff_id': staffId,
      'date': isoDate,
      'is_closed': window == null,
      'start_time': window == null ? null : formatMinutes(window.startMin),
      'end_time': window == null ? null : formatMinutes(window.endMin),
    };

/// Which services to link and unlink to move from [current] to [desired].
({Set<String> add, Set<String> remove}) serviceLinkChanges(Set<String> current, Set<String> desired) =>
    (add: desired.difference(current), remove: current.difference(desired));
