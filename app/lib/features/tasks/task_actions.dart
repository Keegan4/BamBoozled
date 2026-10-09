import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../core/utils/dates.dart';
import '../../domain/models/priority.dart';
import '../../domain/models/task.dart';
import 'widgets/task_card.dart';
import 'task_editor.dart';

/// Ticks a task on or off and offers Undo.
Future<void> toggleTaskDone(BuildContext context, WidgetRef ref, Task task) async {
  final repo = ref.read(taskRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  final now = ref.read(clockProvider);
  final nowDone = !task.isDone;
  if (nowDone && task.isTooEarlyToTick(now)) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '“${task.title}” isn’t due until ${formatShortDate(task.dueAt, now)}. '
            'You can tick it off from ${formatShortDate(task.earliestTick!, now)}.',
          ),
        ),
      );
    return;
  }
  await repo.setDone(task.id, nowDone);
  final String message;
  if (!nowDone) {
    message = '“${task.title}” moved back to your list.';
  } else if (task.repeat == Repeat.none) {
    message = 'Nice work! “${task.title}” is done.';
  } else {
    message =
        'Nice work! “${task.title}” is done. It comes back tomorrow, due '
        '${formatShortDate(task.repeat.next(task.dueAt), now)}.';
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(label: 'Undo', onPressed: () => repo.setDone(task.id, !nowDone)),
      ),
    );
}

/// A [TaskCard] wired up to the repository and the editor.
class ConnectedTaskCard extends ConsumerWidget {
  const ConnectedTaskCard({super.key, required this.task, this.tooltip});

  final Task task;
  final String? tooltip;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TaskCard(
    task: task,
    category: ref.watch(categoryMapProvider)[task.categoryId],
    now: ref.watch(clockProvider),
    tooltip: tooltip,
    onToggleDone: () => toggleTaskDone(context, ref, task),
    onOpen: () => showTaskEditor(context, task: task),
  );
}
