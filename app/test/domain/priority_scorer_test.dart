import 'package:bamboozled/domain/models/priority.dart';
import 'package:bamboozled/domain/models/task.dart';
import 'package:bamboozled/domain/services/priority_scorer.dart';
import 'package:flutter_test/flutter_test.dart';

// Thursday 8 October 2026, 2:00 pm.
final now = DateTime(2026, 10, 8, 14);

Task task(String title, DateTime due, Priority priority, {int? estimate, DateTime? done, DateTime? deleted}) => Task(
      id: title,
      title: title,
      dueAt: due,
      priority: priority,
      categoryId: 'general',
      estimateMinutes: estimate,
      completedAt: done,
      deletedAt: deleted,
      createdAt: now,
      updatedAt: now,
    );

void main() {
  const scorer = PriorityScorer();

  group('urgency', () {
    test('is 1.0 when due right now', () {
      expect(scorer.urgency(task('a', now, Priority.low), now), closeTo(1.0, 1e-9));
    });
    test('halves at two days', () {
      expect(scorer.urgency(task('a', now.add(const Duration(days: 2)), Priority.low), now), closeTo(0.5, 1e-9));
    });
    test('is about 0.22 at one week', () {
      expect(scorer.urgency(task('a', now.add(const Duration(days: 7)), Priority.low), now), closeTo(0.222, 1e-3));
    });
    test('is boosted to 1.25 when overdue', () {
      expect(scorer.urgency(task('a', now.subtract(const Duration(minutes: 1)), Priority.low), now), 1.25);
    });
  });

  test('matches the worked example in docs/priority-algorithm.md', () {
    final tasks = [
      task('Plan CCA trip', now.add(const Duration(days: 7)), Priority.urgent),
      task('Reply to parents', now.add(const Duration(hours: 4)), Priority.low),
      task('Mark 3A essays', now.add(const Duration(days: 1)), Priority.high),
      task('Submit report', now.subtract(const Duration(days: 1)), Priority.medium),
    ];
    final ranked = scorer.rank(tasks, now);
    expect(ranked.map((r) => r.task.title), ['Submit report', 'Mark 3A essays', 'Reply to parents', 'Plan CCA trip']);
    expect(ranked.map((r) => r.score.toStringAsFixed(2)), ['0.91', '0.70', '0.62', '0.57']);
  });

  test('excludes completed and deleted tasks', () {
    final ranked = scorer.rank([
      task('open', now.add(const Duration(days: 1)), Priority.low),
      task('done', now, Priority.urgent, done: now),
      task('deleted', now, Priority.urgent, deleted: now),
    ], now);
    expect(ranked.map((r) => r.task.title), ['open']);
  });

  test('breaks ties by earlier due date, then shorter estimate', () {
    final overdue1 = now.subtract(const Duration(days: 2));
    final overdue2 = now.subtract(const Duration(days: 1));
    final ranked = scorer.rank([
      task('later', overdue2, Priority.high),
      task('long', overdue1, Priority.high, estimate: 120),
      task('no estimate', overdue1, Priority.high),
      task('short', overdue1, Priority.high, estimate: 15),
    ], now);
    expect(ranked.map((r) => r.task.title), ['short', 'long', 'no estimate', 'later']);
  });

  test('explains the ranking', () {
    expect(scorer.reason(task('a', DateTime(2026, 10, 9, 17), Priority.high), now), 'Due tomorrow · High priority');
    expect(scorer.reason(task('a', DateTime(2026, 10, 7, 23, 59), Priority.medium), now),
        'Overdue by 1 day · Medium priority');
  });
}
