import 'package:bamboozled/domain/services/daily_note_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final ids = [for (var i = 0; i < 7; i++) 'note-$i'];
  final day0 = DateTime(2026, 10, 1);
  DateTime day(int n) => DateTime(day0.year, day0.month, day0.day + n);

  test('the same person gets the same card on the same day, every time and at any hour', () {
    final a = DailyNotePicker.pick(ids, 'ms-tan', day0);
    expect(DailyNotePicker.pick(ids, 'ms-tan', day0), a);
    expect(DailyNotePicker.pick(ids, 'ms-tan', DateTime(2026, 10, 1, 23, 59)), a);
    expect(DailyNotePicker.pick(ids.reversed, 'ms-tan', day0), a, reason: 'the order of the file doesn’t matter');
  });

  test('no card repeats until every card has been shown, and every card is shown once per cycle', () {
    final start = DailyNotePicker.dayIndex(day0);
    final cycleStart = start - start % ids.length;
    for (var cycle = 0; cycle < 4; cycle++) {
      final shown = [
        for (var i = 0; i < ids.length; i++)
          DailyNotePicker.pick(ids, 'ms-tan', day(cycleStart - start + cycle * ids.length + i))!,
      ];
      expect(shown.toSet(), ids.toSet(), reason: 'cycle $cycle');
    }
  });

  test('different people get different orders', () {
    final orders = {
      for (final seed in ['a', 'b', 'c', 'd', 'e', 'f']) DailyNotePicker.orderFor(ids, seed, 0).join(','),
    };
    expect(orders.length, greaterThan(1));
  });

  test('a new cycle is a new shuffle', () {
    final orders = {for (var c = 0; c < 6; c++) DailyNotePicker.orderFor(ids, 'ms-tan', c).join(',')};
    expect(orders.length, greaterThan(1));
  });

  test('the card changes at midnight', () {
    final seen = {for (var i = 0; i < ids.length; i++) DailyNotePicker.pick(ids, 'x', day(i))};
    expect(seen.length, ids.length, reason: 'consecutive days within a cycle all differ');
  });

  test('days are counted by calendar date, across months, years and before the epoch', () {
    expect(DailyNotePicker.dayIndex(DateTime(2026, 1, 1)), 0);
    expect(DailyNotePicker.dayIndex(DateTime(2026, 1, 31, 23)), 30);
    expect(DailyNotePicker.dayIndex(DateTime(2026, 3, 1)), 59);
    expect(DailyNotePicker.dayIndex(DateTime(2027, 1, 1)), 365);
    expect(DailyNotePicker.dayIndex(DateTime(2025, 12, 31)), -1);
    expect(DailyNotePicker.pick(ids, 'x', DateTime(2025, 6, 1)), isIn(ids));
  });

  test('the same card is never shown two days running, even when a new cycle starts', () {
    for (final count in [2, 3, 4, 7]) {
      final some = ids.take(count).toList();
      for (final seed in ['a', 'b', 'ms-tan', 'x9']) {
        String? previous;
        for (var i = 0; i < count * 30; i++) {
          final today = DailyNotePicker.pick(some, seed, day(i));
          expect(today, isNot(previous), reason: '$count cards, seed $seed, day $i');
          previous = today;
        }
      }
    }
  });

  test('two cards simply alternate', () {
    final two = ['a', 'b'];
    expect({for (var i = 0; i < 6; i += 2) DailyNotePicker.pick(two, 's', day(i))}.length, 1);
    expect(DailyNotePicker.orderFor(two, 's', 0), DailyNotePicker.orderFor(two, 's', 5));
  });

  test('one card is shown every day; no cards gives nothing', () {
    expect(DailyNotePicker.pick(['only'], 'x', day0), 'only');
    expect(DailyNotePicker.pick(['only'], 'x', day(1)), 'only');
    expect(DailyNotePicker.pick(const [], 'x', day0), isNull);
  });

  test('the shuffle is a known sequence, so phones, computers and browsers agree', () {
    // Pinned (checked to match when compiled to JavaScript too): if this changes, everyone's cards
    // would change. Update only on purpose.
    expect(DailyNotePicker.orderFor(['a', 'b', 'c', 'd', 'e'], 'seed', 0), ['d', 'e', 'c', 'a', 'b']);
  });
}
