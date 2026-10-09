import 'package:bamboozled/core/utils/dates.dart';
import 'package:bamboozled/data/providers.dart';
import 'package:bamboozled/data/repositories/task_repository.dart';
import 'package:bamboozled/domain/models/category.dart';
import 'package:bamboozled/domain/models/priority.dart';
import 'package:bamboozled/domain/models/task.dart';
import 'package:bamboozled/features/welcome/welcome_controller.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table_calendar/table_calendar.dart' show CalendarFormat;

import '../helpers.dart';

void main() {
  group('TaskFilter.matches', () {
    final now = testNow; // Thu 8 Oct 2026, 9 am
    final categories = {
      'teaching': Category(id: 'teaching', name: 'Teaching', color: const Color(0xFF9CC9E8), updatedAt: now),
      'admin': Category(id: 'admin', name: 'Admin', color: const Color(0xFFF2C879), updatedAt: now),
    };
    Task task({
      String title = 'Mark essays',
      String cat = 'teaching',
      Priority p = Priority.high,
      DateTime? due,
      DateTime? done,
      String? notes,
    }) => Task(
      id: title,
      title: title,
      dueAt: due ?? now.add(const Duration(days: 1)),
      priority: p,
      categoryId: cat,
      notes: notes,
      completedAt: done,
      createdAt: now,
      updatedAt: now,
    );

    test('the default filter shows to-do tasks of any category and priority', () {
      const f = TaskFilter();
      expect(f.matches(task(), now, categories), isTrue);
      expect(f.matches(task(done: now), now, categories), isFalse, reason: 'done tasks are hidden by default');
      expect(f.activeCount, 0);
      expect(f.hasAnyFilter, isFalse);
    });

    test('category filter accepts any of the chosen categories', () {
      const f = TaskFilter(categoryIds: {'admin'});
      expect(f.matches(task(cat: 'admin'), now, categories), isTrue);
      expect(f.matches(task(cat: 'teaching'), now, categories), isFalse);
      expect(const TaskFilter(categoryIds: {'admin', 'teaching'}).matches(task(), now, categories), isTrue);
    });

    test('priority filter is exact', () {
      const f = TaskFilter(priority: Priority.urgent);
      expect(f.matches(task(p: Priority.urgent), now, categories), isTrue);
      expect(f.matches(task(p: Priority.high), now, categories), isFalse);
    });

    test('status filters', () {
      final overdue = task(due: now.subtract(const Duration(days: 1)));
      final upcoming = task();
      final done = task(done: now, due: now.subtract(const Duration(days: 1)));
      bool m(StatusFilter s, Task t) => TaskFilter(status: s).matches(t, now, categories);
      expect(
        [m(StatusFilter.all, overdue), m(StatusFilter.all, upcoming), m(StatusFilter.all, done)],
        [true, true, true],
      );
      expect(
        [m(StatusFilter.todo, overdue), m(StatusFilter.todo, upcoming), m(StatusFilter.todo, done)],
        [true, true, false],
      );
      expect(
        [m(StatusFilter.overdue, overdue), m(StatusFilter.overdue, upcoming), m(StatusFilter.overdue, done)],
        [true, false, false],
        reason: 'finished tasks are never overdue',
      );
      expect(
        [m(StatusFilter.done, overdue), m(StatusFilter.done, upcoming), m(StatusFilter.done, done)],
        [false, false, true],
      );
    });

    test('search ignores case and surrounding spaces, and looks in title, notes and category name', () {
      bool m(String q, Task t) => TaskFilter(query: q).matches(t, now, categories);
      expect(m('  ESSAY ', task()), isTrue);
      expect(m('rubric', task(notes: 'Use the Rubric from drive')), isTrue);
      expect(m('teach', task()), isTrue, reason: 'category name');
      expect(m('zzz', task()), isFalse);
      expect(m('   ', task()), isTrue, reason: 'a blank search matches everything');
    });

    test('filters combine with AND', () {
      const f = TaskFilter(categoryIds: {'teaching'}, priority: Priority.high, query: 'essay');
      expect(f.matches(task(), now, categories), isTrue);
      expect(f.matches(task(cat: 'admin'), now, categories), isFalse);
      expect(f.matches(task(p: Priority.low), now, categories), isFalse);
      expect(f.matches(task(title: 'Quiz'), now, categories), isFalse);
    });

    test('activeCount counts category, priority and status (not search); hasAnyFilter includes search', () {
      const f = TaskFilter(categoryIds: {'a'}, priority: Priority.low, status: StatusFilter.done, query: 'x');
      expect(f.activeCount, 3);
      expect(const TaskFilter(query: 'x').activeCount, 0);
      expect(const TaskFilter(query: 'x').hasAnyFilter, isTrue);
      expect(const TaskFilter(status: StatusFilter.all).activeCount, 1);
    });
  });

  group('providers', () {
    late TestApp app;
    late ProviderContainer container;

    setUp(() async {
      app = await TestApp.create();
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(app.db),
          taskRepositoryProvider.overrideWithValue(app.repo),
          clockProvider.overrideWith(FixedClock.new),
        ],
      );
      // Keep the stream providers alive and wait for their first values.
      container.listen(tasksProvider, (_, _) {});
      container.listen(categoriesProvider, (_, _) {});
      await container.read(tasksProvider.future);
      await container.read(categoriesProvider.future);
    });

    tearDown(() async {
      container.dispose();
      await app.repo.dispose();
      await app.db.close();
    });

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));
    TaskFilterNotifier filter() => container.read(taskFilterProvider.notifier);
    List<String> ranked() => container.read(rankedTasksProvider).map((r) => r.task.title).toList();

    test('categories load in order and are looked up by id', () {
      final map = container.read(categoryMapProvider);
      expect(map.keys, containsAll(['general', 'teaching', 'admin', 'meetings', 'cca', 'personal']));
      expect(map['teaching']!.name, 'Teaching');
    });

    test('rankedTasks is the Do-next order for incomplete tasks', () {
      expect(ranked(), [
        'Submit term report',
        'Mark 3A essays',
        'Reply to parent emails',
        'Plan CCA trip',
        'Prepare Sec 2 quiz',
        'Staff meeting slides',
        'Book dentist',
      ]);
    });

    test('changing filters changes the ranked list', () async {
      filter().toggleCategory('teaching');
      expect(ranked(), ['Mark 3A essays', 'Prepare Sec 2 quiz']);
      filter().toggleCategory('teaching');
      expect(container.read(taskFilterProvider).categoryIds, isEmpty);

      filter().setPriority(Priority.urgent);
      expect(ranked(), ['Plan CCA trip']);
      filter().setPriority(null);

      filter().setQuery('dentist');
      expect(ranked(), ['Book dentist']);
      filter().reset();
      expect(container.read(taskFilterProvider).hasAnyFilter, isFalse);
      expect(ranked(), hasLength(7));
    });

    test('showAllCategories clears the category filter only', () {
      filter()
        ..toggleCategory('admin')
        ..setPriority(Priority.low)
        ..showAllCategories();
      final f = container.read(taskFilterProvider);
      expect(f.categoryIds, isEmpty);
      expect(f.priority, Priority.low);
    });

    test('the Done status shows finished tasks, which are not ranked', () {
      filter().setStatus(StatusFilter.done);
      expect(container.read(filteredTasksProvider).map((t) => t.title), ['Print worksheets']);
      expect(ranked(), isEmpty);
    });

    test('tasksByDay groups filtered tasks by due date', () {
      final byDay = container.read(tasksByDayProvider);
      expect(byDay[DateTime(2026, 10, 8)]!.map((t) => t.title), ['Reply to parent emails']);
      expect(byDay[DateTime(2026, 10, 15)]!.single.title, 'Plan CCA trip');
      expect(byDay.containsKey(DateTime(2026, 10, 6)), isFalse, reason: 'the done task is filtered out');

      filter().setStatus(StatusFilter.all);
      expect(container.read(tasksByDayProvider).containsKey(DateTime(2026, 10, 6)), isTrue);
    });

    test('weekSummary counts Monday–Sunday and ignores filters', () {
      filter().setQuery('no such task');
      final s = container.read(weekSummaryProvider);
      // Week of 5–11 Oct: report (7th), essays (9th), parent emails (8th), worksheets (6th, done).
      expect(s.dueThisWeek, 4);
      expect(s.doneThisWeek, 1);
      expect(s.overdue, 1);
    });

    test('new tasks appear in the providers straight away', () async {
      await app.repo.addTask(
        TaskDraft(title: 'Brand new', dueAt: DateTime(2026, 10, 8, 23), priority: Priority.urgent, categoryId: 'admin'),
      );
      await settle();
      expect(ranked().first, 'Submit term report');
      expect(ranked(), contains('Brand new'));
      expect(container.read(weekSummaryProvider).dueThisWeek, 5);
    });
  });

  group('calendar state', () {
    late ProviderContainer container;
    late TestApp app;

    setUp(() async {
      app = await TestApp.create(withSampleTasks: false);
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(app.db),
          taskRepositoryProvider.overrideWithValue(app.repo),
          clockProvider.overrideWith(FixedClock.new),
        ],
      );
    });
    tearDown(() async {
      container.dispose();
      await app.repo.dispose();
      await app.db.close();
    });

    test('starts on today in month view; the phone strip starts in week view', () {
      final cal = container.read(calendarProvider);
      expect(cal.selectedDay, DateTime(2026, 10, 8));
      expect(cal.focusedDay, DateTime(2026, 10, 8));
      expect(cal.format, CalendarFormat.month);
      expect(container.read(stripCalendarProvider).format, CalendarFormat.week);
    });

    test('desktop and phone calendars are independent', () {
      container.read(calendarProvider.notifier).select(DateTime(2026, 10, 20, 15));
      expect(container.read(calendarProvider).selectedDay, DateTime(2026, 10, 20), reason: 'time is dropped');
      expect(container.read(stripCalendarProvider).selectedDay, DateTime(2026, 10, 8));
    });

    test('paging moves a month in month view and a week in week view', () {
      final n = container.read(calendarProvider.notifier);
      n.page(1);
      expect(container.read(calendarProvider).focusedDay, DateTime(2026, 11, 1));
      n.page(-2);
      expect(container.read(calendarProvider).focusedDay, DateTime(2026, 9, 1));

      n.setFormat(CalendarFormat.week);
      n.focus(DateTime(2026, 10, 8));
      n.page(1);
      expect(container.read(calendarProvider).focusedDay, DateTime(2026, 10, 15));
      n.page(-1);
      n.page(-1);
      expect(container.read(calendarProvider).focusedDay, DateTime(2026, 10, 1));
    });

    test('paging across a year boundary', () {
      final n = container.read(calendarProvider.notifier)..focus(DateTime(2026, 12, 15));
      n.page(1);
      expect(container.read(calendarProvider).focusedDay, DateTime(2027, 1, 1));
    });

    test('goToToday returns to the current day from anywhere', () {
      final n = container.read(calendarProvider.notifier);
      n.select(DateTime(2027, 3, 3));
      n.goToToday();
      final cal = container.read(calendarProvider);
      expect(isSameDay(cal.selectedDay, testNow), isTrue);
      expect(isSameDay(cal.focusedDay, testNow), isTrue);
    });

    test('switching format keeps the selected day', () {
      final n = container.read(calendarProvider.notifier);
      n.select(DateTime(2026, 10, 12));
      n.setFormat(CalendarFormat.week);
      expect(container.read(calendarProvider).selectedDay, DateTime(2026, 10, 12));
      expect(container.read(calendarProvider).format, CalendarFormat.week);
    });
  });
}
