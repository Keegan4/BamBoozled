import 'package:bamboozled/core/layout/adaptive_scaffold.dart';
import 'package:bamboozled/features/tasks/task_editor.dart';
import 'package:bamboozled/features/tasks/widgets/task_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

const phone = Size(412, 915);

List<String> allTaskTitles(WidgetTester tester) =>
    tester.widgetList<TaskCard>(find.byType(TaskCard)).map((c) => c.task.title).toList();

Finder rail(String label) => find.descendant(of: find.byType(AdaptiveScaffold), matching: find.text(label));

void main() {
  group('navigation (desktop and tablet)', () {
    testWidgets('a side rail lists Home, Calendar, Notes and Settings, with no bottom bar', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      for (final label in ['Home', 'Calendar', 'Notes', 'Settings']) {
        expect(rail(label), findsOneWidget, reason: label);
      }
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byTooltip('Add task'), findsNothing, reason: 'the big + button is phone-only');
      await app.dispose(tester);
    });

    testWidgets('each destination opens its page', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);

      await tester.tap(rail('Calendar'));
      await TestApp.settle(tester);
      expect(find.text('Calendar'), findsWidgets);
      expect(find.text('October 2026'), findsOneWidget);

      await tester.tap(rail('Notes'));
      await TestApp.settle(tester);
      expect(find.text('Notes are coming soon'), findsOneWidget);
      expect(find.text('The panda is still sharpening its pencils.'), findsOneWidget);

      await tester.tap(rail('Settings'));
      await TestApp.settle(tester);
      expect(find.text('Your name'), findsOneWidget);

      await tester.tap(rail('Home'));
      await TestApp.settle(tester);
      expect(find.text('Good morning, Ms Tan'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the panda logo takes you home', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, location: '/settings');
      expect(find.text('Your name'), findsOneWidget);
      await tester.tap(find.byTooltip('BamBoozled'));
      await TestApp.settle(tester);
      expect(find.text('Good morning, Ms Tan'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the current page is marked as selected', (tester) async {
      final handle = tester.ensureSemantics();
      final app = await TestApp.create();
      await app.pump(tester, location: '/calendar');
      expect(tester.getSemantics(find.bySemanticsLabel('Calendar').first).flagsCollection.isSelected, isNotNull);
      handle.dispose();
      await app.dispose(tester);
    });

    for (final (path, marker) in [
      ('/', 'Good morning, Ms Tan'),
      ('/tasks', 'All tasks'),
      ('/calendar', 'October 2026'),
      ('/notes', 'Notes are coming soon'),
      ('/settings', 'Your name'),
    ]) {
      testWidgets('opening $path directly shows the right page', (tester) async {
        final app = await TestApp.create();
        await app.pump(tester, location: path);
        expect(find.text(marker), findsOneWidget);
        await app.dispose(tester);
      });
    }

    testWidgets('a tablet-width window still gets the side rail', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: const Size(700, 900));
      expect(rail('Settings'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await app.dispose(tester);
    });
  });

  group('navigation (phone)', () {
    testWidgets('a bottom bar replaces the side rail', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: phone);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      await app.dispose(tester);
    });

    testWidgets('each tab opens its page', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: phone);
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Calendar')));
      await TestApp.settle(tester);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Calendar'), findsWidgets);
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Notes')));
      await TestApp.settle(tester);
      expect(find.text('Notes are coming soon'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Settings')));
      await TestApp.settle(tester);
      expect(find.text('Your name'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Home')));
      await TestApp.settle(tester);
      expect(find.text('Good morning, Ms Tan'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the big + button shows on Home and All tasks only', (tester) async {
      final app = await TestApp.create();
      for (final (path, shown) in [
        ('/', true),
        ('/tasks', true),
        ('/calendar', false),
        ('/notes', false),
        ('/settings', false),
      ]) {
        await app.pump(tester, size: phone, location: path);
        expect(find.byTooltip('Add task'), shown ? findsOneWidget : findsNothing, reason: path);
        await tester.pumpWidget(const SizedBox());
      }
      await app.dispose(tester);
    });

    testWidgets('the + button is big enough to tap easily and opens the form', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: phone);
      expect(tester.getSize(find.byType(FloatingActionButton)).width, greaterThanOrEqualTo(56));
      await tester.tap(find.byTooltip('Add task'));
      await TestApp.settle(tester);
      expect(find.byType(TaskEditor), findsOneWidget);
      await app.dispose(tester);
    });
  });

  group('All tasks page', () {
    testWidgets('lists every to-do task in Do-next order, and hides finished ones by default', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, location: '/tasks');
      expect(find.text('All tasks'), findsOneWidget);
      expect(allTaskTitles(tester), [
        'Submit term report',
        'Mark 3A essays',
        'Reply to parent emails',
        'Plan CCA trip',
        'Prepare Sec 2 quiz',
        'Staff meeting slides',
        'Book dentist',
      ]);
      expect(find.text('Done'), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('choosing Status: All adds a Done section, most recently finished first', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, location: '/tasks');
      await tester.tap(find.byTooltip('Change Status'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(MenuItemButton), matching: find.text('All')));
      await TestApp.settle(tester);
      expect(find.text('Done'), findsOneWidget);
      expect(allTaskTitles(tester).last, 'Print worksheets');
      expect(allTaskTitles(tester), hasLength(8));
      await app.dispose(tester);
    });

    testWidgets('search and filters work here too, and an empty result is explained', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, location: '/tasks');
      await tester.enterText(find.byType(TextField).first, 'quiz');
      await TestApp.settle(tester);
      expect(allTaskTitles(tester), ['Prepare Sec 2 quiz']);
      await tester.enterText(find.byType(TextField).first, 'zzzz');
      await TestApp.settle(tester);
      expect(find.text('No tasks match.'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the back arrow returns home', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, location: '/tasks');
      await tester.tap(find.byTooltip('Back'));
      await TestApp.settle(tester);
      expect(find.text('Good morning, Ms Tan'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('on a phone it fits and has the compact filter button', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: phone, location: '/tasks');
      expect(find.text('Filter'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await app.dispose(tester);
    });

    testWidgets('tapping a task opens it for editing', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, location: '/tasks');
      await tester.tap(find.text('Book dentist'));
      await TestApp.settle(tester);
      expect(find.text('Edit task'), findsOneWidget);
      await app.dispose(tester);
    });
  });

  group('Notes page', () {
    testWidgets('is a friendly placeholder on every screen size', (tester) async {
      final app = await TestApp.create();
      for (final size in [phone, const Size(800, 900), const Size(1440, 900)]) {
        await app.pump(tester, size: size, location: '/notes');
        expect(find.text('Notes are coming soon'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
      await app.dispose(tester);
    });
  });
}
