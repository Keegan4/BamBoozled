import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/panda_theme.dart';
import '../../../core/widgets/leaf_icon.dart';
import '../../../core/widgets/panda_mascot.dart';
import '../../../core/widgets/pills.dart';
import '../../../data/providers.dart';
import '../../../domain/models/task.dart';
import '../../tasks/task_actions.dart';
import '../../tasks/task_editor.dart';
import '../welcome_controller.dart';
import 'week_tasks_sheet.dart';

/// "Do next": the top tasks in recommended order, each with its rank. When the Status filter asks for
/// finished tasks it lists those too, and finished tasks from the last week always stay visible in a
/// "Recently done" section below, so ticking a task off never makes it just vanish.
class DoNextList extends ConsumerWidget {
  const DoNextList({super.key, this.limit = 5, this.showSubtitle = true});

  final int limit;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ranked = ref.watch(rankedTasksProvider);
    final done = ref.watch(filteredDoneProvider);
    final recent = ref.watch(recentlyDoneProvider);
    final scorer = ref.watch(priorityScorerProvider);
    final now = ref.watch(clockProvider);
    final filter = ref.watch(taskFilterProvider);
    final hasAnyTasks = (ref.watch(tasksProvider).value ?? const []).isNotEmpty;

    final status = filter.status;
    final showsFinished = status == StatusFilter.done || status == StatusFilter.all;
    final onlyFinished = status == StatusFilter.done;
    // Finished tasks are listed in the main list for Done/All, and in "Recently done" otherwise.
    final finishedInList = showsFinished ? done : const <Task>[];
    final recentSection = showsFinished || status == StatusFilter.overdue ? const <Task>[] : recent;
    final nothingToShow = ranked.isEmpty && finishedInList.isEmpty;

    final header = Row(
      children: [
        onlyFinished
            ? Icon(Icons.check_circle_rounded, size: 22, color: context.panda.bamboo)
            : const LeafIcon(size: 22),
        const SizedBox(width: 8),
        Text(onlyFinished ? 'Done' : 'Do next', style: PandaText.title),
        const Spacer(),
        if (showSubtitle)
          Flexible(
            child: Text(
              onlyFinished ? 'Most recent first' : 'By deadline + priority',
              overflow: TextOverflow.ellipsis,
              style: PandaText.caption.copyWith(color: context.panda.muted),
            ),
          ),
      ],
    );

    Widget body;
    if (!hasAnyTasks) {
      body = const _Message(
        sleeping: true,
        title: 'No tasks yet',
        text: 'Add your first task and the panda will suggest what to do next.',
      );
    } else if (nothingToShow && filter.hasAnyFilter) {
      body = _Message(
        title: 'No tasks match',
        text: 'Try a different search or clear your filters.',
        action: OutlinedButton(
          onPressed: ref.read(taskFilterProvider.notifier).reset,
          child: const Text('Clear filters'),
        ),
      );
    } else if (nothingToShow) {
      body = const _Message(title: 'All done!', text: 'Everything is ticked off. Time for some bamboo.');
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ranked.isNotEmpty)
            Column(
              key: const ValueKey('do-next'),
              children: [
                for (final (i, r) in ranked.take(limit).indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        _RankBubble(rank: i + 1),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ConnectedTaskCard(task: r.task, tooltip: scorer.reason(r.task, now)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          if (finishedInList.isNotEmpty)
            _DoneColumn(
              key: const ValueKey('done-list'),
              title: ranked.isEmpty ? null : 'Done',
              tasks: finishedInList.take(limit).toList(),
              indent: ranked.isNotEmpty,
            ),
        ],
      );
    }

    final total = ranked.length + finishedInList.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 12),
        body,
        if (!nothingToShow)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.go('/tasks'),
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.chevron_right_rounded),
              label: Text(total > limit ? 'See all $total tasks' : 'See all tasks'),
            ),
          ),
        if (recentSection.isNotEmpty) _RecentlyDone(tasks: recentSection),
      ],
    );
  }
}

/// A short list of finished tasks (struck through, with a tick) that can be un-ticked.
class _DoneColumn extends StatelessWidget {
  const _DoneColumn({super.key, required this.tasks, this.title, this.indent = false});

  final String? title;
  final List<Task> tasks;

  /// Line the cards up with the numbered ones above them.
  final bool indent;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (title != null)
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 10),
          child: Text(title!, style: PandaText.heading),
        ),
      for (final t in tasks)
        Padding(
          padding: EdgeInsets.only(bottom: 10, left: indent ? 44 : 0),
          child: ConnectedTaskCard(task: t),
        ),
    ],
  );
}

/// "Recently done": the last few things you finished, collapsible.
class _RecentlyDone extends ConsumerStatefulWidget {
  const _RecentlyDone({required this.tasks});
  final List<Task> tasks;

  @override
  ConsumerState<_RecentlyDone> createState() => _RecentlyDoneState();
}

class _RecentlyDoneState extends ConsumerState<_RecentlyDone> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final shown = widget.tasks.take(3).toList();
    final more = widget.tasks.length - shown.length;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            label: 'Recently done, ${widget.tasks.length}',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _open = !_open),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline_rounded, size: 20, color: context.panda.bambooDark),
                    const SizedBox(width: 8),
                    Text('Recently done', style: PandaText.heading),
                    const SizedBox(width: 8),
                    Text('${widget.tasks.length}', style: PandaText.captionStrong.copyWith(color: context.panda.muted)),
                    const Spacer(),
                    Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: context.panda.muted),
                  ],
                ),
              ),
            ),
          ),
          if (_open) ...[
            const SizedBox(height: 4),
            _DoneColumn(key: const ValueKey('recently-done'), tasks: shown),
            if (more > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => ref.read(taskFilterProvider.notifier).setStatus(StatusFilter.done),
                  child: Text('Show all ${widget.tasks.length} finished'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _RankBubble extends StatelessWidget {
  const _RankBubble({required this.rank});
  final int rank;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Number $rank',
    excludeSemantics: true,
    child: Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: rank == 1 ? context.panda.ink : context.panda.bambooTint,
      ),
      child: Text(
        '$rank',
        style: PandaText.heading.copyWith(color: rank == 1 ? context.panda.rice : context.panda.bambooDark),
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.text, this.sleeping = false, this.action});
  final String title;
  final String text;
  final bool sleeping;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      children: [
        PandaMascot(size: 96, sleeping: sleeping),
        const SizedBox(height: 12),
        Text(title, style: PandaText.title, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(
          text,
          style: PandaText.body.copyWith(color: context.panda.muted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        action ??
            FilledButton.icon(
              onPressed: () => showTaskEditor(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add a task'),
            ),
      ],
    ),
  );
}

/// "This week": due / done / overdue counts and a progress bar. Each box opens the matching tasks.
class WeekSummaryCard extends ConsumerWidget {
  const WeekSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(weekSummaryProvider);
    final progress = s.dueThisWeek == 0 ? 0.0 : s.doneThisWeek / s.dueThisWeek;
    Widget stat(WeekView view, int n, String label, Color bg, Color fg) => Expanded(
      child: Semantics(
        button: true,
        label: '$n $label. Show these tasks.',
        excludeSemantics: true,
        child: Tooltip(
          message: 'See the tasks: ${view.title.toLowerCase()}',
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(PandaSizes.tileRadius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              hoverColor: fg.withValues(alpha: 0.08),
              onTap: () => showWeekTasks(context, view),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$n', style: PandaText.display.copyWith(color: fg)),
                    Row(
                      children: [
                        Flexible(
                          child: Text(label, style: PandaText.captionStrong.copyWith(color: fg)),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.chevron_right_rounded, size: 18, color: fg),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return PandaCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('This week', style: PandaText.title),
              const Spacer(),
              Text('Tap a box to see the tasks', style: PandaText.caption.copyWith(color: context.panda.muted)),
            ],
          ),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                stat(WeekView.due, s.dueThisWeek, 'due this week', context.panda.bambooTint, context.panda.bambooDark),
                const SizedBox(width: 12),
                stat(WeekView.done, s.doneThisWeek, 'done', context.panda.rice, context.panda.ink),
                const SizedBox(width: 12),
                stat(
                  WeekView.overdue,
                  s.overdue,
                  'overdue',
                  s.overdue > 0 ? context.panda.overdueTint : context.panda.rice,
                  s.overdue > 0 ? context.panda.overdue : context.panda.ink,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: context.panda.line,
              color: context.panda.bamboo,
              semanticsLabel: 'Weekly progress: ${s.doneThisWeek} of ${s.dueThisWeek} done',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.dueThisWeek == 0
                ? 'Nothing due this week yet.'
                : '${s.doneThisWeek} of ${s.dueThisWeek} done${progress >= 1 ? ' — amazing!' : ' — keep going!'}',
            style: PandaText.caption.copyWith(color: context.panda.muted),
          ),
        ],
      ),
    );
  }
}
