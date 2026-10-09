import 'package:bamboozled/core/theme/colors.dart';
import 'package:bamboozled/data/repositories/task_repository.dart';
import 'package:bamboozled/domain/models/category.dart';
import 'package:bamboozled/features/tasks/task_editor.dart';
import 'package:bamboozled/features/welcome/widgets/filter_bar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

const phone = Size(412, 915);
const tall = Size(1440, 1800);

/// A repository whose category saving always fails, to see how the dialog copes.
class FailingCategoryRepository extends TaskRepository {
  FailingCategoryRepository(super.db);

  @override
  Future<Category> addCategory(String name, Color color) => Future.error(StateError('disk full'));
}

/// The pill's own highlight (the InkWell inside the "Change Priority" / "Change Status" pill).
Finder pillInk(String tooltip) => find.descendant(of: find.byTooltip(tooltip), matching: find.byType(InkWell));

Finder inEditor(Finder f) => find.descendant(of: find.byType(TaskEditor), matching: f);
Finder nameBox() => find.widgetWithText(TextField, 'e.g. Exams');

Future<void> openNewCategory(WidgetTester tester) async {
  await tester.tap(find.text('Add task'));
  await TestApp.settle(tester);
  await tester.tap(inEditor(find.widgetWithText(InkWell, 'New')).first);
  await TestApp.settle(tester);
  expect(find.text('New category'), findsOneWidget);
}

Future<List<Category>> categories(WidgetTester tester, TestApp app) async =>
    (await tester.runAsync(() => app.repo.watchCategories().first))!;

Future<void> addCategoryThroughForm(WidgetTester tester, String name) async {
  await tester.enterText(nameBox(), name);
  await tester.tap(find.text('Add category'));
  await TestApp.settle(tester);
}

/// Colour of the dot on the category chip in the filter row (or form).
Color? dotOf(WidgetTester tester, Finder scope, String label) {
  final chip = find.descendant(of: scope, matching: find.widgetWithText(InkWell, label)).first;
  final dot = tester
      .widgetList<Container>(find.descendant(of: chip, matching: find.byType(Container)))
      .firstWhere((c) => c.decoration is BoxDecoration && (c.decoration! as BoxDecoration).shape == BoxShape.circle);
  return (dot.decoration! as BoxDecoration).color;
}

Future<void> addManyCategories(WidgetTester tester, TestApp app, int n) => tester.runAsync(() async {
  for (var i = 1; i <= n; i++) {
    await app.repo.addCategory('Subject $i', PandaColors.categoryChoices.values.elementAt(i % 12));
  }
});

ScrollPosition chipScroll(WidgetTester tester) => tester
    .state<ScrollableState>(find.descendant(of: find.byType(CategoryChips), matching: find.byType(Scrollable)))
    .position;

void main() {
  group('creating a category', () {
    testWidgets('a new category is saved, selected on the form, and appears in the filter row', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await openNewCategory(tester);
      await addCategoryThroughForm(tester, 'Exams');
      expect(find.text('New category'), findsNothing);
      expect(find.byType(TaskEditor), findsOneWidget, reason: 'the task form stays open');
      expect(inEditor(find.text('Exams')), findsOneWidget);
      expect((await categories(tester, app)).map((c) => c.name), contains('Exams'));
      expect(find.descendant(of: find.byType(CategoryChips), matching: find.text('Exams')), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the name is trimmed, and the new category goes last', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await openNewCategory(tester);
      await addCategoryThroughForm(tester, '  Marking  ');
      final cats = await categories(tester, app);
      expect(cats.last.name, 'Marking');
      await app.dispose(tester);
    });

    testWidgets('new categories start with different colours, none already in use', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      final starting = <Color?>[];
      for (final name in ['One', 'Two', 'Three', 'Four']) {
        await openNewCategory(tester);
        await addCategoryThroughForm(tester, name);
        starting.add(dotOf(tester, find.byType(TaskEditor), name));
        await tester.tap(find.text('Cancel'));
        await TestApp.settle(tester);
      }
      final builtIn = {
        PandaColors.stone,
        PandaColors.sky,
        PandaColors.honey,
        PandaColors.blush,
        PandaColors.lavender,
        PandaColors.mint,
      };
      expect(starting.toSet(), hasLength(4), reason: 'four different colours');
      expect(
        starting.where(builtIn.contains),
        isEmpty,
        reason: 'and none the same as General, Teaching, Admin, Meetings, CCA or Personal',
      );
      await app.dispose(tester);
    });

    testWidgets('a colour can be picked, and is used', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await openNewCategory(tester);
      await tester.tap(find.byTooltip('Lavender'));
      await tester.pump();
      await addCategoryThroughForm(tester, 'Purple things');
      expect((await categories(tester, app)).last.color, PandaColors.lavender);
      await app.dispose(tester);
    });

    testWidgets('12 colours are offered', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await openNewCategory(tester);
      for (final name in PandaColors.categoryChoices.keys) {
        expect(find.byTooltip(name), findsOneWidget, reason: name);
      }
      expect(PandaColors.categoryChoices, hasLength(12));
      await app.dispose(tester);
    });

    testWidgets('a blank name is refused with a message and the dialog stays open', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await openNewCategory(tester);
      await tester.tap(find.text('Add category'));
      await TestApp.settle(tester);
      expect(find.text('Give the category a name'), findsOneWidget);
      await addCategoryThroughForm(tester, '    ');
      expect(find.text('Give the category a name'), findsOneWidget);
      expect(find.text('New category'), findsOneWidget);
      expect(await categories(tester, app), hasLength(6));
      await app.dispose(tester);
    });

    testWidgets('typing clears the message', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await openNewCategory(tester);
      await tester.tap(find.text('Add category'));
      await TestApp.settle(tester);
      await tester.enterText(nameBox(), 'E');
      await tester.pump();
      expect(find.text('Give the category a name'), findsNothing);
      await app.dispose(tester);
    });

    for (final name in ['teaching', 'TEACHING', ' Teaching ', 'general']) {
      testWidgets('"$name" is refused because that category already exists', (tester) async {
        final app = await TestApp.create();
        await app.pump(tester, size: tall);
        await openNewCategory(tester);
        await addCategoryThroughForm(tester, name);
        expect(find.textContaining('You already have a category called'), findsOneWidget);
        expect(find.text('New category'), findsOneWidget);
        expect(await categories(tester, app), hasLength(6));
        await app.dispose(tester);
      });
    }

    testWidgets('the name box stops at 40 characters', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await openNewCategory(tester);
      await tester.enterText(nameBox(), 'n' * 60);
      expect(tester.widget<TextField>(nameBox()).controller!.text, hasLength(40));
      await app.dispose(tester);
    });

    testWidgets('a double click on Add category adds one category, and does not close the task form', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await openNewCategory(tester);
      await tester.enterText(nameBox(), 'Exams');
      // Three clicks in the same instant, before the screen has had time to react to the first.
      final add = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add category')).onPressed!;
      add();
      add();
      add();
      await TestApp.settle(tester);
      expect((await categories(tester, app)).where((c) => c.name == 'Exams'), hasLength(1));
      expect(find.byType(TaskEditor), findsOneWidget, reason: 'the second click used to close the whole task form');
      await app.dispose(tester);
    });

    testWidgets('pressing Enter twice adds one category', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await openNewCategory(tester);
      await tester.enterText(nameBox(), 'Exams');
      final submit = tester.widget<TextField>(nameBox()).onSubmitted!;
      submit('Exams');
      submit('Exams');
      submit('Exams');
      await TestApp.settle(tester);
      expect((await categories(tester, app)).where((c) => c.name == 'Exams'), hasLength(1));
      await app.dispose(tester);
    });

    testWidgets('if saving fails the dialog says so, stays open, and can be tried again', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall, repository: FailingCategoryRepository(app.db));
      await openNewCategory(tester);
      await addCategoryThroughForm(tester, 'Exams');
      expect(find.text('Couldn’t save the category. Please try again.'), findsOneWidget);
      expect(find.text('New category'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add category')).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await app.dispose(tester);
    });

    testWidgets('Cancel closes the dialog without adding anything, and the task form is still open', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await openNewCategory(tester);
      await tester.enterText(nameBox(), 'Never');
      await tester.tap(find.text('Cancel').first);
      await TestApp.settle(tester);
      expect(find.text('New category'), findsNothing);
      expect(find.byType(TaskEditor), findsOneWidget);
      expect(await categories(tester, app), hasLength(6));
      await app.dispose(tester);
    });

    testWidgets('on a phone it works the same way', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: phone);
      await tester.tap(find.byTooltip('Add task'));
      await TestApp.settle(tester);
      await tester.tap(inEditor(find.widgetWithText(InkWell, 'New')).first);
      await TestApp.settle(tester);
      await addCategoryThroughForm(tester, 'Exams');
      expect(find.byType(TaskEditor), findsOneWidget);
      expect((await categories(tester, app)).map((c) => c.name), contains('Exams'));
      expect(tester.takeException(), isNull);
      await app.dispose(tester);
    });

    testWidgets('twenty categories in a row can be created without trouble', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      for (var i = 1; i <= 20; i++) {
        await openNewCategory(tester);
        await addCategoryThroughForm(tester, 'Category $i');
        await tester.tap(find.text('Cancel'));
        await TestApp.settle(tester);
      }
      expect(await categories(tester, app), hasLength(26));
      expect(tester.takeException(), isNull);
      await app.dispose(tester);
    });

    testWidgets('a task saved in the new category shows that colour', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, size: tall);
      await openNewCategory(tester);
      await tester.tap(find.byTooltip('Rose'));
      await tester.pump();
      await addCategoryThroughForm(tester, 'Rosy');
      await tester.enterText(find.widgetWithText(TextField, 'e.g. Mark 3A essays'), 'In my new category');
      await tester.tap(find.text('Save task'));
      await TestApp.settle(tester);
      final task = (await tester.runAsync(() => app.repo.watchTasks().first))!.single;
      final cat = (await categories(tester, app)).singleWhere((c) => c.id == task.categoryId);
      expect([cat.name, cat.color], ['Rosy', PandaColors.rose]);
      await app.dispose(tester);
    });
  });

  group('reaching every category in the filter row', () {
    testWidgets('with the standard six everything fits and nothing needs scrolling', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      expect(chipScroll(tester).maxScrollExtent, 0);
      await app.dispose(tester);
    });

    testWidgets('with many categories the row scrolls and has a visible scrollbar', (tester) async {
      final app = await TestApp.create();
      await addManyCategories(tester, app, 14);
      await app.pump(tester);
      expect(chipScroll(tester).maxScrollExtent, greaterThan(200));
      final bar = tester.widget<Scrollbar>(
        find.descendant(of: find.byType(CategoryChips), matching: find.byType(Scrollbar)),
      );
      expect(bar.thumbVisibility, isTrue, reason: 'the bar is always shown, so people know there is more');
      expect(bar.trackVisibility, isTrue);
      await app.dispose(tester);
    });

    testWidgets('the scrollbar sits below the chips and does not cover them', (tester) async {
      final app = await TestApp.create();
      await addManyCategories(tester, app, 14);
      await app.pump(tester);
      final chips = tester.getRect(
        find.descendant(of: find.byType(CategoryChips), matching: find.widgetWithText(InkWell, 'All')),
      );
      final area = tester.getRect(find.byType(CategoryChips));
      expect(area.bottom - chips.bottom, greaterThanOrEqualTo(10));
      await app.dispose(tester);
    });

    testWidgets('the last category starts off-screen and can be reached by dragging with a finger', (tester) async {
      final app = await TestApp.create();
      await addManyCategories(tester, app, 14);
      await app.pump(tester);
      final row = tester.getRect(find.byType(CategoryChips));
      Rect last() => tester.getRect(
        find.descendant(of: find.byType(CategoryChips), matching: find.widgetWithText(InkWell, 'Subject 14')).first,
      );
      expect(last().right, greaterThan(row.right), reason: 'cut off at the edge before scrolling');
      await tester.drag(find.byType(CategoryChips), const Offset(-2000, 0));
      await tester.pump();
      expect(last().right, lessThanOrEqualTo(row.right + 1));
      await app.dispose(tester);
    });

    testWidgets('it can be dragged with the mouse too', (tester) async {
      final app = await TestApp.create();
      await addManyCategories(tester, app, 14);
      await app.pump(tester);
      await tester.drag(find.byType(CategoryChips), const Offset(-300, 0), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(chipScroll(tester).pixels, greaterThan(100));
      await app.dispose(tester);
    });

    testWidgets('the mouse wheel scrolls the row sideways', (tester) async {
      final app = await TestApp.create();
      await addManyCategories(tester, app, 14);
      await app.pump(tester);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(tester.getCenter(find.byType(CategoryChips))));
      expect(chipScroll(tester).pixels, 0);
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 150)));
      await tester.pump();
      expect(chipScroll(tester).pixels, 150);
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -60)));
      await tester.pump();
      expect(chipScroll(tester).pixels, 90);
      await app.dispose(tester);
    });

    testWidgets('wheeling past either end stops at the end', (tester) async {
      final app = await TestApp.create();
      await addManyCategories(tester, app, 14);
      await app.pump(tester);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(tester.getCenter(find.byType(CategoryChips))));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100000)));
      await tester.pump();
      expect(chipScroll(tester).pixels, chipScroll(tester).maxScrollExtent);
      expect(tester.takeException(), isNull);
      await app.dispose(tester);
    });

    testWidgets('after scrolling, the last category can be tapped to filter by it', (tester) async {
      final app = await TestApp.create();
      await tester.runAsync(() async {
        for (var i = 1; i <= 14; i++) {
          await app.repo.addCategory('Subject $i', PandaColors.slate);
        }
        await app.repo.addTask(
          TaskDraft(
            title: 'In the last category',
            dueAt: DateTime(2026, 10, 9),
            categoryId: (await app.repo.watchCategories().first).last.id,
          ),
        );
      });
      await app.pump(tester);
      await tester.drag(find.byType(CategoryChips), const Offset(-3000, 0));
      await tester.pump();
      await tester.tap(
        find.descendant(of: find.byType(CategoryChips), matching: find.widgetWithText(InkWell, 'Subject 14')).first,
      );
      await TestApp.settle(tester);
      expect(doNextTitles(tester), ['In the last category']);
      expect(find.text('Showing only: Subject 14'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the scrolling scrollbar and chips also work on a phone', (tester) async {
      final app = await TestApp.create();
      await addManyCategories(tester, app, 8);
      await app.pump(tester, size: phone);
      expect(chipScroll(tester).maxScrollExtent, greaterThan(0));
      expect(find.descendant(of: find.byType(CategoryChips), matching: find.byType(Scrollbar)), findsOneWidget);
      expect(tester.takeException(), isNull);
      await app.dispose(tester);
    });

    testWidgets('the phone filter sheet lists every category without scrolling sideways', (tester) async {
      final app = await TestApp.create();
      await addManyCategories(tester, app, 10);
      await app.pump(tester, size: phone);
      await tester.tap(find.text('Filter'));
      await TestApp.settle(tester);
      for (final i in [1, 5, 10]) {
        expect(
          find.descendant(of: find.byType(FilterSheet), matching: find.text('Subject $i')),
          findsOneWidget,
          reason: 'Subject $i',
        );
      }
      await app.dispose(tester);
    });

    testWidgets('a category made on the form is in the row straight away', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await openNewCategory(tester);
      await addCategoryThroughForm(tester, 'Fresh');
      expect(find.descendant(of: find.byType(CategoryChips), matching: find.text('Fresh')), findsOneWidget);
      await app.dispose(tester);
    });
  });

  group('the priority and status menus', () {
    testWidgets('the pill clips its highlight to its own rounded shape', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      for (final label in ['Change Priority', 'Change Status']) {
        final material = tester.widget<Material>(
          find.ancestor(of: pillInk(label), matching: find.byType(Material)).first,
        );
        expect(material.shape, isA<StadiumBorder>(), reason: label);
        expect(material.clipBehavior, Clip.antiAlias, reason: label);
      }
      await app.dispose(tester);
    });

    testWidgets('hovering with a mouse paints a highlight no bigger than the pill', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      final pill = find.byTooltip('Change Priority');
      final pillRect = tester.getRect(pill);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(pill));
      await tester.pump(const Duration(milliseconds: 200));
      final ink = tester.getRect(pillInk('Change Priority'));
      expect(ink.width, closeTo(pillRect.width, 1));
      expect(ink.height, closeTo(pillRect.height, 1));
      await mouse.removePointer();
      await app.dispose(tester);
    });
  });

  group('saving a task safely', () {
    testWidgets('pressing Enter twice saves one task', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, size: tall);
      await tester.tap(find.text('Add task'));
      await TestApp.settle(tester);
      final title = find.widgetWithText(TextField, 'e.g. Mark 3A essays');
      await tester.enterText(title, 'Only once');
      final submit = tester.widget<TextField>(title).onSubmitted!;
      submit('Only once'); // a held Enter key fires this many times in a row
      submit('Only once');
      submit('Only once');
      await TestApp.settle(tester);
      expect(
        (await tester.runAsync(() => app.repo.watchTasks().first))!.where((t) => t.title == 'Only once'),
        hasLength(1),
      );
      await app.dispose(tester);
    });

    testWidgets('clicking Save task several times saves one task', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, size: tall);
      await tester.tap(find.text('Add task'));
      await TestApp.settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'e.g. Mark 3A essays'), 'Only once');
      final save = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save task')).onPressed!;
      for (var i = 0; i < 4; i++) {
        save();
      }
      await TestApp.settle(tester);
      expect(
        (await tester.runAsync(() => app.repo.watchTasks().first))!.where((t) => t.title == 'Only once'),
        hasLength(1),
      );
      await app.dispose(tester);
    });

    testWidgets('editing a task that was finished in the meantime keeps it finished', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall);
      await tester.tap(find.text('Mark 3A essays'));
      await TestApp.settle(tester);
      expect(find.text('Edit task'), findsOneWidget);
      final id = (await tester.runAsync(() => app.repo.watchTasks().first))!
          .singleWhere((t) => t.title == 'Mark 3A essays')
          .id;
      await tester.runAsync(() => app.repo.setDone(id, true)); // e.g. ticked on another device while the form was open
      await tester.enterText(inEditor(find.byType(TextField)).first, 'Mark 3A essays (second half)');
      await tester.tap(find.text('Save changes'));
      await TestApp.settle(tester);
      final saved = (await tester.runAsync(() => app.repo.getTask(id)))!;
      expect(saved.title, 'Mark 3A essays (second half)');
      expect(saved.isDone, isTrue, reason: 'saving the form must not silently un-finish the task');
      await app.dispose(tester);
    });
  });
}
