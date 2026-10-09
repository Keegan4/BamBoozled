import 'package:bamboozled/core/theme/colors.dart';
import 'package:bamboozled/data/repositories/task_repository.dart';
import 'package:bamboozled/domain/models/priority.dart';
import 'package:bamboozled/features/tasks/task_editor.dart';
import 'package:bamboozled/features/welcome/widgets/do_next_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

const phone = Size(412, 915);

Future<void> addTask(
  WidgetTester tester,
  TestApp app,
  String title,
  DateTime due, {
  Priority priority = Priority.medium,
  bool done = false,
}) async {
  await tester.runAsync(() async {
    final t = await app.repo.addTask(TaskDraft(title: title, dueAt: due, priority: priority, categoryId: 'general'));
    if (done) await app.repo.setDone(t.id, true);
  });
}

void main() {
  group('Do next list', () {
    testWidgets('ranks tasks, numbering them from 1 with the top one highlighted', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      expect(doNextTitles(tester).length, 5);
      for (final n in ['1', '2', '3', '4', '5']) {
        expect(find.descendant(of: find.byKey(const ValueKey('do-next')), matching: find.text(n)), findsOneWidget);
      }
      Color? bubble(String n) {
        final c = find
            .ancestor(
              of: find.descendant(of: find.byKey(const ValueKey('do-next')), matching: find.text(n)),
              matching: find.byType(Container),
            )
            .first;
        return (tester.widget<Container>(c).decoration! as BoxDecoration).color;
      }

      expect(bubble('1'), PandaColors.ink);
      expect(bubble('2'), PandaColors.bambooTint);
      await app.dispose(tester);
    });

    testWidgets('an urgent task a week away ranks below a low-priority task due today', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await addTask(tester, app, 'Urgent next week', DateTime(2026, 10, 15, 9), priority: Priority.urgent);
      await addTask(tester, app, 'Low but today', DateTime(2026, 10, 8, 13), priority: Priority.low);
      await app.pump(tester);
      expect(doNextTitles(tester), ['Low but today', 'Urgent next week']);
      await app.dispose(tester);
    });

    testWidgets('as a deadline approaches, a nearer task overtakes a more important one', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await addTask(tester, app, 'Urgent, due Thursday', DateTime(2026, 10, 15, 9), priority: Priority.urgent);
      await addTask(tester, app, 'Medium, due Sunday', DateTime(2026, 10, 11, 9));
      await app.pump(tester, now: DateTime(2026, 10, 8, 9));
      expect(doNextTitles(tester), ['Urgent, due Thursday', 'Medium, due Sunday']);
      await tester.pumpWidget(const SizedBox()); // start a fresh app, as if opened later
      await app.pump(tester, now: DateTime(2026, 10, 11, 0)); // nine hours before the medium task is due
      expect(doNextTitles(tester), ['Medium, due Sunday', 'Urgent, due Thursday']);
      await app.dispose(tester);
    });

    testWidgets('each card explains its rank in a tooltip', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      expect(find.byTooltip('Overdue by 1 day · Medium priority'), findsOneWidget);
      expect(find.byTooltip('Due tomorrow · High priority'), findsOneWidget);
      expect(find.byTooltip('Due today · Low priority'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('shows only the top five and links to the full list with the real count', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      expect(doNextTitles(tester), hasLength(5));
      expect(find.text('See all 7 tasks'), findsOneWidget);
      await tester.tap(find.text('See all 7 tasks'));
      await TestApp.settle(tester);
      expect(find.text('All tasks'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('with five or fewer tasks the link says "See all tasks"', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await addTask(tester, app, 'Only one', DateTime(2026, 10, 9));
      await app.pump(tester);
      expect(find.text('See all tasks'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('completed tasks leave the list and new tasks join it straight away', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await addTask(tester, app, 'First', DateTime(2026, 10, 8, 12));
      await app.pump(tester);
      expect(doNextTitles(tester), ['First']);
      await addTask(tester, app, 'Second', DateTime(2026, 10, 9, 12));
      await TestApp.settle(tester);
      expect(doNextTitles(tester), ['First', 'Second']);
      await tester.tap(find.descendant(of: cardFor('First'), matching: find.byType(InkResponse)));
      await TestApp.settle(tester);
      expect(doNextTitles(tester), ['Second']);
      await app.dispose(tester);
    });
  });

  group('empty states', () {
    testWidgets('no tasks at all: sleeping panda, a friendly message and a button to add one', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester);
      expect(find.text('No tasks yet'), findsOneWidget);
      expect(find.textContaining('Add your first task'), findsOneWidget);
      await tester.tap(find.text('Add a task'));
      await TestApp.settle(tester);
      expect(find.byType(TaskEditor), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('every task finished: a celebration instead of an empty list', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await addTask(tester, app, 'Done already', DateTime(2026, 10, 7), done: true);
      await app.pump(tester);
      expect(find.text('All done!'), findsOneWidget);
      expect(find.textContaining('Time for some bamboo'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('filters that match nothing say so and offer to clear them', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      await tester.enterText(find.byType(TextField).first, 'nothing like this');
      await TestApp.settle(tester);
      expect(find.text('No tasks match'), findsOneWidget);
      expect(find.text('Try a different search or clear your filters.'), findsOneWidget);
      expect(find.text('Clear filters'), findsNWidgets(2), reason: 'in the banner and under the message');
      await app.dispose(tester);
    });
  });

  group('This week summary', () {
    testWidgets('counts tasks due, done and overdue', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      Finder stat(String label) => find.descendant(of: find.byType(WeekSummaryCard), matching: find.text(label));
      expect(stat('due this week'), findsOneWidget);
      expect(stat('done'), findsOneWidget);
      expect(stat('overdue'), findsOneWidget);
      final texts = tester
          .widgetList<Text>(find.descendant(of: find.byType(WeekSummaryCard), matching: find.byType(Text)))
          .map((t) => t.data)
          .toList();
      expect(texts, containsAllInOrder(['4', 'due this week', '1', 'done', '1', 'overdue']));
      expect(find.text('1 of 4 done — keep going!'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the progress bar matches the counts', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(bar.value, 0.25);
      expect(bar.semanticsLabel, 'Weekly progress: 1 of 4 done');
      await app.dispose(tester);
    });

    testWidgets('an empty week says so, with an empty bar', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester);
      expect(find.text('Nothing due this week yet.'), findsOneWidget);
      expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0);
      await app.dispose(tester);
    });

    testWidgets('a finished week gets a cheer and a full bar', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await addTask(tester, app, 'A', DateTime(2026, 10, 7), done: true);
      await addTask(tester, app, 'B', DateTime(2026, 10, 9), done: true);
      await app.pump(tester);
      expect(find.text('2 of 2 done — amazing!'), findsOneWidget);
      expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 1);
      await app.dispose(tester);
    });

    testWidgets('the overdue box is only red when something is overdue', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await addTask(tester, app, 'Fine', DateTime(2026, 10, 9));
      await app.pump(tester);
      Color? overdueBox() {
        final box = find
            .ancestor(
              of: find.descendant(of: find.byType(WeekSummaryCard), matching: find.text('overdue')),
              matching: find.byType(Material),
            )
            .first;
        return tester.widget<Material>(box).color;
      }

      expect(overdueBox(), PandaColors.rice);
      await addTask(tester, app, 'Late', DateTime(2026, 10, 7));
      await TestApp.settle(tester);
      expect(overdueBox(), PandaColors.overdueTint);
      await app.dispose(tester);
    });

    testWidgets('the summary ignores the search and filters', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      await tester.enterText(find.byType(TextField).first, 'nothing like this');
      await TestApp.settle(tester);
      expect(find.text('1 of 4 done — keep going!'), findsOneWidget);
      await app.dispose(tester);
    });
  });

  group('greeting', () {
    testWidgets('uses the name from Settings and the time of day', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, now: DateTime(2026, 10, 8, 14));
      expect(find.text('Good afternoon, Ms Tan'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('without a name it just greets', (tester) async {
      final app = await TestApp.create(name: null);
      await app.pump(tester, now: DateTime(2026, 10, 8, 20));
      expect(find.text('Good evening'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the subtitle gives the date, weekly count and overdue count', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      expect(find.text('Thursday, 8 October · 4 tasks this week, 1 overdue'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('singular when there is one task and nothing overdue', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await addTask(tester, app, 'One', DateTime(2026, 10, 9));
      await app.pump(tester);
      expect(find.text('Thursday, 8 October · 1 task this week'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('on a phone the subtitle is shorter', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: phone);
      expect(find.text('Thu 8 Oct · 1 overdue'), findsOneWidget);
      await app.dispose(tester);
    });
  });

  group('responsive layout', () {
    for (final width in [412.0, 600.0, 700.0, 899.0, 900.0, 1099.0, 1100.0, 1440.0, 1920.0]) {
      testWidgets('the welcome page lays out without overflow at ${width.toInt()}px wide', (tester) async {
        final app = await TestApp.create();
        await app.pump(tester, size: Size(width, 900));
        expect(tester.takeException(), isNull);
        expect(doNextTitles(tester), hasLength(5));
        await app.dispose(tester);
      });
    }

    testWidgets('tablet and phone windows show the same Do next order', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: const Size(700, 900));
      final tablet = doNextTitles(tester);
      await tester.pumpWidget(const SizedBox());
      await app.pump(tester, size: phone);
      expect(doNextTitles(tester), tablet);
      await app.dispose(tester);
    });
  });
}
