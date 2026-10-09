import 'package:bamboozled/core/theme/colors.dart';
import 'package:bamboozled/data/repositories/task_repository.dart';
import 'package:bamboozled/domain/models/priority.dart';
import 'package:bamboozled/domain/models/task.dart';
import 'package:bamboozled/features/tasks/task_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

const phone = Size(412, 915);

/// Tall enough that the whole desktop dialog is on screen, so every field can be tapped.
const tall = Size(1440, 1800);

Finder inEditor(Finder f) => find.descendant(of: find.byType(TaskEditor), matching: f);
Finder pill(String label) => inEditor(find.widgetWithText(InkWell, label)).first;
Finder titleField() => find.widgetWithText(TextField, 'e.g. Mark 3A essays');

/// The title box of an open form, whether or not it has text in it.
Finder editorTitle() => inEditor(find.byType(TextField)).first;

Future<void> tapInEditor(WidgetTester tester, Finder f) async {
  await tester.tap(f);
  await TestApp.settle(tester);
}

Future<List<Task>> allTasks(WidgetTester tester, TestApp app) async =>
    (await tester.runAsync(() => app.repo.watchTasks().first))!;

Future<void> openAddForm(WidgetTester tester) async {
  await tester.tap(find.text('Add task'));
  await TestApp.settle(tester);
}

Future<void> openTask(WidgetTester tester, String title) async {
  await tester.tap(find.descendant(of: find.byKey(const ValueKey('do-next')), matching: find.text(title)));
  await TestApp.settle(tester);
}

Future<void> save(WidgetTester tester, String label) => tapInEditor(tester, find.text(label));

void main() {
  group('adding a task (desktop dialog)', () {
    testWidgets('opens as a dialog with every field from the recommended format', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await openAddForm(tester);
      expect(find.byType(Dialog), findsOneWidget);
      for (final label in [
        'New task',
        'What needs doing?',
        'When is it due?',
        'How important is it?',
        'Category',
        'How long will it take?  (optional)',
        'Notes  (optional)',
        'Repeat',
      ]) {
        expect(find.text(label, findRichText: true), findsOneWidget, reason: label);
      }
      expect(find.text('Save task'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('defaults: due today at end of day, medium priority, General category, no repeat', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, size: tall);
      await openAddForm(tester);
      await tester.enterText(titleField(), 'Just a title');
      await save(tester, 'Save task');
      final t = (await allTasks(tester, app)).single;
      expect(t.title, 'Just a title');
      expect(t.dueAt, DateTime(2026, 10, 8, 23, 59));
      expect(t.priority, Priority.medium);
      expect(t.categoryId, 'general');
      expect(t.repeat, Repeat.none);
      expect(t.estimateMinutes, isNull);
      expect(t.notes, isNull);
      await app.dispose(tester);
    });

    testWidgets('every field can be filled in', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, size: tall);
      await openAddForm(tester);
      await tester.enterText(titleField(), '  Plan the CCA trip  ');
      await tapInEditor(tester, pill('Next week'));
      await tapInEditor(tester, inEditor(find.text('Urgent')));
      await tapInEditor(tester, pill('CCA'));
      await tapInEditor(tester, pill('1 hour'));
      await tester.enterText(find.widgetWithText(TextField, 'Add any details, links or reminders…'), ' Book the bus ');
      await tapInEditor(tester, pill('Weekly'));
      await save(tester, 'Save task');

      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Task added'), findsOneWidget);
      final t = (await allTasks(tester, app)).single;
      expect(t.title, 'Plan the CCA trip');
      expect(t.dueAt, DateTime(2026, 10, 12, 23, 59), reason: 'next Monday, end of day');
      expect(t.priority, Priority.urgent);
      expect(t.categoryId, 'cca');
      expect(t.estimateMinutes, 60);
      expect(t.notes, 'Book the bus');
      expect(t.repeat, Repeat.weekly);
      await app.dispose(tester);
    });

    testWidgets('the Today and Tomorrow chips set the due day', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, size: tall);
      await openAddForm(tester);
      await tester.enterText(titleField(), 'Tomorrow task');
      await tapInEditor(tester, pill('Tomorrow'));
      await save(tester, 'Save task');
      expect((await allTasks(tester, app)).single.dueAt, DateTime(2026, 10, 9, 23, 59));
      await app.dispose(tester);
    });

    testWidgets('an estimate chip can be tapped again to clear it', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, size: tall);
      await openAddForm(tester);
      await tester.enterText(titleField(), 'x');
      await tapInEditor(tester, pill('30 min'));
      await tapInEditor(tester, pill('30 min'));
      await save(tester, 'Save task');
      expect((await allTasks(tester, app)).single.estimateMinutes, isNull);
      await app.dispose(tester);
    });

    testWidgets('a time can be added, shown, and removed', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, size: tall);
      await openAddForm(tester);
      await tester.enterText(titleField(), 'Timed');
      await tapInEditor(tester, pill('Add a time'));
      expect(find.text('What time is it due?'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await TestApp.settle(tester);
      expect(inEditor(find.text('5:00 pm')), findsOneWidget, reason: 'the picker starts at 5 pm');

      // Remove it again with the ×.
      await tapInEditor(tester, find.byTooltip('Remove 5:00 pm'));
      expect(inEditor(find.text('Add a time')), findsOneWidget);

      // Add it back and save.
      await tapInEditor(tester, pill('Add a time'));
      await tester.tap(find.text('OK'));
      await TestApp.settle(tester);
      await save(tester, 'Save task');
      expect((await allTasks(tester, app)).single.dueAt, DateTime(2026, 10, 8, 17));
      await app.dispose(tester);
    });

    testWidgets('a specific date can be picked from the calendar', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, size: tall);
      await openAddForm(tester);
      await tester.enterText(titleField(), 'Dated');
      await tapInEditor(tester, pill('Pick a date'));
      expect(find.text('When is it due?'), findsWidgets);
      await tester.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.text('20')));
      await tester.pump();
      await tester.tap(find.text('OK'));
      await TestApp.settle(tester);
      expect(inEditor(find.text('Tue 20 Oct')), findsOneWidget, reason: 'the chip shows the chosen date');
      await save(tester, 'Save task');
      expect((await allTasks(tester, app)).single.dueAt, DateTime(2026, 10, 20, 23, 59));
      await app.dispose(tester);
    });

    testWidgets('an empty title is refused with a friendly message, then accepted once typed', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, size: tall);
      await openAddForm(tester);
      await save(tester, 'Save task');
      expect(find.text('Give your task a short name'), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      expect(await allTasks(tester, app), isEmpty);

      await tester.enterText(titleField(), 'x');
      await tester.pump();
      expect(find.text('Give your task a short name'), findsNothing);

      await tester.enterText(titleField(), '   ');
      await tester.pump();
      await save(tester, 'Save task');
      expect(find.text('Give your task a short name'), findsOneWidget, reason: 'spaces alone are not a title');
      await app.dispose(tester);
    });

    testWidgets('Cancel and × close the form without saving', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, size: tall);
      await openAddForm(tester);
      await tester.enterText(titleField(), 'Never saved');
      await tapInEditor(tester, find.text('Cancel'));
      expect(find.byType(Dialog), findsNothing);

      await openAddForm(tester);
      await tester.enterText(titleField(), 'Never saved either');
      await tapInEditor(tester, find.byTooltip('Close'));
      expect(find.byType(Dialog), findsNothing);
      expect(await allTasks(tester, app), isEmpty);
      await app.dispose(tester);
    });

    testWidgets('pressing enter in the title box saves', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, size: tall);
      await openAddForm(tester);
      await tester.enterText(titleField(), 'Quick one');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await TestApp.settle(tester);
      expect((await allTasks(tester, app)).single.title, 'Quick one');
      await app.dispose(tester);
    });

    testWidgets('a new category can be created from the form and used straight away', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, size: tall);
      await openAddForm(tester);
      await tester.enterText(titleField(), 'Mark mid-years');
      await tapInEditor(tester, pill('New'));
      expect(find.text('New category'), findsOneWidget);

      // An empty name does nothing.
      await tester.tap(find.text('Add category'));
      await TestApp.settle(tester);
      expect(find.text('New category'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'e.g. Exams'), ' Exams ');
      await tester.tap(find.byTooltip('Honey'));
      await tester.pump();
      await tester.tap(find.text('Add category'));
      await TestApp.settle(tester);
      expect(inEditor(find.text('Exams')), findsOneWidget);

      await save(tester, 'Save task');
      final task = (await allTasks(tester, app)).single;
      final cats = (await tester.runAsync(() => app.repo.watchCategories().first))!;
      final exams = cats.singleWhere((c) => c.name == 'Exams');
      expect(task.categoryId, exams.id);
      expect(exams.color, PandaColors.honey);
      await app.dispose(tester);
    });

    testWidgets('the form scrolls on a short window instead of overflowing', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: const Size(1100, 500));
      await openAddForm(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Save task'), findsOneWidget, reason: 'the buttons stay visible below the scrolling fields');
      await app.dispose(tester);
    });
  });

  group('due-day chips follow today\'s date', () {
    Future<List<String>> chips(WidgetTester tester, DateTime clock) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, size: tall, now: clock);
      await openAddForm(tester);
      final labels = ['Today', 'Tomorrow', 'This Fri', 'Fri 16 Oct', 'Next week', 'Pick a date'];
      final found = [
        for (final l in labels)
          if (inEditor(find.text(l)).evaluate().isNotEmpty) l,
      ];
      await app.dispose(tester);
      return found;
    }

    testWidgets('on a Monday there is a This Fri chip', (tester) async {
      expect(await chips(tester, DateTime(2026, 10, 5, 9)), [
        'Today',
        'Tomorrow',
        'This Fri',
        'Next week',
        'Pick a date',
      ]);
    });

    testWidgets('on a Thursday Friday is already "Tomorrow", so no This Fri chip', (tester) async {
      expect(await chips(tester, DateTime(2026, 10, 8, 9)), ['Today', 'Tomorrow', 'Next week', 'Pick a date']);
    });

    testWidgets('on a Saturday the Friday chip shows the date', (tester) async {
      expect(await chips(tester, DateTime(2026, 10, 10, 9)), [
        'Today',
        'Tomorrow',
        'Fri 16 Oct',
        'Next week',
        'Pick a date',
      ]);
    });
  });

  group('adding from the calendar', () {
    testWidgets('the Add button next to a day starts a task due that day', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester);
      await tester.tap(find.bySemanticsLabel('Saturday, October 10, 2026'), warnIfMissed: false);
      // Semantics are off here, so select by tapping the number in the grid instead.
      await tester.tap(find.text('10').first);
      await TestApp.settle(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Add'));
      await TestApp.settle(tester);
      expect(inEditor(find.text('Sat 10 Oct')), findsOneWidget);
      await tester.enterText(titleField(), 'Weekend marking');
      await save(tester, 'Save task');
      expect((await allTasks(tester, app)).single.dueAt, DateTime(2026, 10, 10, 23, 59));
      await app.dispose(tester);
    });
  });

  group('editing a task', () {
    testWidgets('the form is pre-filled with the task and saving without changes changes nothing', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      final before = (await allTasks(tester, app)).singleWhere((t) => t.title == 'Mark 3A essays');
      await openTask(tester, 'Mark 3A essays');

      expect(find.text('Edit task'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(titleField().evaluate().isEmpty ? find.byType(TextField).first : titleField())
            .controller!
            .text,
        'Mark 3A essays',
      );
      expect(inEditor(find.text('5:00 pm')), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);

      await save(tester, 'Save changes');
      expect(find.text('Task updated'), findsOneWidget);
      final after = (await allTasks(tester, app)).singleWhere((t) => t.id == before.id);
      expect(after.title, before.title);
      expect(after.dueAt, before.dueAt);
      expect(after.priority, before.priority);
      expect(after.categoryId, before.categoryId);
      expect(after.repeat, before.repeat);
      await app.dispose(tester);
    });

    testWidgets('changes are saved to the same task', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      final id = (await allTasks(tester, app)).singleWhere((t) => t.title == 'Mark 3A essays').id;
      await openTask(tester, 'Mark 3A essays');

      await tester.enterText(editorTitle(), 'Mark 3B essays');
      await tapInEditor(tester, inEditor(find.text('Low')));
      await tapInEditor(tester, pill('Admin'));
      await tapInEditor(tester, pill('Monthly'));
      await tapInEditor(tester, find.byTooltip('Remove 5:00 pm'));
      await save(tester, 'Save changes');

      final all = await allTasks(tester, app);
      expect(all.where((t) => t.id == id), hasLength(1), reason: 'edited in place, not duplicated');
      final t = all.singleWhere((t) => t.id == id);
      expect(t.title, 'Mark 3B essays');
      expect(t.priority, Priority.low);
      expect(t.categoryId, 'admin');
      expect(t.repeat, Repeat.monthly);
      expect(t.dueAt, DateTime(2026, 10, 9, 23, 59));
      await app.dispose(tester);
    });

    testWidgets('notes can be edited and cleared', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await tester.runAsync(
        () => app.repo.addTask(
          TaskDraft(title: 'With notes', dueAt: DateTime(2026, 10, 9, 17), categoryId: 'general', notes: 'Old notes'),
        ),
      );
      await app.pump(tester, size: tall);
      await openTask(tester, 'With notes');
      final notes = find.widgetWithText(TextField, 'Old notes');
      expect(notes, findsOneWidget);
      await tester.enterText(notes, '');
      await save(tester, 'Save changes');
      expect((await allTasks(tester, app)).single.notes, isNull);
      await app.dispose(tester);
    });

    testWidgets('deleting asks first, removes the task, and can be undone', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await openTask(tester, 'Mark 3A essays');
      await tapInEditor(tester, find.widgetWithText(TextButton, 'Delete'));
      expect(find.text('Delete “Mark 3A essays”?'), findsOneWidget);

      // "Keep it" backs out.
      await tester.tap(find.text('Keep it'));
      await TestApp.settle(tester);
      expect(find.byType(TaskEditor), findsOneWidget);
      expect((await allTasks(tester, app)).map((t) => t.title), contains('Mark 3A essays'));

      await tapInEditor(tester, find.widgetWithText(TextButton, 'Delete'));
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Delete')));
      await TestApp.settle(tester);
      expect(find.byType(TaskEditor), findsNothing);
      expect(find.text('Deleted “Mark 3A essays”'), findsOneWidget);
      expect((await allTasks(tester, app)).map((t) => t.title), isNot(contains('Mark 3A essays')));
      expect(doNextTitles(tester), isNot(contains('Mark 3A essays')));

      await tester.tap(find.text('Undo'));
      await TestApp.settle(tester);
      expect((await allTasks(tester, app)).map((t) => t.title), contains('Mark 3A essays'));
      expect(doNextTitles(tester), contains('Mark 3A essays'));
      await app.dispose(tester);
    });
  });

  group('on a phone (bottom sheet)', () {
    testWidgets('opens as a sheet from the big + button', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: phone);
      await tester.tap(find.byTooltip('Add task'));
      await TestApp.settle(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('New task'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await app.dispose(tester);
    });

    testWidgets('Notes comes directly above Repeat, with every field in the recommended order', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: phone);
      await tester.tap(find.byTooltip('Add task'));
      await TestApp.settle(tester);
      double top(String label) => tester.getTopLeft(find.text(label, findRichText: true)).dy;
      final order = [
        'What needs doing?',
        'When is it due?',
        'How important is it?',
        'Category',
        'How long will it take?  (optional)',
        'Notes  (optional)',
        'Repeat',
      ];
      final ys = [for (final l in order) top(l)];
      expect([...ys]..sort(), ys, reason: 'fields appear in order: $order');
      expect(top('Notes  (optional)'), lessThan(top('Repeat')));
      await app.dispose(tester);
    });

    testWidgets('can be filled in and saved, and the buttons share the width', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, size: phone);
      await tester.tap(find.byTooltip('Add task'));
      await TestApp.settle(tester);
      await tester.enterText(titleField(), 'Phone task');
      await tester.enterText(find.widgetWithText(TextField, 'Add any details, links or reminders…'), 'From my phone');
      await save(tester, 'Save task');
      final t = (await allTasks(tester, app)).single;
      expect(t.title, 'Phone task');
      expect(t.notes, 'From my phone');
      await app.dispose(tester);
    });

    testWidgets('editing shows Delete in the header', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: phone);
      await tester.tap(
        find.descendant(of: find.byKey(const ValueKey('do-next')), matching: find.text('Mark 3A essays')),
      );
      await TestApp.settle(tester);
      expect(find.text('Edit task'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Delete'), findsOneWidget);
      await app.dispose(tester);
    });
  });
}
