import 'package:bamboozled/core/theme/colors.dart';
import 'package:bamboozled/core/widgets/pills.dart';
import 'package:bamboozled/data/repositories/task_repository.dart';
import 'package:bamboozled/domain/models/priority.dart';
import 'package:bamboozled/features/tasks/task_editor.dart';
import 'package:bamboozled/features/tasks/widgets/task_card.dart';
import 'package:bamboozled/features/welcome/widgets/calendar_panel.dart';
import 'package:bamboozled/features/welcome/widgets/do_next_list.dart';
import 'package:bamboozled/features/welcome/widgets/week_tasks_sheet.dart';
import 'package:bamboozled/data/local/app_database.dart' show TasksCompanion;
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

const phone = Size(412, 915);
const tall = Size(1440, 2400);

/// Titles in a section of the Do next card.
List<String> titlesIn(WidgetTester tester, String key) => tester
    .widgetList<TaskCard>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TaskCard)))
    .map((c) => c.task.title)
    .toList();

List<String> recentlyDone(WidgetTester tester) => titlesIn(tester, 'recently-done');
List<String> finished(WidgetTester tester) => titlesIn(tester, 'done-list');

/// Ticks (or un-ticks) the first card with this title.
Future<void> tick(WidgetTester tester, String title) async {
  await tester.tap(find.descendant(of: cardFor(title), matching: find.byType(InkResponse)));
  await TestApp.settle(tester);
}

Future<void> addDirect(
  WidgetTester tester,
  TestApp app,
  String title,
  DateTime due, {
  Priority priority = Priority.medium,
  String category = 'general',
  bool done = false,
  Repeat repeat = Repeat.none,
}) async {
  await tester.runAsync(() async {
    final t = await app.repo.addTask(
      TaskDraft(title: title, dueAt: due, priority: priority, categoryId: category, repeat: repeat),
    );
    if (done) await app.repo.setDone(t.id, true);
  });
}

bool isStruckThrough(WidgetTester tester, String title) =>
    tester.widget<Text>(find.descendant(of: cardFor(title), matching: find.text(title))).style!.decoration ==
    TextDecoration.lineThrough;

Finder filterSelection(String label) =>
    find.descendant(of: find.byKey(const ValueKey('active-filters')), matching: find.textContaining(label));

void main() {
  group('every task that is created shows up', () {
    for (final p in Priority.values) {
      testWidgets('a ${p.label} task appears in Do next, the calendar and All tasks', (tester) async {
        final app = await TestApp.create(withSampleTasks: false);
        await addDirect(tester, app, 'A ${p.label} task', DateTime(2026, 10, 8, 18), priority: p);
        await app.pump(tester);
        expect(doNextTitles(tester), ['A ${p.label} task']);
        expect(
          find.descendant(of: find.byType(SelectedDayTasks), matching: find.text('A ${p.label} task')),
          findsOneWidget,
        );
        await tester.tap(find.text('See all tasks'));
        await TestApp.settle(tester);
        expect(find.text('A ${p.label} task'), findsOneWidget);
        await app.dispose(tester);
      });
    }

    testWidgets('24 tasks (every priority in every category) all appear on the All tasks page, none missing', (
      tester,
    ) async {
      final app = await TestApp.create(withSampleTasks: false);
      final titles = <String>[];
      for (final p in Priority.values) {
        for (final cat in ['general', 'teaching', 'admin', 'meetings', 'cca', 'personal']) {
          final title = '${p.label} $cat';
          titles.add(title);
          await addDirect(
            tester,
            app,
            title,
            DateTime(2026, 10, 9 + titles.length % 10, 12),
            priority: p,
            category: cat,
          );
        }
      }
      await app.pump(tester, size: tall, location: '/tasks');
      final shown = tester.widgetList<TaskCard>(find.byType(TaskCard)).map((c) => c.task.title).toList();
      expect(shown, hasLength(24));
      expect(shown.toSet(), titles.toSet());
      await app.dispose(tester);
    });

    testWidgets('a task made with the form appears at once in every place', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, size: const Size(1440, 1800));
      await tester.tap(find.text('Add task'));
      await TestApp.settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'e.g. Mark 3A essays'), 'Made with the form');
      await tester.tap(find.text('Save task'));
      await TestApp.settle(tester);
      expect(doNextTitles(tester), ['Made with the form']);
      expect(
        find.descendant(of: find.byType(SelectedDayTasks), matching: find.text('Made with the form')),
        findsOneWidget,
      );
      expect(find.text('Task added'), findsOneWidget);
      expect(find.textContaining('due this week'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('a task due on a day in another month shows when you go to that month', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await addDirect(tester, app, 'November task', DateTime(2026, 11, 20, 10));
      await app.pump(tester);
      await tester.tap(find.byTooltip('Next month'));
      await TestApp.settle(tester);
      await tester.tap(find.descendant(of: find.byType(CalendarPanel), matching: find.text('20')).first);
      await TestApp.settle(tester);
      expect(find.descendant(of: find.byType(SelectedDayTasks), matching: find.text('November task')), findsOneWidget);
      await app.dispose(tester);
    });
  });

  group('ticking a task off', () {
    testWidgets('it moves from the ranked list to "Recently done", struck through and ticked', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      expect(doNextTitles(tester), contains('Mark 3A essays'));
      expect(recentlyDone(tester), ['Print worksheets'], reason: 'the sample data already has one finished task');

      await tick(tester, 'Mark 3A essays');

      expect(doNextTitles(tester), isNot(contains('Mark 3A essays')));
      expect(recentlyDone(tester), contains('Mark 3A essays'), reason: 'it did not vanish, it moved');
      expect(isStruckThrough(tester, 'Mark 3A essays'), isTrue);
      expect(find.byIcon(Icons.check_rounded), findsWidgets);
      expect(find.textContaining('Nice work!'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the most recently finished task is listed first', (tester) async {
      final app = await TestApp.create(ticking: true);
      await app.pump(tester, size: tall);
      await tick(tester, 'Mark 3A essays');
      expect(recentlyDone(tester).first, 'Mark 3A essays');
      await app.dispose(tester);
    });

    testWidgets('an overdue task that is finished does not disappear either', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await tick(tester, 'Submit term report');
      expect(doNextTitles(tester), isNot(contains('Submit term report')));
      expect(recentlyDone(tester), contains('Submit term report'));
      expect(
        find.descendant(of: cardFor('Submit term report'), matching: find.textContaining('Overdue')),
        findsNothing,
      );
      await app.dispose(tester);
    });

    testWidgets('the weekly summary counts it as done straight away', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      expect(find.text('1 of 4 done — keep going!'), findsOneWidget);
      await tick(tester, 'Mark 3A essays');
      expect(find.text('2 of 4 done — keep going!'), findsOneWidget);
      expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0.5);
      await app.dispose(tester);
    });

    testWidgets('overdue count goes down when an overdue task is finished', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      expect(find.text('1 overdue'), findsNothing);
      List<String?> summary() => tester
          .widgetList<Text>(find.descendant(of: find.byType(WeekSummaryCard), matching: find.byType(Text)))
          .map((t) => t.data)
          .toList();
      expect(summary(), containsAllInOrder(['1', 'overdue']));
      await tick(tester, 'Submit term report');
      expect(summary(), containsAllInOrder(['0', 'overdue']));
      await app.dispose(tester);
    });

    testWidgets('the calendar dot for a day with only that task goes away, and the day says it is done', (
      tester,
    ) async {
      final app = await TestApp.create(withSampleTasks: false);
      await addDirect(tester, app, 'Only task', DateTime(2026, 10, 8, 18), category: 'cca');
      await app.pump(tester);
      expect(find.descendant(of: find.byType(SelectedDayTasks), matching: find.text('Only task')), findsOneWidget);
      await tick(tester, 'Only task');
      expect(find.text('The task due is done.'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('it can be ticked straight from the calendar\'s day list', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await tester.tap(
        find
            .descendant(
              of: find.descendant(of: find.byType(SelectedDayTasks), matching: find.byType(TaskCard)),
              matching: find.byType(InkResponse),
            )
            .first,
      );
      await TestApp.settle(tester);
      expect(recentlyDone(tester), contains('Reply to parent emails'));
      await app.dispose(tester);
    });

    testWidgets('finishing the last task shows "All done!", and the task is still there to see or un-tick', (
      tester,
    ) async {
      final app = await TestApp.create(withSampleTasks: false);
      await addDirect(tester, app, 'Last one', DateTime(2026, 10, 9));
      await app.pump(tester, size: tall);
      await tick(tester, 'Last one');
      expect(find.text('All done!'), findsOneWidget);
      expect(doNextTitles(tester), isEmpty);
      expect(recentlyDone(tester), ['Last one']);
      await tick(tester, 'Last one');
      expect(doNextTitles(tester), ['Last one']);
      expect(find.text('All done!'), findsNothing);
      await app.dispose(tester);
    });
  });

  group('un-ticking: it comes back where it was', () {
    testWidgets('Undo in the message puts it back in the same position with the same due time', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      final before = doNextTitles(tester);
      final dueBefore = tester.widget<TaskCard>(cardFor('Mark 3A essays')).task.dueAt;
      expect(
        find.descendant(of: cardFor('Mark 3A essays'), matching: find.textContaining('Due tomorrow, 5:00 pm')),
        findsOneWidget,
      );

      await tick(tester, 'Mark 3A essays');
      await tester.tap(find.text('Undo'));
      await TestApp.settle(tester);

      expect(doNextTitles(tester), before);
      expect(tester.widget<TaskCard>(cardFor('Mark 3A essays')).task.dueAt, dueBefore);
      expect(
        find.descendant(of: cardFor('Mark 3A essays'), matching: find.textContaining('Due tomorrow, 5:00 pm')),
        findsOneWidget,
      );
      expect(recentlyDone(tester), ['Print worksheets']);
      await app.dispose(tester);
    });

    testWidgets('un-ticking from "Recently done" brings it back to the same position', (tester) async {
      final app = await TestApp.create(ticking: true);
      await app.pump(tester, size: tall);
      final before = doNextTitles(tester);
      await tick(tester, 'Reply to parent emails');
      expect(doNextTitles(tester), isNot(before));
      await tester.tap(
        find.descendant(of: find.byKey(const ValueKey('recently-done')), matching: find.byType(InkResponse)).first,
      );
      await TestApp.settle(tester);
      expect(doNextTitles(tester), before);
      expect(find.textContaining('moved back to your list'), findsOneWidget);
      expect(isStruckThrough(tester, 'Reply to parent emails'), isFalse);
      await app.dispose(tester);
    });

    testWidgets('ticking and un-ticking 8 times leaves the list exactly as it started', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      final before = doNextTitles(tester);
      for (var i = 0; i < 8; i++) {
        await tick(tester, 'Mark 3A essays');
        expect(doNextTitles(tester), isNot(contains('Mark 3A essays')), reason: 'cycle $i');
        await tick(tester, 'Mark 3A essays');
        expect(doNextTitles(tester), before, reason: 'cycle $i');
      }
      expect(recentlyDone(tester), ['Print worksheets']);
      await app.dispose(tester);
    });

    testWidgets('finishing three tasks and un-ticking them in a different order restores the original order', (
      tester,
    ) async {
      final app = await TestApp.create(ticking: true);
      await app.pump(tester, size: tall);
      final before = doNextTitles(tester);
      for (final t in ['Mark 3A essays', 'Submit term report', 'Plan CCA trip']) {
        await tick(tester, t);
      }
      for (final t in ['Mark 3A essays', 'Submit term report', 'Plan CCA trip']) {
        expect(doNextTitles(tester), isNot(contains(t)), reason: t);
      }
      for (final t in ['Plan CCA trip', 'Mark 3A essays', 'Submit term report']) {
        await tick(tester, t);
      }
      expect(doNextTitles(tester), before);
      await app.dispose(tester);
    });

    testWidgets('a task finished yesterday-ish keeps its place in the calendar when un-ticked', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await addDirect(tester, app, 'Calendar task', DateTime(2026, 10, 8, 18));
      await app.pump(tester, size: tall);
      await tick(tester, 'Calendar task');
      await tick(tester, 'Calendar task');
      expect(find.descendant(of: find.byType(SelectedDayTasks), matching: find.text('Calendar task')), findsOneWidget);
      await app.dispose(tester);
    });
  });

  group('the Status filter shows finished tasks', () {
    Future<void> setStatus(WidgetTester tester, String option) async {
      await tester.tap(find.byTooltip('Change Status'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(MenuItemButton), matching: find.text(option)));
      await TestApp.settle(tester);
    }

    testWidgets('Done lists finished tasks (most recent first), ticked, under a "Done" heading', (tester) async {
      final app = await TestApp.create(ticking: true);
      await app.pump(tester, size: tall);
      await tick(tester, 'Mark 3A essays');
      await setStatus(tester, 'Done');
      expect(find.text('Most recent first'), findsOneWidget);
      expect(doNextTitles(tester), isEmpty);
      expect(finished(tester), ['Mark 3A essays', 'Print worksheets']);
      expect(find.text('No tasks match'), findsNothing);
      expect(find.byKey(const ValueKey('recently-done')), findsNothing, reason: 'not listed twice');
      await app.dispose(tester);
    });

    testWidgets('un-ticking from the Done view sends the task back to Do next', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await setStatus(tester, 'Done');
      await tick(tester, 'Print worksheets');
      expect(find.text('No tasks match'), findsOneWidget, reason: 'nothing finished any more');
      await setStatus(tester, 'To do');
      expect(doNextTitles(tester), contains('Print worksheets'));
      await app.dispose(tester);
    });

    testWidgets('All shows the ranked tasks first and the finished ones after them', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await setStatus(tester, 'All');
      expect(doNextTitles(tester), hasLength(5));
      expect(finished(tester), ['Print worksheets']);
      await app.dispose(tester);
    });

    testWidgets('category and search filters apply to finished tasks too', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await setStatus(tester, 'Done');
      await tester.tap(find.widgetWithText(InkWell, 'Admin').first);
      await TestApp.settle(tester);
      expect(find.text('No tasks match'), findsOneWidget, reason: 'the finished task is Teaching, not Admin');
      await tester.tap(find.widgetWithText(InkWell, 'Teaching').first);
      await TestApp.settle(tester);
      await tester.tap(find.widgetWithText(InkWell, 'Admin').first);
      await TestApp.settle(tester);
      expect(finished(tester), ['Print worksheets']);
      await app.dispose(tester);
    });

    testWidgets('"Recently done" only lists the last 7 days', (tester) async {
      final app = await TestApp.create();
      await tester.runAsync(() async {
        final old = (await app.repo.watchTasks().first).singleWhere((t) => t.title == 'Print worksheets');
        await (app.db.update(
          app.db.tasks,
        )..where((t) => t.id.equals(old.id))).write(TasksCompanion(completedAt: Value(DateTime(2026, 9, 20))));
      });
      await app.pump(tester, size: tall);
      expect(find.byKey(const ValueKey('recently-done')), findsNothing);
      await setStatus(tester, 'Done');
      expect(finished(tester), ['Print worksheets'], reason: 'still in the Done view, however old');
      await app.dispose(tester);
    });

    testWidgets('"Recently done" shows 3, can be collapsed, and links to the full Done view', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      for (var i = 1; i <= 5; i++) {
        await addDirect(tester, app, 'Finished $i', DateTime(2026, 10, 8, 10 + i), done: true);
      }
      await app.pump(tester, size: tall);
      expect(recentlyDone(tester), hasLength(3));
      expect(find.text('Recently done'), findsOneWidget);

      await tester.tap(find.text('Recently done'));
      await TestApp.settle(tester);
      expect(find.byKey(const ValueKey('recently-done')), findsNothing, reason: 'collapsed');
      await tester.tap(find.text('Recently done'));
      await TestApp.settle(tester);
      expect(recentlyDone(tester), hasLength(3));

      await tester.tap(find.text('Show all 5 finished'));
      await TestApp.settle(tester);
      expect(find.text('Status: Done'), findsOneWidget);
      expect(finished(tester), hasLength(5));
      await app.dispose(tester);
    });
  });

  group('"2 tasks due this week but nothing shows up": hidden by filters', () {
    /// The exact situation from the bug report: two tasks due this week, with the General category
    /// and the Done status selected.
    Future<TestApp> twoTasksButFiltered(WidgetTester tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await addDirect(tester, app, 'Mark Sec 3 papers', DateTime(2026, 10, 9, 17), category: 'teaching');
      await addDirect(tester, app, 'Staff briefing', DateTime(2026, 10, 9, 15), category: 'meetings');
      await app.pump(tester, size: tall, now: DateTime(2026, 10, 9, 14));
      await tester.tap(find.widgetWithText(InkWell, 'General').first);
      await TestApp.settle(tester);
      await tester.tap(find.byTooltip('Change Status'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(MenuItemButton), matching: find.text('Done')));
      await TestApp.settle(tester);
      return app;
    }

    testWidgets('the banner says what is being filtered, so tasks do not just look missing', (tester) async {
      final app = await twoTasksButFiltered(tester);
      expect(find.text('Showing only: General · Done'), findsOneWidget);
      expect(find.text('Clear filters'), findsWidgets);
      expect(find.textContaining('2 tasks this week'), findsOneWidget, reason: 'the greeting still says there are 2');
      await app.dispose(tester);
    });

    testWidgets('the summary still counts the two tasks, and tapping it shows them despite the filters', (
      tester,
    ) async {
      final app = await twoTasksButFiltered(tester);
      expect(find.text('0 of 2 done — keep going!'), findsOneWidget);
      await tester.tap(find.text('due this week'));
      await TestApp.settle(tester);
      expect(find.byType(WeekTasksSheet), findsOneWidget);
      expect(
        find.descendant(of: find.byType(WeekTasksSheet), matching: find.text('Mark Sec 3 papers')),
        findsOneWidget,
      );
      expect(find.descendant(of: find.byType(WeekTasksSheet), matching: find.text('Staff briefing')), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the day panel says tasks are hidden by the filters, with a count', (tester) async {
      final app = await twoTasksButFiltered(tester);
      expect(find.text('2 tasks are hidden by your filters.'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('Clear filters brings both tasks back everywhere', (tester) async {
      final app = await twoTasksButFiltered(tester);
      await tester.tap(
        find.descendant(of: find.byKey(const ValueKey('active-filters')), matching: find.text('Clear filters')),
      );
      await TestApp.settle(tester);
      expect(find.byKey(const ValueKey('active-filters')), findsNothing);
      expect(doNextTitles(tester).toSet(), {'Mark Sec 3 papers', 'Staff briefing'});
      expect(find.descendant(of: find.byType(SelectedDayTasks), matching: find.byType(TaskCard)), findsNWidgets(2));
      expect(find.textContaining('hidden by your filters'), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('the Do next card offers its own Clear filters button too', (tester) async {
      final app = await twoTasksButFiltered(tester);
      expect(find.text('No tasks match'), findsOneWidget);
      final messageCard = find.ancestor(of: find.text('No tasks match'), matching: find.byType(PandaCard)).first;
      await tester.tap(find.descendant(of: messageCard, matching: find.text('Clear filters')));
      await TestApp.settle(tester);
      expect(doNextTitles(tester), hasLength(2));
      await app.dispose(tester);
    });

    testWidgets('no banner when no filters are on, and one appears for a search alone', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      expect(find.byKey(const ValueKey('active-filters')), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'quiz');
      await TestApp.settle(tester);
      expect(find.text('Showing only: “quiz”'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the banner lists every filter in plain words', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await tester.tap(find.widgetWithText(InkWell, 'Teaching').first);
      await tester.tap(find.widgetWithText(InkWell, 'Admin').first);
      await TestApp.settle(tester);
      await tester.tap(find.byTooltip('Change Priority'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(MenuItemButton), matching: find.text('High')));
      await TestApp.settle(tester);
      expect(find.text('Showing only: Teaching or Admin · High priority'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the banner is also on the Calendar and All tasks pages', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall, location: '/tasks');
      await tester.tap(find.widgetWithText(InkWell, 'CCA').first);
      await TestApp.settle(tester);
      expect(find.text('Showing only: CCA'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await TestApp.settle(tester);
      expect(find.text('Showing only: CCA'), findsOneWidget, reason: 'the filter is shared with the home page');
      await app.dispose(tester);
    });

    testWidgets('a new task your filters would hide says so, and "Show it" reveals it', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await tester.tap(find.widgetWithText(InkWell, 'CCA').first);
      await TestApp.settle(tester);
      expect(doNextTitles(tester), ['Plan CCA trip']);

      await tester.tap(find.text('Add task'));
      await TestApp.settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'e.g. Mark 3A essays'), 'A general task');
      await tester.tap(find.text('Save task'));
      await TestApp.settle(tester);
      expect(find.text('Task added — your filters are hiding it'), findsOneWidget);
      expect(doNextTitles(tester), ['Plan CCA trip']);

      await tester.tap(find.text('Show it'));
      await TestApp.settle(tester);
      expect(doNextTitles(tester), contains('A general task'));
      expect(find.byKey(const ValueKey('active-filters')), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('a new task that matches the filters just says "Task added"', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await tester.tap(find.widgetWithText(InkWell, 'General').first);
      await TestApp.settle(tester);
      await tester.tap(find.text('Add task'));
      await TestApp.settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'e.g. Mark 3A essays'), 'Matches');
      await tester.tap(find.text('Save task'));
      await TestApp.settle(tester);
      expect(find.text('Task added'), findsOneWidget);
      expect(find.text('Show it'), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('editing a task so your filters hide it says so too', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await tester.tap(find.widgetWithText(InkWell, 'Teaching').first);
      await TestApp.settle(tester);
      await tester.tap(find.text('Mark 3A essays'));
      await TestApp.settle(tester);
      await tester.tap(
        find.descendant(of: find.byType(TaskEditor), matching: find.widgetWithText(InkWell, 'Admin')).first,
      );
      await TestApp.settle(tester);
      await tester.tap(find.text('Save changes'));
      await TestApp.settle(tester);
      expect(find.text('Task updated — your filters are hiding it'), findsOneWidget);
      await app.dispose(tester);
    });
  });

  group('the "This week" boxes open the tasks behind them', () {
    testWidgets('each box is a button', (tester) async {
      final handle = tester.ensureSemantics();
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      expect(find.bySemanticsLabel('4 due this week. Show these tasks.'), findsOneWidget);
      expect(find.bySemanticsLabel('1 done. Show these tasks.'), findsOneWidget);
      expect(find.bySemanticsLabel('1 overdue. Show these tasks.'), findsOneWidget);
      handle.dispose();
      await app.dispose(tester);
    });

    testWidgets('"due this week" opens the list with all four tasks, earliest first, finished one ticked', (
      tester,
    ) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await tester.tap(find.text('due this week'));
      await TestApp.settle(tester);
      expect(find.text('Due 4'), findsOneWidget);
      expect(find.text('Done 1'), findsOneWidget);
      expect(find.text('Overdue 1'), findsOneWidget);
      final titles = tester
          .widgetList<TaskCard>(find.descendant(of: find.byType(WeekTasksSheet), matching: find.byType(TaskCard)))
          .map((c) => c.task.title)
          .toList();
      expect(titles, ['Print worksheets', 'Submit term report', 'Reply to parent emails', 'Mark 3A essays']);
      await app.dispose(tester);
    });

    testWidgets('"done" opens the finished tab', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await tester.tap(find.descendant(of: find.byType(WeekSummaryCard), matching: find.text('done')));
      await TestApp.settle(tester);
      final titles = tester
          .widgetList<TaskCard>(find.descendant(of: find.byType(WeekTasksSheet), matching: find.byType(TaskCard)))
          .map((c) => c.task.title)
          .toList();
      expect(titles, ['Print worksheets']);
      await app.dispose(tester);
    });

    testWidgets('"overdue" opens the overdue tab, oldest first', (tester) async {
      final app = await TestApp.create();
      await addDirect(tester, app, 'Older still', DateTime(2026, 10, 1, 9));
      await app.pump(tester, size: tall);
      await tester.tap(find.descendant(of: find.byType(WeekSummaryCard), matching: find.text('overdue')));
      await TestApp.settle(tester);
      final titles = tester
          .widgetList<TaskCard>(find.descendant(of: find.byType(WeekTasksSheet), matching: find.byType(TaskCard)))
          .map((c) => c.task.title)
          .toList();
      expect(titles, ['Older still', 'Submit term report']);
      await app.dispose(tester);
    });

    testWidgets('the tabs switch between the lists and show counts', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await tester.tap(find.text('due this week'));
      await TestApp.settle(tester);
      await tester.tap(find.text('Overdue 1'));
      await TestApp.settle(tester);
      expect(find.descendant(of: find.byType(WeekTasksSheet), matching: find.byType(TaskCard)), findsOneWidget);
      await tester.tap(find.text('Done 1'));
      await TestApp.settle(tester);
      expect(find.descendant(of: find.byType(WeekTasksSheet), matching: find.text('Print worksheets')), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('an empty tab says so in words', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, size: tall);
      await tester.tap(find.text('overdue'));
      await TestApp.settle(tester);
      expect(find.text('Nothing is overdue. Well done!'), findsOneWidget);
      await tester.tap(find.text('Done 0'));
      await TestApp.settle(tester);
      expect(find.textContaining('Nothing finished yet'), findsOneWidget);
      await tester.tap(find.text('Due 0'));
      await TestApp.settle(tester);
      expect(find.text('Nothing is due this week yet.'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('tasks can be ticked and un-ticked inside the list, and everything updates behind it', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await tester.tap(find.text('due this week'));
      await TestApp.settle(tester);
      await tester.tap(
        find.descendant(
          of: find.descendant(
            of: find.byType(WeekTasksSheet),
            matching: find.widgetWithText(TaskCard, 'Mark 3A essays'),
          ),
          matching: find.byType(InkResponse),
        ),
      );
      await TestApp.settle(tester);
      expect(find.text('Done 2'), findsOneWidget);
      expect(find.text('Due 4'), findsOneWidget, reason: 'still due this week, just finished');
      await tester.tap(
        find.descendant(
          of: find.descendant(
            of: find.byType(WeekTasksSheet),
            matching: find.widgetWithText(TaskCard, 'Mark 3A essays'),
          ),
          matching: find.byType(InkResponse),
        ),
      );
      await TestApp.settle(tester);
      expect(find.text('Done 1'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('tapping a task in the list opens it for editing', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await tester.tap(find.text('due this week'));
      await TestApp.settle(tester);
      await tester.tap(find.descendant(of: find.byType(WeekTasksSheet), matching: find.text('Mark 3A essays')));
      await TestApp.settle(tester);
      expect(find.text('Edit task'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the list can be closed', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await tester.tap(find.text('due this week'));
      await TestApp.settle(tester);
      await tester.tap(find.byTooltip('Close'));
      await TestApp.settle(tester);
      expect(find.byType(WeekTasksSheet), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('on a phone it opens as a bottom sheet', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: phone);
      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await TestApp.settle(tester);
      await tester.tap(find.text('due this week'));
      await TestApp.settle(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(WeekTasksSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
      await app.dispose(tester);
    });

    testWidgets('the boxes show a hint on hover', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      expect(find.byTooltip('See the tasks: due this week'), findsOneWidget);
      expect(find.byTooltip('See the tasks: done this week'), findsOneWidget);
      expect(find.byTooltip('See the tasks: overdue'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the overdue box is red only when something is overdue, as before', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      final box = find
          .ancestor(
            of: find.descendant(of: find.byType(WeekSummaryCard), matching: find.text('overdue')),
            matching: find.byType(Material),
          )
          .first;
      expect(tester.widget<Material>(box).color, PandaColors.overdueTint);
      await app.dispose(tester);
    });
  });

  group('repeating tasks', () {
    testWidgets('a repeating task is marked on its card', (tester) async {
      final app = await TestApp.create();
      await addDirect(tester, app, 'Water plants', DateTime(2026, 10, 9, 17), repeat: Repeat.weekly);
      await app.pump(tester, size: tall);
      expect(find.descendant(of: cardFor('Water plants'), matching: find.textContaining('↻ Weekly')), findsOneWidget);
      expect(find.descendant(of: cardFor('Mark 3A essays'), matching: find.textContaining('↻')), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('ticking says when it comes back, and Undo puts it back', (tester) async {
      final app = await TestApp.create();
      await addDirect(tester, app, 'Water plants', DateTime(2026, 10, 9, 17), repeat: Repeat.weekly);
      await app.pump(tester, size: tall);
      await tick(tester, 'Water plants');
      expect(find.textContaining('It comes back tomorrow, due Fri 16 Oct'), findsOneWidget);
      expect(recentlyDone(tester), contains('Water plants'));
      await tester.tap(find.text('Undo'));
      await TestApp.settle(tester);
      expect(doNextTitles(tester), contains('Water plants'));
      await app.dispose(tester);
    });

    testWidgets('one finished on an earlier day is back in the list when the app opens', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await addDirect(tester, app, 'Water plants', DateTime(2026, 10, 6, 17), repeat: Repeat.weekly, done: true);
      await tester.runAsync(
        () => (app.db.update(app.db.tasks)).write(TasksCompanion(completedAt: Value(DateTime(2026, 10, 6, 18)))),
      );
      await app.pump(tester, size: tall);
      await TestApp.settle(tester);
      expect(doNextTitles(tester), ['Water plants']);
      expect(find.descendant(of: cardFor('Water plants'), matching: find.textContaining('Tue 13 Oct')), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('ticking does not add a new task straight away', (tester) async {
      final app = await TestApp.create();
      await addDirect(tester, app, 'Water plants', DateTime(2026, 10, 9, 17), repeat: Repeat.weekly);
      await app.pump(tester, size: tall);
      await tick(tester, 'Water plants');
      expect(find.widgetWithText(TaskCard, 'Water plants'), findsOneWidget, reason: 'one card, not two');
      await app.dispose(tester);
    });

    testWidgets('one that is not due for weeks cannot be ticked: it explains instead', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await addDirect(tester, app, 'Water plants', DateTime(2027, 1, 23, 17), repeat: Repeat.weekly);
      await app.pump(tester, size: tall);
      await tick(tester, 'Water plants');
      expect(find.textContaining('isn’t due until Sat 23 Jan 2027'), findsOneWidget);
      expect(find.textContaining('tick it off from Sat 16 Jan 2027'), findsOneWidget);
      expect(find.textContaining('Nice work'), findsNothing);
      expect(isStruckThrough(tester, 'Water plants'), isFalse);
      await app.dispose(tester);
    });

    testWidgets('ticking a one-off task far ahead is still allowed', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await addDirect(tester, app, 'Book flights', DateTime(2027, 1, 23, 17));
      await app.pump(tester, size: tall);
      await tick(tester, 'Book flights');
      expect(find.textContaining('Nice work!'), findsOneWidget);
      await app.dispose(tester);
    });
  });

  group('the "This week" boxes look clickable', () {
    testWidgets('each has an arrow, and a hint says to tap them', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      expect(find.text('Tap a box to see the tasks'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(WeekSummaryCard), matching: find.byIcon(Icons.chevron_right_rounded)),
        findsNWidgets(3),
      );
      await app.dispose(tester);
    });

    testWidgets('"done" opens the Done tab and "overdue" the Overdue tab', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await tester.tap(find.text('done').first);
      await TestApp.settle(tester);
      expect(find.byType(WeekTasksSheet), findsOneWidget);
      expect(find.descendant(of: find.byType(WeekTasksSheet), matching: find.text('Print worksheets')), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await TestApp.settle(tester);
      await tester.tap(find.text('overdue').first);
      await TestApp.settle(tester);
      expect(
        find.descendant(of: find.byType(WeekTasksSheet), matching: find.text('Submit term report')),
        findsOneWidget,
      );
      await app.dispose(tester);
    });
  });
}
