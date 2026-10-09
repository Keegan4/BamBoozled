import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart' show CalendarFormat;

import '../../core/utils/dates.dart';
import '../../data/providers.dart';
import '../../domain/models/category.dart';
import '../../domain/models/priority.dart';
import '../../domain/models/task.dart';
import '../../domain/services/priority_scorer.dart';

enum StatusFilter {
  all('All'),
  todo('To do'),
  overdue('Overdue'),
  done('Done');

  const StatusFilter(this.label);
  final String label;
}

class TaskFilter {
  const TaskFilter({this.categoryIds = const {}, this.priority, this.status = StatusFilter.todo, this.query = ''});

  /// Empty means all categories.
  final Set<String> categoryIds;

  /// Null means any priority.
  final Priority? priority;
  final StatusFilter status;
  final String query;

  /// Number of filters that differ from the defaults (shown on the phone Filter button).
  int get activeCount =>
      (categoryIds.isNotEmpty ? 1 : 0) + (priority != null ? 1 : 0) + (status != StatusFilter.todo ? 1 : 0);

  bool get hasAnyFilter => activeCount > 0 || query.trim().isNotEmpty;

  /// Plain-English summary of what is being filtered, e.g. ["General", "High priority", "Done"].
  /// The default Status (To do) is not mentioned.
  List<String> describe(Map<String, Category> categories) => [
    if (categoryIds.isNotEmpty) categoryIds.map((id) => categories[id]?.name ?? 'Unknown category').join(' or '),
    if (priority != null) '${priority!.label} priority',
    if (status != StatusFilter.todo) status.label,
    if (query.trim().isNotEmpty) '“${query.trim()}”',
  ];

  TaskFilter copyWith({
    Set<String>? categoryIds,
    Priority? Function()? priority,
    StatusFilter? status,
    String? query,
  }) => TaskFilter(
    categoryIds: categoryIds ?? this.categoryIds,
    priority: priority != null ? priority() : this.priority,
    status: status ?? this.status,
    query: query ?? this.query,
  );

  /// Whether [task] passes every filter. Search matches title, notes and category name.
  bool matches(Task task, DateTime now, Map<String, Category> categories) {
    if (categoryIds.isNotEmpty && !categoryIds.contains(task.categoryId)) return false;
    if (priority != null && task.priority != priority) return false;
    final ok = switch (status) {
      StatusFilter.all => true,
      StatusFilter.todo => !task.isDone,
      StatusFilter.overdue => task.isOverdue(now),
      StatusFilter.done => task.isDone,
    };
    if (!ok) return false;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return task.title.toLowerCase().contains(q) ||
        (task.notes?.toLowerCase().contains(q) ?? false) ||
        (categories[task.categoryId]?.name.toLowerCase().contains(q) ?? false);
  }
}

class TaskFilterNotifier extends Notifier<TaskFilter> {
  @override
  TaskFilter build() => const TaskFilter();

  void toggleCategory(String id) {
    final ids = {...state.categoryIds};
    ids.contains(id) ? ids.remove(id) : ids.add(id);
    state = state.copyWith(categoryIds: ids);
  }

  void showAllCategories() => state = state.copyWith(categoryIds: {});
  void setPriority(Priority? p) => state = state.copyWith(priority: () => p);
  void setStatus(StatusFilter s) => state = state.copyWith(status: s);
  void setQuery(String q) => state = state.copyWith(query: q);
  void reset() => state = const TaskFilter();
}

final taskFilterProvider = NotifierProvider<TaskFilterNotifier, TaskFilter>(TaskFilterNotifier.new);

final priorityScorerProvider = Provider((ref) => const PriorityScorer());

/// All tasks that pass the current filters.
final filteredTasksProvider = Provider<List<Task>>((ref) {
  final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
  final filter = ref.watch(taskFilterProvider);
  final now = ref.watch(clockProvider);
  final categories = ref.watch(categoryMapProvider);
  return [
    for (final t in tasks)
      if (filter.matches(t, now, categories)) t,
  ];
});

/// Filtered, incomplete tasks in recommended order.
final rankedTasksProvider = Provider<List<RankedTask>>(
  (ref) => ref.watch(priorityScorerProvider).rank(ref.watch(filteredTasksProvider), ref.watch(clockProvider)),
);

/// Filtered tasks grouped by due day (for the calendar).
final tasksByDayProvider = Provider<Map<DateTime, List<Task>>>((ref) {
  final byDay = <DateTime, List<Task>>{};
  for (final t in ref.watch(filteredTasksProvider)) {
    (byDay[dateOnly(t.dueAt)] ??= []).add(t);
  }
  return byDay;
});

/// The tasks behind each box in "This week". Ignores the filters, so the lists always add up to
/// the numbers shown.
class WeekTasks {
  const WeekTasks({required this.due, required this.done, required this.overdue});

  /// Everything due Monday–Sunday this week, finished or not, earliest first.
  final List<Task> due;

  /// The finished ones among [due], most recently finished first.
  final List<Task> done;

  /// Every unfinished task that is past its deadline (any week), oldest first.
  final List<Task> overdue;
}

final weekTasksProvider = Provider<WeekTasks>((ref) {
  final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
  final now = ref.watch(clockProvider);
  final start = startOfWeek(now);
  final end = start.add(const Duration(days: 7));
  final due = [
    for (final t in tasks)
      if (!t.dueAt.isBefore(start) && t.dueAt.isBefore(end)) t,
  ]..sort((a, b) => a.dueAt.compareTo(b.dueAt));
  final done = [
    for (final t in due)
      if (t.isDone) t,
  ]..sort((a, b) => b.completedAt!.compareTo(a.completedAt!));
  final overdue = [
    for (final t in tasks)
      if (t.isOverdue(now)) t,
  ]..sort((a, b) => a.dueAt.compareTo(b.dueAt));
  return WeekTasks(due: due, done: done, overdue: overdue);
});

class WeekSummary {
  const WeekSummary({required this.dueThisWeek, required this.doneThisWeek, required this.overdue});
  final int dueThisWeek;
  final int doneThisWeek;
  final int overdue;
}

/// Counts across all tasks (ignoring filters) for Monday–Sunday of this week.
final weekSummaryProvider = Provider<WeekSummary>((ref) {
  final week = ref.watch(weekTasksProvider);
  return WeekSummary(dueThisWeek: week.due.length, doneThisWeek: week.done.length, overdue: week.overdue.length);
});

/// Finished tasks that pass the category, priority and search filters, most recently finished
/// first. (The Status filter is ignored here: it decides *whether* these are shown.)
final filteredDoneProvider = Provider<List<Task>>((ref) {
  final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
  final filter = ref.watch(taskFilterProvider).copyWith(status: StatusFilter.all);
  final now = ref.watch(clockProvider);
  final categories = ref.watch(categoryMapProvider);
  return [
    for (final t in tasks)
      if (t.isDone && filter.matches(t, now, categories)) t,
  ]..sort((a, b) => b.completedAt!.compareTo(a.completedAt!));
});

/// Tasks finished within the last week: shown under "Do next" so a task you tick off moves
/// somewhere visible instead of just disappearing.
final recentlyDoneProvider = Provider<List<Task>>((ref) {
  final cutoff = ref.watch(clockProvider).subtract(const Duration(days: 7));
  return [
    for (final t in ref.watch(filteredDoneProvider))
      if (t.completedAt!.isAfter(cutoff)) t,
  ];
});

/// How many tasks on [day] the current filters are hiding (ignores deleted tasks).
final hiddenOnDayProvider = Provider.family<int, DateTime>((ref, day) {
  final all = ref.watch(tasksProvider).value ?? const <Task>[];
  final shown = ref.watch(tasksByDayProvider)[day]?.length ?? 0;
  final total = all.where((t) => dateOnly(t.dueAt) == day).length;
  return total - shown;
});

class CalendarState {
  const CalendarState({required this.selectedDay, required this.focusedDay, required this.format});
  final DateTime selectedDay;
  final DateTime focusedDay;
  final CalendarFormat format;

  CalendarState copyWith({DateTime? selectedDay, DateTime? focusedDay, CalendarFormat? format}) => CalendarState(
    selectedDay: selectedDay ?? this.selectedDay,
    focusedDay: focusedDay ?? this.focusedDay,
    format: format ?? this.format,
  );
}

class CalendarNotifier extends Notifier<CalendarState> {
  @override
  CalendarState build() {
    final today = dateOnly(ref.read(clockProvider));
    return CalendarState(selectedDay: today, focusedDay: today, format: CalendarFormat.month);
  }

  void select(DateTime day) => state = state.copyWith(selectedDay: dateOnly(day), focusedDay: dateOnly(day));
  void focus(DateTime day) => state = state.copyWith(focusedDay: dateOnly(day));
  void setFormat(CalendarFormat f) => state = state.copyWith(format: f);

  void goToToday() {
    final today = dateOnly(ref.read(clockProvider));
    state = state.copyWith(selectedDay: today, focusedDay: today);
  }

  /// Moves one week or one month back (-1) or forward (+1).
  void page(int direction) {
    final f = state.focusedDay;
    state = state.copyWith(
      focusedDay: state.format == CalendarFormat.month
          ? DateTime(f.year, f.month + direction, 1)
          : f.add(Duration(days: 7 * direction)),
    );
  }
}

final calendarProvider = NotifierProvider<CalendarNotifier, CalendarState>(CalendarNotifier.new);

/// Separate calendar state for the phone's week strip (starts in week view).
class StripCalendarNotifier extends CalendarNotifier {
  @override
  CalendarState build() => super.build().copyWith(format: CalendarFormat.week);
}

final stripCalendarProvider = NotifierProvider<CalendarNotifier, CalendarState>(StripCalendarNotifier.new);
