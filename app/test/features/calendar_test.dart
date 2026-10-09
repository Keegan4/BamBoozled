import 'package:bamboozled/core/theme/colors.dart';
import 'package:bamboozled/data/repositories/task_repository.dart';
import 'package:bamboozled/domain/models/priority.dart';
import 'package:bamboozled/features/tasks/task_editor.dart';
import 'package:bamboozled/features/welcome/widgets/calendar_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

const phone = Size(412, 915);

/// Coloured dots drawn under the days in a calendar.
List<Color> dots(WidgetTester tester, Type calendar) => [
  for (final c in tester.widgetList<Container>(
    find.descendant(of: find.byType(calendar), matching: find.byType(Container)),
  ))
    if (c.decoration is BoxDecoration &&
        (c.decoration! as BoxDecoration).shape == BoxShape.circle &&
        c.constraints?.maxWidth == 8 &&
        (c.decoration! as BoxDecoration).color != null)
      (c.decoration! as BoxDecoration).color!,
];

Finder dayNumber(String n, Type calendar) => find.descendant(of: find.byType(calendar), matching: find.text(n)).first;

Finder panel(Finder f) => find.descendant(of: find.byType(CalendarPanel), matching: f);

void main() {
  group('calendar panel (desktop)', () {
    testWidgets('shows the current month with Monday-first weekday headings', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      expect(find.text('October 2026'), findsOneWidget);
      final headings = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      for (final h in headings) {
        expect(panel(find.text(h)), findsOneWidget, reason: h);
      }
      // Each heading is further right than the previous one.
      final xs = [for (final h in headings) tester.getCenter(panel(find.text(h))).dx];
      expect([...xs]..sort(), xs);
      // The month grid shows all 31 days.
      for (final d in ['1', '15', '31']) {
        expect(panel(find.text(d)), findsWidgets, reason: 'day $d');
      }
      await app.dispose(tester);
    });

    testWidgets('today is highlighted in green and the selected day in black', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      Color? circleBehind(String day) {
        final circle = find.ancestor(of: panel(find.text(day)).first, matching: find.byType(Container)).first;
        return (tester.widget<Container>(circle).decoration! as BoxDecoration).color;
      }

      // Today (8th) is also the selected day on first load; today wins so it is always findable.
      expect(circleBehind('8'), PandaColors.bamboo);
      await tester.tap(dayNumber('15', CalendarPanel));
      await TestApp.settle(tester);
      expect(circleBehind('15'), PandaColors.ink);
      expect(circleBehind('8'), PandaColors.bamboo);
      await app.dispose(tester);
    });

    testWidgets('previous and next move a month at a time, and Today comes back', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      await tester.tap(find.byTooltip('Next month'));
      await TestApp.settle(tester);
      expect(find.text('November 2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Next month'));
      await TestApp.settle(tester);
      expect(find.text('December 2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous month'));
      await tester.tap(find.byTooltip('Previous month'));
      await tester.tap(find.byTooltip('Previous month'));
      await TestApp.settle(tester);
      expect(find.text('September 2026'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Today'));
      await TestApp.settle(tester);
      expect(find.text('October 2026'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('swiping sideways changes the month', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      await tester.drag(find.byType(PandaCalendar), const Offset(-600, 0));
      await TestApp.settle(tester);
      expect(find.text('November 2026'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('Week view shows a single row and arrows move a week at a time', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      final monthHeight = tester.getSize(find.byType(PandaCalendar)).height;
      await tester.tap(find.text('Week'));
      await TestApp.settle(tester);
      expect(tester.getSize(find.byType(PandaCalendar)).height, lessThan(monthHeight / 3));
      expect(find.byTooltip('Next week'), findsOneWidget);
      expect(find.byTooltip('Previous week'), findsOneWidget);

      await tester.tap(find.byTooltip('Next week'));
      await tester.tap(find.byTooltip('Next week'));
      await TestApp.settle(tester);
      expect(panel(find.text('22')), findsWidgets, reason: 'two weeks on from the 8th');
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Month'));
      await TestApp.settle(tester);
      expect(tester.getSize(find.byType(PandaCalendar)).height, closeTo(monthHeight, 1));
      await app.dispose(tester);
    });

    testWidgets('the week view can page through months without layout errors', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: const Size(1437.3333333333333, 900));
      await tester.tap(find.text('Week'));
      await TestApp.settle(tester);
      for (var i = 0; i < 12; i++) {
        await tester.tap(find.byTooltip('Next week'));
      }
      await TestApp.settle(tester);
      expect(tester.takeException(), isNull);
      await app.dispose(tester);
    });
  });

  group('days and their tasks', () {
    testWidgets('selecting a day lists that day\'s tasks under the calendar', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      expect(find.text('Today'), findsWidgets);
      await tester.tap(dayNumber('15', CalendarPanel));
      await TestApp.settle(tester);
      expect(find.text('Thursday 15 October'), findsOneWidget);
      expect(panel(find.text('Plan CCA trip')), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('a day with no tasks says so', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      await tester.tap(dayNumber('10', CalendarPanel));
      await TestApp.settle(tester);
      expect(find.text('Saturday 10 October'), findsOneWidget);
      expect(find.text('Nothing due — enjoy the bamboo.'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('ticking a task in the day list completes it', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      await tester.tap(panel(find.byType(InkResponse)).first);
      await TestApp.settle(tester);
      expect(find.textContaining('Nice work!'), findsOneWidget);
      expect(doNextTitles(tester), isNot(contains('Reply to parent emails')));
      await app.dispose(tester);
    });

    testWidgets('the Add button next to the day opens the form on that day', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: const Size(1440, 1800));
      await tester.tap(dayNumber('13', CalendarPanel));
      await TestApp.settle(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Add'));
      await TestApp.settle(tester);
      expect(find.byType(TaskEditor), findsOneWidget);
      expect(find.descendant(of: find.byType(TaskEditor), matching: find.text('Tue 13 Oct')), findsOneWidget);
      await app.dispose(tester);
    });
  });

  group('dots under the days', () {
    testWidgets('each day shows a dot in the colour of its tasks\' categories', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      final colours = dots(tester, CalendarPanel);
      expect(colours.where((c) => c == PandaColors.lavender), hasLength(1), reason: 'CCA trip on the 15th');
      expect(colours.where((c) => c == PandaColors.blush), hasLength(1), reason: 'staff meeting on the 14th');
      expect(colours.where((c) => c == PandaColors.mint), hasLength(1), reason: 'dentist on the 16th');
      expect(colours.where((c) => c == PandaColors.honey), hasLength(2), reason: 'report (7th) and emails (8th)');
      await app.dispose(tester);
    });

    testWidgets('at most three dots, one per category, however many tasks are due', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await tester.runAsync(() async {
        for (final cat in ['teaching', 'teaching', 'admin', 'cca', 'meetings', 'personal']) {
          await app.repo.addTask(
            TaskDraft(title: 'Busy $cat', dueAt: DateTime(2026, 10, 20, 10), priority: Priority.low, categoryId: cat),
          );
        }
      });
      await app.pump(tester);
      expect(dots(tester, CalendarPanel), hasLength(3));
      await app.dispose(tester);
    });

    testWidgets('dots follow the filters', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      final before = dots(tester, CalendarPanel).length;
      await tester.tap(find.widgetWithText(InkWell, 'CCA').first);
      await TestApp.settle(tester);
      expect(dots(tester, CalendarPanel), [PandaColors.lavender]);
      expect(before, greaterThan(1));
      await app.dispose(tester);
    });

    testWidgets('finished tasks have no dot until the Status filter includes them', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      final before = dots(tester, CalendarPanel).length;
      await tester.tap(find.byTooltip('Change Status'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All').last);
      await TestApp.settle(tester);
      expect(dots(tester, CalendarPanel).length, before + 1, reason: 'the finished worksheet on the 6th appears');
      await app.dispose(tester);
    });
  });

  group('phone week strip', () {
    testWidgets('starts as a single week with a Month button', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: phone);
      expect(find.byType(WeekStrip), findsOneWidget);
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('Month'), findsOneWidget);
      for (final d in ['5', '6', '7', '8', '9', '10', '11']) {
        expect(dayNumber(d, WeekStrip), findsOneWidget, reason: 'day $d is in this week');
      }
      expect(find.descendant(of: find.byType(WeekStrip), matching: find.text('15')), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('Month expands the strip into the full month and Week collapses it again', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: phone);
      final collapsed = tester.getSize(find.byType(WeekStrip)).height;
      await tester.tap(find.text('Month'));
      await TestApp.settle(tester);
      expect(tester.getSize(find.byType(WeekStrip)).height, greaterThan(collapsed + 150));
      expect(find.text('Week'), findsOneWidget);
      expect(dayNumber('15', WeekStrip), findsOneWidget);

      await tester.tap(find.text('Week'));
      await TestApp.settle(tester);
      expect(tester.getSize(find.byType(WeekStrip)).height, closeTo(collapsed, 1));
      expect(tester.takeException(), isNull);
      await app.dispose(tester);
    });

    testWidgets('tapping another day opens its tasks, and × returns to today', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: phone);
      expect(find.text('Friday 9 October'), findsNothing);
      await tester.tap(dayNumber('9', WeekStrip));
      await TestApp.settle(tester);
      expect(find.text('Friday 9 October'), findsOneWidget);
      expect(find.descendant(of: find.byType(SelectedDayTasks), matching: find.text('Mark 3A essays')), findsOneWidget);

      await tester.tap(find.byTooltip('Back to today'));
      await TestApp.settle(tester);
      expect(find.text('Friday 9 October'), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('the expanded month works on a phone for days in other weeks', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: phone);
      await tester.tap(find.text('Month'));
      await TestApp.settle(tester);
      await tester.tap(dayNumber('15', WeekStrip));
      await TestApp.settle(tester);
      expect(find.text('Thursday 15 October'), findsOneWidget);
      expect(find.descendant(of: find.byType(SelectedDayTasks), matching: find.text('Plan CCA trip')), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('dots show on the strip too', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: phone);
      expect(dots(tester, WeekStrip), containsAll([PandaColors.honey]));
      await app.dispose(tester);
    });
  });

  group('Calendar page', () {
    testWidgets('has a title, filters and the full calendar', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, location: '/calendar');
      expect(find.text('Calendar'), findsWidgets);
      expect(find.byType(CalendarPanel), findsOneWidget);
      expect(find.text('Priority: Any'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('on a phone it uses the compact filter button', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: phone, location: '/calendar');
      expect(find.text('Filter'), findsOneWidget);
      expect(find.byType(CalendarPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
      await app.dispose(tester);
    });
  });
}
