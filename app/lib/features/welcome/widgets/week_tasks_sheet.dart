import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/breakpoints.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/panda_theme.dart';
import '../../tasks/task_actions.dart';
import '../welcome_controller.dart';

/// Which list the "This week" sheet shows.
enum WeekView {
  due('Due', 'Due this week', 'Nothing is due this week yet.'),
  done('Done', 'Done this week', 'Nothing finished yet. Tick a task off and it will show up here.'),
  overdue('Overdue', 'Overdue', 'Nothing is overdue. Well done!');

  const WeekView(this.tab, this.title, this.empty);
  final String tab;
  final String title;
  final String empty;
}

/// Opens the list of this week's tasks: a dialog on wide screens, a bottom sheet on phones.
Future<void> showWeekTasks(BuildContext context, WeekView initial) {
  final sheet = WeekTasksSheet(initial: initial);
  if (Breakpoints.isPhone(context)) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: PandaColors.surface,
      builder: (_) => sheet,
    );
  }
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: PandaColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: sheet,
      ),
    ),
  );
}

/// The tasks behind the Due / Done / Overdue boxes. Tasks can be ticked off or opened from here, and
/// the lists update as you do. Filters on the home page don't apply, so the lists match the numbers.
class WeekTasksSheet extends ConsumerStatefulWidget {
  const WeekTasksSheet({super.key, required this.initial});

  final WeekView initial;

  @override
  ConsumerState<WeekTasksSheet> createState() => _WeekTasksSheetState();
}

class _WeekTasksSheetState extends ConsumerState<WeekTasksSheet> {
  late WeekView _view = widget.initial;

  @override
  Widget build(BuildContext context) {
    final week = ref.watch(weekTasksProvider);
    final tasks = switch (_view) {
      WeekView.due => week.due,
      WeekView.done => week.done,
      WeekView.overdue => week.overdue,
    };
    final counts = {
      WeekView.due: week.due.length,
      WeekView.done: week.done.length,
      WeekView.overdue: week.overdue.length,
    };
    final phone = Breakpoints.isPhone(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(24, phone ? 0 : 24, 16, 8),
          child: Row(
            children: [
              Expanded(child: Text('This week', style: PandaText.title)),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                style: IconButton.styleFrom(backgroundColor: PandaColors.rice, minimumSize: const Size(48, 48)),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SegmentedButton<WeekView>(
            showSelectedIcon: false,
            segments: [
              for (final v in WeekView.values)
                ButtonSegment(
                  value: v,
                  label: Text('${v.tab} ${counts[v]}', maxLines: 1, overflow: TextOverflow.fade),
                ),
            ],
            selected: {_view},
            onSelectionChanged: (s) => setState(() => _view = s.first),
            style: SegmentedButton.styleFrom(
              backgroundColor: PandaColors.rice,
              selectedBackgroundColor: PandaColors.ink,
              selectedForegroundColor: PandaColors.rice,
              foregroundColor: PandaColors.ink,
              side: const BorderSide(color: PandaColors.line),
              minimumSize: const Size(0, 48),
              textStyle: PandaText.bodyStrong,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Flexible(
          child: tasks.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  child: Text(_view.empty, style: PandaText.body.copyWith(color: PandaColors.muted)),
                )
              : ListView(
                  key: ValueKey('week-${_view.name}'),
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_view.title, style: PandaText.heading),
                    ),
                    for (final t in tasks)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: ConnectedTaskCard(task: t),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
