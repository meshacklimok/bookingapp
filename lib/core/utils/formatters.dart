/// Formats integer cents as Kenyan shillings, e.g. 150000 -> "KES 1,500".
String formatKes(int cents) {
  final whole = cents ~/ 100;
  final rem = cents % 100;
  final digits = whole.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  final fraction = rem == 0 ? '' : '.${rem.toString().padLeft(2, '0')}';
  return 'KES $buffer$fraction';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _two(int n) => n.toString().padLeft(2, '0');

/// "2026-11-03", the format Postgres expects for a date parameter.
String formatIsoDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// "Tue 3 Nov"
String formatDay(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

/// "14:30"
String formatTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// "Tue 3 Nov, 14:30" in the device's local time.
String formatDateTime(DateTime d) {
  final local = d.toLocal();
  return '${formatDay(local)}, ${formatTime(local)}';
}

/// "just now", "5 min ago", "3 h ago", "yesterday", then "Tue 3 Nov".
String formatRelative(DateTime then, DateTime now) {
  final diff = now.difference(then);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(then.year, then.month, then.day)).inDays;
  return days == 1 ? 'yesterday' : formatDay(then.toLocal());
}
