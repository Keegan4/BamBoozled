import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/panda_theme.dart';
import '../../../core/widgets/leaf_icon.dart';
import '../../../core/widgets/panda_mascot.dart';
import '../../../core/widgets/pills.dart';
import '../../../data/providers.dart';
import '../../tasks/task_actions.dart';
import '../../tasks/task_editor.dart';
import '../welcome_controller.dart';

/// "Do next": the top tasks in recommended order, each with its rank.
class DoNextList extends ConsumerWidget {
  const DoNextList({super.key, this.limit = 5, this.showSubtitle = true});

  final int limit;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ranked = ref.watch(rankedTasksProvider);
    final scorer = ref.watch(priorityScorerProvider);
    final now = ref.watch(clockProvider);
    final filter = ref.watch(taskFilterProvider);
    final hasAnyTasks = (ref.watch(tasksProvider).value ?? const []).isNotEmpty;

    final header = Row(
      children: [
        const LeafIcon(size: 22),
        const SizedBox(width: 8),
        const Text('Do next', style: PandaText.title),
        const Spacer(),
        if (showSubtitle)
          Flexible(
            child: Text(
              'By deadline + priority',
              overflow: TextOverflow.ellipsis,
              style: PandaText.caption.copyWith(color: PandaColors.muted),
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
    } else if (ranked.isEmpty && filter.hasAnyFilter) {
      body = _Message(
        title: 'No tasks match',
        text: 'Try a different search or clear your filters.',
        action: OutlinedButton(
          onPressed: ref.read(taskFilterProvider.notifier).reset,
          child: const Text('Clear filters'),
        ),
      );
    } else if (ranked.isEmpty) {
      body = const _Message(title: 'All done!', text: 'Everything is ticked off. Time for some bamboo.');
    } else {
      body = Column(
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
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 12),
        body,
        if (ranked.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.go('/tasks'),
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.chevron_right_rounded),
              label: Text(ranked.length > limit ? 'See all ${ranked.length} tasks' : 'See all tasks'),
            ),
          ),
      ],
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
      decoration: BoxDecoration(shape: BoxShape.circle, color: rank == 1 ? PandaColors.ink : PandaColors.bambooTint),
      child: Text(
        '$rank',
        style: PandaText.heading.copyWith(color: rank == 1 ? PandaColors.rice : PandaColors.bambooDark),
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
          style: PandaText.body.copyWith(color: PandaColors.muted),
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

/// "This week": due / done / overdue counts and a progress bar.
class WeekSummaryCard extends ConsumerWidget {
  const WeekSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(weekSummaryProvider);
    final progress = s.dueThisWeek == 0 ? 0.0 : s.doneThisWeek / s.dueThisWeek;
    Widget stat(int n, String label, Color bg, Color fg) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(PandaSizes.tileRadius)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$n', style: PandaText.display.copyWith(color: fg)),
            Text(label, style: PandaText.captionStrong.copyWith(color: fg)),
          ],
        ),
      ),
    );
    return PandaCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('This week', style: PandaText.title),
          const SizedBox(height: 14),
          Row(
            children: [
              stat(s.dueThisWeek, 'due this week', PandaColors.bambooTint, PandaColors.bambooDark),
              const SizedBox(width: 12),
              stat(s.doneThisWeek, 'done', PandaColors.rice, PandaColors.ink),
              const SizedBox(width: 12),
              stat(
                s.overdue,
                'overdue',
                s.overdue > 0 ? PandaColors.overdueTint : PandaColors.rice,
                s.overdue > 0 ? PandaColors.overdue : PandaColors.ink,
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: PandaColors.line,
              color: PandaColors.bamboo,
              semanticsLabel: 'Weekly progress: ${s.doneThisWeek} of ${s.dueThisWeek} done',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.dueThisWeek == 0
                ? 'Nothing due this week yet.'
                : '${s.doneThisWeek} of ${s.dueThisWeek} done${progress >= 1 ? ' — amazing!' : ' — keep going!'}',
            style: PandaText.caption.copyWith(color: PandaColors.muted),
          ),
        ],
      ),
    );
  }
}
