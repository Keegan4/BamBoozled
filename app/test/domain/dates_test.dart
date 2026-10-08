import 'package:bamboozled/core/utils/dates.dart';
import 'package:bamboozled/domain/models/priority.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 8, 14); // Thu 8 Oct 2026, 2 pm

  group('dueLabel', () {
    test('today with and without a time', () {
      expect(dueLabel(DateTime(2026, 10, 8, 18), now), 'Due today, 6:00 pm');
      expect(dueLabel(endOfDay(now), now), 'Due today');
    });
    test('tomorrow', () => expect(dueLabel(DateTime(2026, 10, 9, 17), now), 'Due tomorrow, 5:00 pm'));
    test('later dates', () {
      expect(dueLabel(DateTime(2026, 10, 12, 23, 59), now), 'Due Mon 12 Oct');
      expect(dueLabel(DateTime(2027, 1, 4, 9), now), 'Due Mon 4 Jan 2027');
    });
    test('overdue', () {
      expect(dueLabel(DateTime(2026, 10, 8, 13, 30), now), 'Overdue');
      expect(dueLabel(DateTime(2026, 10, 8, 11), now), 'Overdue by 3 hours');
      expect(dueLabel(DateTime(2026, 10, 7, 23, 59), now), 'Overdue by 1 day');
      expect(dueLabel(DateTime(2026, 10, 5, 9), now), 'Overdue by 3 days');
    });
    test('done tasks are never overdue', () {
      expect(dueLabel(DateTime(2026, 10, 8, 9), now, done: true), 'Due today, 9:00 am');
    });
  });

  test('startOfWeek is Monday', () {
    expect(startOfWeek(now), DateTime(2026, 10, 5));
    expect(startOfWeek(DateTime(2026, 10, 11, 22)), DateTime(2026, 10, 5));
  });

  test('greeting follows the time of day', () {
    expect(greetingFor(DateTime(2026, 10, 8, 8)), 'Good morning');
    expect(greetingFor(DateTime(2026, 10, 8, 13)), 'Good afternoon');
    expect(greetingFor(DateTime(2026, 10, 8, 20)), 'Good evening');
  });

  group('Repeat.next', () {
    final d = DateTime(2026, 1, 31, 9);
    test('daily and weekly', () {
      expect(Repeat.daily.next(d), DateTime(2026, 2, 1, 9));
      expect(Repeat.weekly.next(d), DateTime(2026, 2, 7, 9));
    });
    test('monthly clamps to the last day of the month', () {
      expect(Repeat.monthly.next(d), DateTime(2026, 2, 28, 9));
      expect(Repeat.monthly.next(DateTime(2026, 12, 15)), DateTime(2027, 1, 15));
    });
  });
}
