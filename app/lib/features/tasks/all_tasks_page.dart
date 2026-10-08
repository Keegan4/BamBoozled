import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/panda_theme.dart';
import '../../data/providers.dart';
import '../welcome/welcome_controller.dart';
import '../welcome/widgets/filter_bar.dart';
import 'task_actions.dart';

/// Every task matching the filters. To-do tasks come in "Do next" order,
/// followed by finished ones (when the Status filter includes them).
class AllTasksPage extends ConsumerWidget {
  const AllTasksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone = Breakpoints.isPhone(context);
    final ranked = ref.watch(rankedTasksProvider);
    final done = ref.watch(filteredTasksProvider).where((t) => t.isDone).toList()
      ..sort((a, b) => b.completedAt!.compareTo(a.completedAt!));
    final scorer = ref.watch(priorityScorerProvider);
    final now = ref.watch(clockProvider);
    return ListView(
      padding: EdgeInsets.fromLTRB(phone ? 16 : 40, phone ? 12 : 32, phone ? 16 : 40, 112),
      children: [
        Row(
          children: [
            IconButton(tooltip: 'Back', onPressed: () => context.go('/'), icon: const Icon(Icons.arrow_back_rounded)),
            const SizedBox(width: 4),
            Text('All tasks', style: phone ? PandaText.title : PandaText.display),
          ],
        ),
        const SizedBox(height: 16),
        const TaskSearchField(),
        const SizedBox(height: 12),
        if (phone) const CompactFilterBar() else const FilterBar(),
        const SizedBox(height: 16),
        if (ranked.isEmpty && done.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('No tasks match.', style: PandaText.body.copyWith(color: PandaColors.muted)),
          ),
        for (final r in ranked)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ConnectedTaskCard(task: r.task, tooltip: scorer.reason(r.task, now)),
          ),
        if (done.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Done', style: PandaText.heading),
          const SizedBox(height: 8),
          for (final t in done)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ConnectedTaskCard(task: t),
            ),
        ],
      ],
    );
  }
}
