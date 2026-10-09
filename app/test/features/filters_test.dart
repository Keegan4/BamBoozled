import 'package:bamboozled/core/theme/colors.dart';
import 'package:bamboozled/features/welcome/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

const phone = Size(412, 915);

/// The colour of the stripe on a task card.
Color stripeOf(WidgetTester tester, String title) {
  final card = cardFor(title);
  final stripe = tester
      .widgetList<Container>(find.descendant(of: card, matching: find.byType(Container)))
      .firstWhere((c) => c.color != null && c.constraints?.maxWidth == 8);
  return stripe.color!;
}

Finder chip(String label) =>
    find.descendant(of: find.byType(CategoryChips), matching: find.widgetWithText(InkWell, label));

Future<void> choose(WidgetTester tester, String menu, String option) async {
  await tester.tap(find.byTooltip('Change $menu'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await TestApp.settle(tester);
}

void main() {
  group('category chips (desktop)', () {
    testWidgets('show All plus one chip per category, each with its colour', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      for (final label in ['All', 'General', 'Teaching', 'Admin', 'Meetings', 'CCA', 'Personal']) {
        expect(chip(label), findsOneWidget, reason: label);
      }
      final dots = tester.widgetList<Container>(
        find.descendant(of: find.byType(CategoryChips), matching: find.byType(Container)),
      );
      final colours = {
        for (final c in dots)
          if (c.decoration is BoxDecoration) (c.decoration! as BoxDecoration).color,
      };
      expect(
        colours,
        containsAll([PandaColors.sky, PandaColors.honey, PandaColors.blush, PandaColors.lavender, PandaColors.mint]),
      );
      await app.dispose(tester);
    });

    testWidgets('tapping a chip filters, tapping again un-filters, and several can be combined', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      expect(doNextTitles(tester), hasLength(5));

      await tester.tap(chip('CCA'));
      await TestApp.settle(tester);
      expect(doNextTitles(tester), ['Plan CCA trip']);

      await tester.tap(chip('Meetings'));
      await TestApp.settle(tester);
      expect(doNextTitles(tester).toSet(), {'Plan CCA trip', 'Staff meeting slides'});

      await tester.tap(chip('CCA'));
      await TestApp.settle(tester);
      expect(doNextTitles(tester), ['Staff meeting slides']);

      await tester.tap(chip('All'));
      await TestApp.settle(tester);
      expect(doNextTitles(tester), hasLength(5));
      await app.dispose(tester);
    });
  });

  group('priority and status menus (desktop)', () {
    testWidgets('priority menu filters, and "Any" clears it again', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      expect(find.text('Priority: Any'), findsOneWidget);

      await choose(tester, 'Priority', 'Urgent');
      expect(find.text('Priority: Urgent'), findsOneWidget);
      expect(doNextTitles(tester), ['Plan CCA trip']);

      await choose(tester, 'Priority', 'Low');
      expect(doNextTitles(tester), ['Reply to parent emails', 'Book dentist']);

      await choose(tester, 'Priority', 'Any');
      expect(find.text('Priority: Any'), findsOneWidget);
      expect(doNextTitles(tester), hasLength(5), reason: 'choosing Any must remove the filter');
      await app.dispose(tester);
    });

    testWidgets('status menu: To do is the default, Overdue and Done narrow the list', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      expect(find.text('Status: To do'), findsOneWidget);

      await choose(tester, 'Status', 'Overdue');
      expect(find.text('Status: Overdue'), findsOneWidget);
      expect(doNextTitles(tester), ['Submit term report']);

      await choose(tester, 'Status', 'Done');
      expect(doNextTitles(tester), isEmpty, reason: 'finished tasks are not in the Do next ranking');
      expect(find.text('No tasks match'), findsOneWidget);

      await choose(tester, 'Status', 'All');
      expect(find.text('Status: All'), findsOneWidget);
      expect(doNextTitles(tester), hasLength(5));
      await app.dispose(tester);
    });

    testWidgets('filters combine', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      await tester.tap(chip('Teaching'));
      await TestApp.settle(tester);
      await choose(tester, 'Priority', 'High');
      expect(doNextTitles(tester), ['Mark 3A essays', 'Prepare Sec 2 quiz']);
      await choose(tester, 'Status', 'Overdue');
      expect(doNextTitles(tester), isEmpty);
      await app.dispose(tester);
    });
  });

  group('search', () {
    testWidgets('filters as you type, matching titles, notes and category names', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      await tester.enterText(find.byType(TextField).first, 'quiz');
      await TestApp.settle(tester);
      expect(doNextTitles(tester), ['Prepare Sec 2 quiz']);

      await tester.enterText(find.byType(TextField).first, 'meetings');
      await TestApp.settle(tester);
      expect(doNextTitles(tester), ['Staff meeting slides'], reason: 'matched by category name');
      await app.dispose(tester);
    });

    testWidgets('a clear button appears once there is text, and empties the search', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      expect(find.byTooltip('Clear search'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'essay');
      await TestApp.settle(tester);
      expect(find.byTooltip('Clear search'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await TestApp.settle(tester);
      expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, isEmpty);
      expect(doNextTitles(tester), hasLength(5));
      expect(find.byTooltip('Clear search'), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('"No tasks match" offers a button that clears the search box too', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      await tester.enterText(find.byType(TextField).first, 'zzzz');
      await TestApp.settle(tester);
      expect(find.text('No tasks match'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await TestApp.settle(tester);
      expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, isEmpty);
      expect(doNextTitles(tester), hasLength(5));
      await app.dispose(tester);
    });

    testWidgets('search works together with the category filter', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      await tester.tap(chip('Admin'));
      await tester.enterText(find.byType(TextField).first, 'report');
      await TestApp.settle(tester);
      expect(doNextTitles(tester), ['Submit term report']);
      await app.dispose(tester);
    });
  });

  group('colour coding', () {
    testWidgets('every task card has the colour of its category', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      expect(stripeOf(tester, 'Mark 3A essays'), PandaColors.sky, reason: 'Teaching');
      expect(stripeOf(tester, 'Submit term report'), PandaColors.honey, reason: 'Admin');
      expect(stripeOf(tester, 'Plan CCA trip'), PandaColors.lavender, reason: 'CCA');
      await app.dispose(tester);
    });

    testWidgets('colour is never the only signal: category name and priority are written out', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      final card = cardFor('Plan CCA trip');
      expect(find.descendant(of: card, matching: find.textContaining('CCA')), findsWidgets);
      expect(find.descendant(of: card, matching: find.text('Urgent')), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('overdue tasks stand out with a red border and a written warning', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      expect(
        find.descendant(of: cardFor('Submit term report'), matching: find.textContaining('Overdue by 1 day')),
        findsOneWidget,
      );
      final material = tester.widget<Material>(
        find.descendant(of: cardFor('Submit term report'), matching: find.byType(Material)).first,
      );
      expect((material.shape! as RoundedRectangleBorder).side.color, PandaColors.overdue);
      await app.dispose(tester);
    });
  });

  group('on a phone', () {
    testWidgets('the Filter button shows how many filters are on and opens a sheet', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: phone);
      expect(find.text('Filter'), findsOneWidget);
      await tester.tap(find.text('Filter'));
      await TestApp.settle(tester);
      expect(find.text('Filter tasks'), findsOneWidget);
      for (final heading in ['Category', 'Priority', 'Status']) {
        expect(
          find.descendant(of: find.byType(FilterSheet), matching: find.text(heading)),
          findsOneWidget,
          reason: heading,
        );
      }
      await app.dispose(tester);
    });

    testWidgets('choices in the sheet apply immediately and update the count', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: phone);
      await tester.tap(find.text('Filter'));
      await TestApp.settle(tester);

      Finder inSheet(String label) =>
          find.descendant(of: find.byType(FilterSheet), matching: find.widgetWithText(InkWell, label)).first;
      await tester.tap(inSheet('Teaching'));
      await tester.tap(inSheet('High'));
      await TestApp.settle(tester);
      await tester.tap(find.text('Show tasks'));
      await TestApp.settle(tester);

      expect(find.text('Filter (2)'), findsOneWidget);
      expect(doNextTitles(tester), ['Mark 3A essays', 'Prepare Sec 2 quiz']);
      await app.dispose(tester);
    });

    testWidgets('Clear filters in the sheet resets everything', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: phone);
      await tester.tap(find.text('Filter'));
      await TestApp.settle(tester);
      await tester.tap(
        find.descendant(of: find.byType(FilterSheet), matching: find.widgetWithText(InkWell, 'Urgent')).first,
      );
      await TestApp.settle(tester);
      expect(doNextTitles(tester), ['Plan CCA trip']);
      await tester.tap(find.text('Clear filters'));
      await TestApp.settle(tester);
      await tester.tap(find.text('Show tasks'));
      await TestApp.settle(tester);
      expect(find.text('Filter'), findsOneWidget);
      expect(doNextTitles(tester), hasLength(5));
      await app.dispose(tester);
    });

    testWidgets('the search icon opens a search box, and closing it clears the search', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: phone);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byTooltip('Search'));
      await TestApp.settle(tester);
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'dentist');
      await TestApp.settle(tester);
      expect(doNextTitles(tester), ['Book dentist']);

      await tester.tap(find.byTooltip('Close search'));
      await TestApp.settle(tester);
      expect(find.byType(TextField), findsNothing);
      expect(doNextTitles(tester), hasLength(5));
      await app.dispose(tester);
    });

    testWidgets('category chips scroll sideways on a phone without overflowing', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: phone);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(CategoryChips), const Offset(-300, 0));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await app.dispose(tester);
    });
  });
}
