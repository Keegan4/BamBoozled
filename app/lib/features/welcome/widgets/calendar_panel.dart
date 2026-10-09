import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart'
    show AvailableGestures, CalendarBuilders, CalendarFormat, StartingDayOfWeek, TableCalendar;

import '../../../core/theme/colors.dart';
import '../../../core/theme/panda_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/pills.dart';
import '../../../data/providers.dart';
import '../../../domain/models/task.dart';
import '../../tasks/task_actions.dart';
import '../../tasks/task_editor.dart';
import '../welcome_controller.dart';

/// Desktop calendar card: month/week grid with category dots, then the
/// tasks due on the selected day.
class CalendarPanel extends ConsumerWidget {
  const CalendarPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cal = ref.watch(calendarProvider);
    final notifier = ref.read(calendarProvider.notifier);
    return PandaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Wraps onto a second line in narrow windows instead of overflowing.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: cal.format == CalendarFormat.month ? 'Previous month' : 'Previous week',
                    onPressed: () => notifier.page(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Text(DateFormat('MMMM y').format(cal.focusedDay), style: PandaText.title),
                  IconButton(
                    tooltip: cal.format == CalendarFormat.month ? 'Next month' : 'Next week',
                    onPressed: () => notifier.page(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(onPressed: notifier.goToToday, child: const Text('Today')),
                  const SizedBox(width: 8),
                  _FormatToggle(format: cal.format, onChanged: notifier.setFormat),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          PandaCalendar(provider: calendarProvider, rowHeight: 72),
          const Divider(height: 32),
          SelectedDayTasks(provider: calendarProvider),
        ],
      ),
    );
  }
}

/// Phone week strip that expands to the full month.
class WeekStrip extends ConsumerWidget {
  const WeekStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cal = ref.watch(stripCalendarProvider);
    final notifier = ref.read(stripCalendarProvider.notifier);
    final month = cal.format == CalendarFormat.month;
    return PandaCard(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(width: 4),
              Expanded(child: Text(DateFormat('MMMM y').format(cal.focusedDay), style: PandaText.heading)),
              TextButton.icon(
                onPressed: () => notifier.setFormat(month ? CalendarFormat.week : CalendarFormat.month),
                iconAlignment: IconAlignment.end,
                icon: Icon(month ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                label: Text(month ? 'Week' : 'Month'),
                style: TextButton.styleFrom(foregroundColor: PandaColors.ink, backgroundColor: PandaColors.rice),
              ),
            ],
          ),
          const SizedBox(height: 4),
          PandaCalendar(provider: stripCalendarProvider, rowHeight: 64),
        ],
      ),
    );
  }
}

class _FormatToggle extends StatelessWidget {
  const _FormatToggle({required this.format, required this.onChanged});
  final CalendarFormat format;
  final ValueChanged<CalendarFormat> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<CalendarFormat>(
    segments: const [
      ButtonSegment(value: CalendarFormat.week, label: Text('Week')),
      ButtonSegment(value: CalendarFormat.month, label: Text('Month')),
    ],
    selected: {format},
    showSelectedIcon: false,
    onSelectionChanged: (s) => onChanged(s.first),
    style: SegmentedButton.styleFrom(
      backgroundColor: PandaColors.rice,
      selectedBackgroundColor: PandaColors.ink,
      selectedForegroundColor: PandaColors.rice,
      foregroundColor: PandaColors.ink,
      side: const BorderSide(color: PandaColors.line),
      minimumSize: const Size(80, 44),
      textStyle: PandaText.bodyStrong,
    ),
  );
}

/// The calendar grid itself. Each day shows up to three dots in the colours
/// of the categories due that day.
class PandaCalendar extends ConsumerWidget {
  const PandaCalendar({super.key, required this.provider, required this.rowHeight});

  final NotifierProvider<CalendarNotifier, CalendarState> provider;
  final double rowHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cal = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    final byDay = ref.watch(tasksByDayProvider);
    final categories = ref.watch(categoryMapProvider);
    final now = ref.watch(clockProvider);

    Widget day(BuildContext context, DateTime day, DateTime focused) {
      final tasks = byDay[dateOnly(day)] ?? const <Task>[];
      final colors = <Color>[];
      for (final t in [...tasks.where((t) => !t.isDone), ...tasks.where((t) => t.isDone)]) {
        final c = categories[t.categoryId]?.color ?? PandaColors.stone;
        if (!colors.contains(c)) colors.add(c);
      }
      return _DayCell(
        day: day,
        today: isSameDay(day, now),
        selected: isSameDay(day, cal.selectedDay),
        outside: cal.format == CalendarFormat.month && day.month != focused.month,
        dots: colors.take(3).toList(),
      );
    }

    return TableCalendar<Task>(
      firstDay: DateTime(now.year - 3),
      lastDay: DateTime(now.year + 4, 12, 31),
      focusedDay: cal.focusedDay,
      currentDay: now,
      calendarFormat: cal.format,
      availableCalendarFormats: const {CalendarFormat.month: 'Month', CalendarFormat.week: 'Week'},
      headerVisible: false,
      startingDayOfWeek: StartingDayOfWeek.monday,
      rowHeight: rowHeight,
      daysOfWeekHeight: 28,
      availableGestures: AvailableGestures.horizontalSwipe,
      selectedDayPredicate: (d) => isSameDay(d, cal.selectedDay),
      onDaySelected: (selected, _) => notifier.select(selected),
      onPageChanged: notifier.focus,
      onFormatChanged: notifier.setFormat,
      calendarBuilders: CalendarBuilders<Task>(
        prioritizedBuilder: day,
        dowBuilder: (context, d) => Center(
          child: Text(DateFormat('EEE').format(d), style: PandaText.captionStrong.copyWith(color: PandaColors.muted)),
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.today,
    required this.selected,
    required this.outside,
    required this.dots,
  });

  final DateTime day;
  final bool today;
  final bool selected;
  final bool outside;
  final List<Color> dots;

  @override
  Widget build(BuildContext context) {
    // table_calendar gives each day its own screen-reader label, e.g. "Thursday, October 15, 2026".
    return ExcludeSemantics(
      child: Opacity(
        opacity: outside ? 0.45 : 1,
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: selected ? PandaColors.bambooTint : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: today ? PandaColors.bamboo : (selected ? PandaColors.ink : null),
                ),
                child: Text(
                  '${day.day}',
                  style: PandaText.bodyStrong.copyWith(color: selected && !today ? PandaColors.rice : PandaColors.ink),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 8,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final c in dots)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tasks due on the calendar's selected day (respecting filters).
class SelectedDayTasks extends ConsumerWidget {
  const SelectedDayTasks({super.key, required this.provider, this.onClose});

  final NotifierProvider<CalendarNotifier, CalendarState> provider;

  /// Shows a close button (phone) that returns the selection to today.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(provider.select((c) => c.selectedDay));
    final now = ref.watch(clockProvider);
    final tasks = ref.watch(tasksByDayProvider)[selected] ?? const <Task>[];
    final title = isSameDay(selected, now) ? 'Today' : DateFormat('EEEE d MMMM').format(selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: PandaText.heading)),
            TextButton.icon(
              onPressed: () => showTaskEditor(context, initialDay: selected),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add'),
            ),
            if (onClose != null)
              IconButton(tooltip: 'Back to today', onPressed: onClose, icon: const Icon(Icons.close_rounded)),
          ],
        ),
        const SizedBox(height: 8),
        if (tasks.isEmpty)
          _EmptyDay(hidden: ref.watch(hiddenOnDayProvider(selected)))
        else
          for (final t in tasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ConnectedTaskCard(task: t),
            ),
      ],
    );
  }
}

/// Shown when no task is listed for the selected day. If tasks exist but are hidden, say why, so
/// they don't look like they've gone missing.
class _EmptyDay extends ConsumerWidget {
  const _EmptyDay({required this.hidden});
  final int hidden;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(taskFilterProvider);
    final style = PandaText.body.copyWith(color: PandaColors.muted);
    if (hidden == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('Nothing due — enjoy the bamboo.', style: style),
      );
    }
    final noun = hidden == 1 ? '1 task is' : '$hidden tasks are';
    // Only the default "To do" view is on: what's hidden is finished work.
    if (!filter.hasAnyFilter) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(hidden == 1 ? 'The task due is done.' : 'Everything due is done.', style: style),
      );
    }
    // The banner at the top of the page has the "Clear filters" button.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text('$noun hidden by your filters.', style: style),
    );
  }
}
