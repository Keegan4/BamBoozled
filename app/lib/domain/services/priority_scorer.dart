import '../../core/utils/dates.dart';
import '../models/task.dart';

/// A task with its "Do next" score.
class RankedTask {
  const RankedTask(this.task, this.score);
  final Task task;
  final double score;
}

/// Orders tasks by a blend of deadline urgency and assigned priority.
/// The formula is documented in docs/priority-algorithm.md.
class PriorityScorer {
  const PriorityScorer({
    this.urgencyWeight = 0.55,
    this.priorityWeight = 0.45,
    this.halfLifeDays = 2,
    this.overdueUrgency = 1.25,
  });

  final double urgencyWeight;
  final double priorityWeight;

  /// Days until due at which urgency halves (today ≈ 1, [halfLifeDays] ≈ 0.5).
  final double halfLifeDays;

  /// Urgency given to every overdue task.
  final double overdueUrgency;

  double urgency(Task task, DateTime now) {
    final daysLeft = task.dueAt.difference(now).inSeconds / Duration.secondsPerDay;
    if (daysLeft < 0) return overdueUrgency;
    return 1 / (1 + daysLeft / halfLifeDays);
  }

  double score(Task task, DateTime now) =>
      urgencyWeight * urgency(task, now) + priorityWeight * (task.priority.weight / 4);

  /// Incomplete, non-deleted tasks, highest score first. Ties go to the earlier
  /// due date, then the shorter estimate (tasks without an estimate last).
  List<RankedTask> rank(Iterable<Task> tasks, DateTime now) {
    final ranked = [
      for (final t in tasks)
        if (!t.isDone && !t.isDeleted) RankedTask(t, score(t, now)),
    ];
    ranked.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byDue = a.task.dueAt.compareTo(b.task.dueAt);
      if (byDue != 0) return byDue;
      return (a.task.estimateMinutes ?? 1 << 30).compareTo(b.task.estimateMinutes ?? 1 << 30);
    });
    return ranked;
  }

  /// Short explanation of a task's rank, e.g. "Due tomorrow · High priority".
  String reason(Task task, DateTime now) {
    final due = dueLabel(task.dueAt, now).replaceFirst(RegExp(r', .*$'), '');
    return '$due · ${task.priority.label} priority';
  }
}
