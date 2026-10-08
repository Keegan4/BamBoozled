import 'package:intl/intl.dart';

/// Tasks with no specific time are due at the end of the day (23:59).
DateTime endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59);

bool hasSpecificTime(DateTime d) => !(d.hour == 23 && d.minute == 59);

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Whole calendar days from [from] to [to] (negative if [to] is earlier). DST-safe.
int calendarDaysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// Monday of the week containing [d].
DateTime startOfWeek(DateTime d) => dateOnly(d).subtract(Duration(days: d.weekday - DateTime.monday));

/// "5:00 pm"
String formatTime(DateTime d) => DateFormat('h:mm a').format(d).toLowerCase();

/// "Mon 12 Oct", with the year added when it isn't [now]'s year.
String formatShortDate(DateTime d, DateTime now) =>
    DateFormat(d.year == now.year ? 'EEE d MMM' : 'EEE d MMM y').format(d);

String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

/// Friendly due label shown on task cards, e.g. "Due tomorrow, 5:00 pm" or "Overdue by 1 day".
String dueLabel(DateTime due, DateTime now, {bool done = false}) {
  final timePart = hasSpecificTime(due) ? ', ${formatTime(due)}' : '';
  if (!done && due.isBefore(now)) {
    final days = calendarDaysBetween(due, now);
    if (days >= 1) return 'Overdue by ${_plural(days, 'day')}';
    final hours = now.difference(due).inHours;
    return hours >= 1 ? 'Overdue by ${_plural(hours, 'hour')}' : 'Overdue';
  }
  final days = calendarDaysBetween(now, due);
  if (days == 0) return 'Due today$timePart';
  if (days == 1) return 'Due tomorrow$timePart';
  return 'Due ${formatShortDate(due, now)}';
}

/// "Good morning" / "Good afternoon" / "Good evening".
String greetingFor(DateTime now) {
  if (now.hour < 12) return 'Good morning';
  if (now.hour < 18) return 'Good afternoon';
  return 'Good evening';
}
