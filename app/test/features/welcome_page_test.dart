import 'package:bamboozled/features/tasks/widgets/task_card.dart';
import 'package:bamboozled/features/welcome/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

List<String> doNextTitles(WidgetTester tester) => tester
    .widgetList<TaskCard>(find.descendant(of: find.byKey(const ValueKey('do-next')), matching: find.byType(TaskCard)))
    .map((c) => c.task.title)
    .toList();

void main() {
  group('desktop', () {
    testWidgets('greets the user and ranks tasks by deadline + priority', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);

      expect(find.text('Good morning, Ms Tan'), findsOneWidget);
      expect(find.textContaining('Thursday, 8 October'), findsOneWidget);
      expect(find.text('October 2026'), findsOneWidget);
      // Scores at 9 am: 0.91, 0.67, 0.58, 0.57, 0.50 (see docs/priority-algorithm.md).
      expect(doNextTitles(tester), [
        'Submit term report',
        'Mark 3A essays',
        'Reply to parent emails',
        'Plan CCA trip',
        'Prepare Sec 2 quiz',
      ]);
      expect(find.text('Overdue by 1 day · Admin'), findsWidgets);
      await app.dispose(tester);
    });

    testWidgets('category chips filter the list', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      await tester.tap(find.widgetWithText(InkWell, 'Teaching').first);
      await TestApp.settle(tester);
      expect(doNextTitles(tester), ['Mark 3A essays', 'Prepare Sec 2 quiz']);
      await tester.tap(find.widgetWithText(InkWell, 'All').first);
      await TestApp.settle(tester);
      expect(doNextTitles(tester), hasLength(5));
      await app.dispose(tester);
    });

    testWidgets('search matches titles and notes', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      await tester.enterText(find.byType(TextField).first, 'essay');
      await TestApp.settle(tester);
      expect(doNextTitles(tester), ['Mark 3A essays']);
      await tester.enterText(find.byType(TextField).first, 'zzz');
      await TestApp.settle(tester);
      expect(find.text('No tasks match'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await TestApp.settle(tester);
      expect(doNextTitles(tester), hasLength(5));
      await app.dispose(tester);
    });

    testWidgets('adding a task through the form', (tester) async {
      final semantics = tester.ensureSemantics();
      final app = await TestApp.create();
      await app.pump(tester);
      await tester.tap(find.text('Add task'));
      await TestApp.settle(tester);
      expect(find.text('New task'), findsOneWidget);

      // Saving without a title explains what's missing.
      await tester.tap(find.text('Save task'));
      await TestApp.settle(tester);
      expect(find.text('Give your task a short name'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'e.g. Mark 3A essays'), 'Call parents of Ali');
      await tester.tap(find.widgetWithText(InkWell, 'Today').first);
      await tester.tap(find.bySemanticsLabel('Urgent priority').last);
      await tester.ensureVisible(find.text('Save task'));
      await tester.tap(find.text('Save task'));
      await TestApp.settle(tester);

      expect(find.text('Task added'), findsOneWidget);
      // Urgent and due tonight: second only to the overdue report.
      expect(doNextTitles(tester).take(2), ['Submit term report', 'Call parents of Ali']);
      await app.dispose(tester);
      semantics.dispose();
    });

    testWidgets('ticking a task off removes it from Do next, with undo', (tester) async {
      final semantics = tester.ensureSemantics();
      final app = await TestApp.create();
      await app.pump(tester);
      await tester.tap(find.bySemanticsLabel('Mark "Submit term report" as done').first);
      await TestApp.settle(tester);
      expect(doNextTitles(tester), isNot(contains('Submit term report')));
      expect(find.textContaining('Nice work!'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await TestApp.settle(tester);
      expect(doNextTitles(tester).first, 'Submit term report');
      await app.dispose(tester);
      semantics.dispose();
    });

    testWidgets('selecting a calendar day lists its tasks', (tester) async {
      final semantics = tester.ensureSemantics();
      final app = await TestApp.create();
      await app.pump(tester);
      await tester.tap(find.bySemanticsLabel('Thursday, October 15, 2026'));
      await TestApp.settle(tester);
      expect(find.text('Thursday 15 October'), findsOneWidget);
      expect(find.text('Plan CCA trip'), findsNWidgets(2)); // in Do next and in the day list
      await app.dispose(tester);
      semantics.dispose();
    });
  });

  group('phone', () {
    const phone = Size(412, 915);

    testWidgets('shows the week strip, bottom navigation and add button', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: phone);
      expect(find.text('Good morning, Ms Tan'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byTooltip('Add task'), findsOneWidget);
      expect(find.text('Month'), findsOneWidget);
      expect(doNextTitles(tester).first, 'Submit term report');
      await app.dispose(tester);
    });

    testWidgets('empty state invites the first task', (tester) async {
      final app = await TestApp.create(withSampleTasks: false, name: null);
      await app.pump(tester, size: phone);
      expect(find.text('No tasks yet'), findsOneWidget);
      expect(find.text('Good morning'), findsOneWidget);
      await tester.tap(find.byTooltip('Add task'));
      await TestApp.settle(tester);
      expect(find.text('New task'), findsOneWidget);
      expect(find.text('Notes'), findsWidgets);
      await app.dispose(tester);
    });

    testWidgets('filter sheet sets status and priority', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: phone);
      await tester.tap(find.text('Filter'));
      await TestApp.settle(tester);
      await tester.tap(find.descendant(of: find.byType(FilterSheet), matching: find.widgetWithText(InkWell, 'Urgent')));
      await TestApp.settle(tester);
      await tester.tap(find.text('Show tasks'));
      await TestApp.settle(tester);
      expect(find.text('Filter (1)'), findsOneWidget);
      expect(doNextTitles(tester), ['Plan CCA trip']);
      await app.dispose(tester);
    });
  });
}
