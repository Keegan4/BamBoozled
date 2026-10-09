import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/panda_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/priority_badge.dart';
import '../../../domain/models/category.dart';
import '../../../domain/models/priority.dart';
import '../../../domain/models/task.dart';

/// One task row: category stripe, tick box, title, due label and priority.
/// Matches the `TaskCard` component in Figma.
class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.category,
    required this.now,
    required this.onToggleDone,
    required this.onOpen,
    this.tooltip,
  });

  final Task task;
  final Category? category;
  final DateTime now;
  final VoidCallback onToggleDone;
  final VoidCallback onOpen;

  /// Extra explanation shown on hover/long-press, e.g. why it's ranked here.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final overdue = task.isOverdue(now);
    final done = task.isDone;
    final metaColor = overdue ? PandaColors.overdue : PandaColors.muted;
    final due = dueLabel(task.dueAt, now, done: done);
    final card = LayoutBuilder(
      builder: (context, constraints) {
        // Narrow (phone) cards: priority as leaves only, and text may wrap to two lines.
        final compact = constraints.maxWidth < 380;
        return Opacity(
          opacity: done ? 0.7 : 1,
          child: Material(
            color: PandaColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PandaSizes.tileRadius),
              side: BorderSide(color: overdue ? PandaColors.overdue : PandaColors.line, width: overdue ? 1.5 : 1),
            ),
            clipBehavior: Clip.antiAlias,
            elevation: 0,
            child: InkWell(
              onTap: onOpen,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 8, color: category?.color ?? PandaColors.stone),
                    _TickBox(done: done, title: task.title, onTap: onToggleDone),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              task.title,
                              maxLines: compact ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: PandaText.bodyStrong.copyWith(
                                color: done ? PandaColors.muted : PandaColors.ink,
                                decoration: done ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(Icons.schedule_rounded, size: 16, color: metaColor),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    [
                                      due,
                                      ?category?.name,
                                      if (task.repeat != Repeat.none) '↻ ${task.repeat.label}',
                                      if (task.isFromCanvas) 'Canvas',
                                    ].join(' · '),
                                    maxLines: compact ? 2 : 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: PandaText.caption.copyWith(color: metaColor),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
                      child: Center(
                        child: PriorityBadge(priority: task.priority, showLabel: !compact),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    return tooltip == null ? card : Tooltip(message: tooltip!, child: card);
  }
}

class _TickBox extends StatelessWidget {
  const _TickBox({required this.done, required this.title, required this.onTap});
  final bool done;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    checked: done,
    button: true,
    label: done ? 'Mark "$title" as not done' : 'Mark "$title" as done',
    excludeSemantics: true,
    child: InkResponse(
      onTap: onTap,
      radius: 24,
      child: SizedBox(
        width: 56,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? PandaColors.bamboo : null,
              border: done ? null : Border.all(color: PandaColors.ink, width: 2),
            ),
            child: done ? const Icon(Icons.check_rounded, size: 18, color: PandaColors.ink) : null,
          ),
        ),
      ),
    ),
  );
}
