import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/panda_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/panda_mascot.dart';
import '../../core/widgets/pills.dart';
import '../../data/providers.dart';
import '../settings/sync_indicator.dart';
import '../tasks/task_editor.dart';
import 'welcome_controller.dart';
import 'widgets/calendar_panel.dart';
import 'widgets/do_next_list.dart';
import 'widgets/filter_bar.dart';

/// The home screen: greeting, calendar, "Do next" and this week's progress.
class WelcomePage extends ConsumerWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < Breakpoints.tablet) return const _PhoneWelcome();
    final desktop = width >= Breakpoints.desktop;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: _Greeting()),
              const SizedBox(width: 16),
              const SizedBox(width: 340, child: TaskSearchField()),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => showTaskEditor(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add task'),
              ),
              const SyncIndicator(),
            ],
          ),
          const SizedBox(height: 24),
          const FilterBar(),
          const SizedBox(height: 24),
          if (desktop)
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: CalendarPanel()),
                SizedBox(width: 28),
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PandaCard(child: DoNextList()),
                      SizedBox(height: 24),
                      WeekSummaryCard(),
                    ],
                  ),
                ),
              ],
            )
          else
            const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PandaCard(child: DoNextList()),
                SizedBox(height: 24),
                CalendarPanel(),
                SizedBox(height: 24),
                WeekSummaryCard(),
              ],
            ),
        ],
      ),
    );
  }
}

class _Greeting extends ConsumerWidget {
  const _Greeting({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider);
    final name = ref.watch(displayNameProvider).value;
    final summary = ref.watch(weekSummaryProvider);
    final greeting = name == null || name.isEmpty ? greetingFor(now) : '${greetingFor(now)}, $name';
    final subtitle = compact
        ? '${DateFormat('EEE d MMM').format(now)}${summary.overdue > 0 ? ' · ${summary.overdue} overdue' : ''}'
        : '${DateFormat('EEEE, d MMMM').format(now)} · '
              '${summary.dueThisWeek} task${summary.dueThisWeek == 1 ? '' : 's'} this week'
              '${summary.overdue > 0 ? ', ${summary.overdue} overdue' : ''}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greeting,
          style: compact ? PandaText.title : PandaText.display,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(subtitle, style: (compact ? PandaText.caption : PandaText.body).copyWith(color: PandaColors.muted)),
      ],
    );
  }
}

class _PhoneWelcome extends ConsumerStatefulWidget {
  const _PhoneWelcome();

  @override
  ConsumerState<_PhoneWelcome> createState() => _PhoneWelcomeState();
}

class _PhoneWelcomeState extends ConsumerState<_PhoneWelcome> {
  bool _searching = false;

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider);
    final selected = ref.watch(stripCalendarProvider.select((c) => c.selectedDay));
    final query = ref.watch(taskFilterProvider.select((f) => f.query));
    final showSearch = _searching || query.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 112),
      children: [
        Row(
          children: [
            const PandaMascot(size: 44),
            const SizedBox(width: 12),
            const Expanded(child: _Greeting(compact: true)),
            const SyncIndicator(),
            IconButton(
              tooltip: showSearch ? 'Close search' : 'Search',
              onPressed: () {
                if (showSearch) ref.read(taskFilterProvider.notifier).setQuery('');
                setState(() => _searching = !showSearch);
              },
              style: IconButton.styleFrom(
                backgroundColor: PandaColors.surface,
                side: const BorderSide(color: PandaColors.line, width: 1.5),
                minimumSize: const Size(48, 48),
              ),
              icon: Icon(showSearch ? Icons.close_rounded : Icons.search_rounded),
            ),
          ],
        ),
        if (showSearch) ...[const SizedBox(height: 12), const TaskSearchField(autofocus: true)],
        const SizedBox(height: 16),
        const WeekStrip(),
        if (!isSameDay(selected, now)) ...[
          const SizedBox(height: 16),
          PandaCard(
            padding: const EdgeInsets.all(16),
            child: SelectedDayTasks(
              provider: stripCalendarProvider,
              onClose: ref.read(stripCalendarProvider.notifier).goToToday,
            ),
          ),
        ],
        const SizedBox(height: 16),
        const CompactFilterBar(),
        const SizedBox(height: 16),
        const DoNextList(showSubtitle: false),
        const SizedBox(height: 8),
        const WeekSummaryCard(),
      ],
    );
  }
}
