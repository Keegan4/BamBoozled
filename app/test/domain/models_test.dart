import 'package:bamboozled/domain/models/category.dart';
import 'package:bamboozled/domain/models/priority.dart';
import 'package:bamboozled/domain/models/task.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 8, 14);

  Task makeTask({DateTime? due, DateTime? done, DateTime? deleted}) => Task(
    id: 't1',
    title: 'Mark 3A essays',
    dueAt: due ?? DateTime(2026, 10, 9, 17),
    priority: Priority.high,
    categoryId: 'teaching',
    estimateMinutes: 60,
    notes: 'Rubric in the shared drive',
    repeat: Repeat.weekly,
    completedAt: done,
    createdAt: now,
    updatedAt: now,
    deletedAt: deleted,
  );

  group('Priority', () {
    test('weights run 1 to 4 and match the number of leaves', () {
      expect(Priority.values.map((p) => p.weight), [1, 2, 3, 4]);
      expect(Priority.values.map((p) => p.label), ['Low', 'Medium', 'High', 'Urgent']);
    });

    test('fromWeight round-trips and falls back to medium for unknown values', () {
      for (final p in Priority.values) {
        expect(Priority.fromWeight(p.weight), p);
      }
      expect(Priority.fromWeight(0), Priority.medium);
      expect(Priority.fromWeight(99), Priority.medium);
    });
  });

  group('Repeat', () {
    test('labels are the words shown on the form', () {
      expect(Repeat.values.map((r) => r.label), ['Never', 'Daily', 'Weekly', 'Monthly']);
    });

    test('none leaves the date alone', () {
      expect(Repeat.none.next(DateTime(2026, 10, 8, 9)), DateTime(2026, 10, 8, 9));
    });

    test('keeps the time of day', () {
      expect(Repeat.daily.next(DateTime(2026, 10, 8, 17, 30)), DateTime(2026, 10, 9, 17, 30));
      expect(Repeat.monthly.next(DateTime(2026, 10, 8, 17, 30)), DateTime(2026, 11, 8, 17, 30));
    });

    test('monthly handles month ends and leap years', () {
      expect(Repeat.monthly.next(DateTime(2027, 1, 31)), DateTime(2027, 2, 28));
      expect(Repeat.monthly.next(DateTime(2028, 1, 31)), DateTime(2028, 2, 29));
      expect(Repeat.monthly.next(DateTime(2026, 3, 31)), DateTime(2026, 4, 30));
      expect(Repeat.monthly.next(DateTime(2026, 12, 31)), DateTime(2027, 1, 31));
    });
  });

  group('Task', () {
    test('defaults to medium priority, no repeat and not done', () {
      final t = Task(id: 'x', title: 'x', dueAt: now, categoryId: 'general', createdAt: now, updatedAt: now);
      expect(t.priority, Priority.medium);
      expect(t.repeat, Repeat.none);
      expect(t.isDone, isFalse);
      expect(t.isDeleted, isFalse);
    });

    test('isDone and isDeleted follow their timestamps', () {
      expect(makeTask(done: now).isDone, isTrue);
      expect(makeTask(deleted: now).isDeleted, isTrue);
    });

    test('isOverdue is true only for unfinished tasks past their due time', () {
      expect(makeTask(due: now.subtract(const Duration(minutes: 1))).isOverdue(now), isTrue);
      expect(makeTask(due: now.add(const Duration(minutes: 1))).isOverdue(now), isFalse);
      expect(makeTask(due: now).isOverdue(now), isFalse, reason: 'due exactly now is not yet overdue');
      expect(makeTask(due: now.subtract(const Duration(days: 3)), done: now).isOverdue(now), isFalse);
    });

    test('copyWith changes only the named fields and never the id or creation time', () {
      final t = makeTask();
      final c = t.copyWith(title: 'New', priority: Priority.urgent);
      expect(c.title, 'New');
      expect(c.priority, Priority.urgent);
      expect(c.id, t.id);
      expect(c.createdAt, t.createdAt);
      expect(c.dueAt, t.dueAt);
      expect(c.notes, t.notes);
    });

    test('copyWith can clear optional fields', () {
      final t = makeTask(done: now);
      final c = t.copyWith(notes: () => null, estimateMinutes: () => null, completedAt: () => null);
      expect(c.notes, isNull);
      expect(c.estimateMinutes, isNull);
      expect(c.isDone, isFalse);
    });

    test('equality compares every field', () {
      expect(makeTask(), makeTask());
      expect(makeTask().hashCode, makeTask().hashCode);
      expect(makeTask(), isNot(makeTask().copyWith(title: 'Other')));
      expect(makeTask(), isNot(makeTask().copyWith(repeat: Repeat.daily)));
      expect(makeTask(), isNot(makeTask(done: now)));
      expect(makeTask(), isNot(makeTask().copyWith(updatedAt: now.add(const Duration(seconds: 1)))));
    });

    test('toString is readable in test failures', () {
      expect(makeTask().toString(), contains('Mark 3A essays'));
      expect(makeTask().toString(), contains('High'));
    });
  });

  group('Category', () {
    final c = Category(id: 'c1', name: 'Exams', color: const Color(0xFFF2C879), sortOrder: 3, updatedAt: now);

    test('copyWith keeps the id and changes named fields', () {
      final r = c.copyWith(name: 'Tests', color: const Color(0xFF9CC9E8));
      expect(r.id, 'c1');
      expect(r.name, 'Tests');
      expect(r.color, const Color(0xFF9CC9E8));
      expect(r.sortOrder, 3);
    });

    test('is deleted only when it has a deletedAt', () {
      expect(c.isDeleted, isFalse);
      expect(c.copyWith(deletedAt: now).isDeleted, isTrue);
    });

    test('equality compares every field', () {
      final same = Category(id: 'c1', name: 'Exams', color: const Color(0xFFF2C879), sortOrder: 3, updatedAt: now);
      expect(c, same);
      expect(c.hashCode, same.hashCode);
      expect(c, isNot(c.copyWith(name: 'Other')));
      expect(c, isNot(c.copyWith(sortOrder: 4)));
    });
  });
}
