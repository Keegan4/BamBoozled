import 'package:bamboozled/core/theme/colors.dart';
import 'package:bamboozled/core/theme/panda_theme.dart';
import 'package:bamboozled/core/widgets/leaf_icon.dart';
import 'package:bamboozled/core/widgets/panda_mascot.dart';
import 'package:bamboozled/core/widgets/pills.dart';
import 'package:bamboozled/core/widgets/priority_badge.dart';
import 'package:bamboozled/domain/models/priority.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpWidgetUnderTest(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: buildPandaTheme(),
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  group('OptionPill', () {
    testWidgets('shows its label and calls onTap', (tester) async {
      var taps = 0;
      await pumpWidgetUnderTest(tester, OptionPill(label: 'Tomorrow', selected: false, onTap: () => taps++));
      expect(find.text('Tomorrow'), findsOneWidget);
      await tester.tap(find.text('Tomorrow'));
      expect(taps, 1);
    });

    testWidgets('is at least 44px tall, so it is easy to tap', (tester) async {
      await pumpWidgetUnderTest(tester, OptionPill(label: 'Today', selected: false, onTap: () {}));
      expect(tester.getSize(find.byType(OptionPill)).height, greaterThanOrEqualTo(44));
    });

    testWidgets('a selected tint pill shows a tick and reports itself as selected', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpWidgetUnderTest(tester, OptionPill(label: 'Today', selected: true, onTap: () {}));
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(OptionPill)),
        isSemantics(isSelected: true, isButton: true, label: 'Today'),
      );
      handle.dispose();
    });

    testWidgets('an unselected pill has no tick', (tester) async {
      await pumpWidgetUnderTest(tester, OptionPill(label: 'Today', selected: false, onTap: () {}));
      expect(find.byIcon(Icons.check_rounded), findsNothing);
    });

    testWidgets('an ink pill turns black when selected and white when not', (tester) async {
      Color? fill() => tester
          .widget<Material>(find.descendant(of: find.byType(OptionPill), matching: find.byType(Material)).first)
          .color;
      await pumpWidgetUnderTest(
        tester,
        OptionPill(label: 'Admin', selected: true, style: OptionPillStyle.ink, onTap: () {}),
      );
      expect(fill(), PandaColors.ink);
      await pumpWidgetUnderTest(
        tester,
        OptionPill(label: 'Admin', selected: false, style: OptionPillStyle.ink, onTap: () {}),
      );
      expect(fill(), PandaColors.surface);
    });

    testWidgets('a category dot shows the category colour instead of a tick', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        OptionPill(label: 'Teaching', selected: true, dotColor: PandaColors.sky, onTap: () {}),
      );
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      final dot = tester.widgetList<Container>(find.byType(Container)).where((c) {
        final d = c.decoration;
        return d is BoxDecoration && d.color == PandaColors.sky && d.shape == BoxShape.circle;
      });
      expect(dot, hasLength(1));
    });

    testWidgets('an icon can be shown before the label', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        OptionPill(label: 'Pick a date', icon: Icons.calendar_month_rounded, selected: false, onTap: () {}),
      );
      expect(find.byIcon(Icons.calendar_month_rounded), findsOneWidget);
    });

    testWidgets('onRemove adds a labelled × button that clears the option', (tester) async {
      var removed = 0, taps = 0;
      await pumpWidgetUnderTest(
        tester,
        OptionPill(label: '5:00 pm', selected: false, onTap: () => taps++, onRemove: () => removed++),
      );
      await tester.tap(find.byTooltip('Remove 5:00 pm'));
      expect(removed, 1);
      expect(taps, 0, reason: 'tapping × must not also tap the pill');
    });
  });

  group('DropdownPill', () {
    Widget pill(ValueChanged<Priority?> onSelected, {Priority? value}) => DropdownPill<Priority?>(
      label: 'Priority',
      value: value,
      items: const {null: 'Any', Priority.low: 'Low', Priority.urgent: 'Urgent'},
      onSelected: onSelected,
    );

    testWidgets('shows the label with the current choice', (tester) async {
      await pumpWidgetUnderTest(tester, pill((_) {}));
      expect(find.text('Priority: Any'), findsOneWidget);
      await pumpWidgetUnderTest(tester, pill((_) {}, value: Priority.urgent));
      expect(find.text('Priority: Urgent'), findsOneWidget);
    });

    testWidgets('opens a menu of every choice and reports the one tapped', (tester) async {
      Priority? picked = Priority.low;
      var calls = 0;
      await pumpWidgetUnderTest(
        tester,
        pill((p) {
          picked = p;
          calls++;
        }, value: Priority.low),
      );
      await tester.tap(find.byType(DropdownPill<Priority?>));
      await tester.pumpAndSettle();
      expect(find.text('Any'), findsOneWidget);
      expect(find.text('Low'), findsOneWidget);
      expect(find.text('Urgent'), findsOneWidget);
      await tester.tap(find.text('Urgent'));
      await tester.pumpAndSettle();
      expect(picked, Priority.urgent);
      expect(calls, 1);
    });

    testWidgets('choosing "Any" reports null', (tester) async {
      Priority? picked = Priority.low;
      await pumpWidgetUnderTest(tester, pill((p) => picked = p, value: Priority.low));
      await tester.tap(find.byType(DropdownPill<Priority?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Any'));
      await tester.pumpAndSettle();
      expect(picked, isNull);
    });

    testWidgets('has a tooltip for screen readers and hover', (tester) async {
      await pumpWidgetUnderTest(tester, pill((_) {}));
      expect(find.byTooltip('Change Priority'), findsOneWidget);
    });
  });

  group('PandaCard', () {
    testWidgets('wraps its child with the padding it is given', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const PandaCard(padding: EdgeInsets.all(10), child: SizedBox(width: 100, height: 50)),
      );
      // 10px padding + 1px border on each side.
      expect(tester.getSize(find.byType(PandaCard)), const Size(122, 72));
    });
  });

  group('PriorityBadge', () {
    for (final p in Priority.values) {
      testWidgets('${p.label} shows ${p.weight} leaf/leaves and its name', (tester) async {
        await pumpWidgetUnderTest(tester, PriorityBadge(priority: p));
        expect(find.byType(LeafIcon), findsNWidgets(p.weight));
        expect(find.text(p.label), findsOneWidget, reason: 'priority is never shown by colour alone');
      });
    }

    testWidgets('can hide the label but keeps the leaves and a spoken label', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpWidgetUnderTest(tester, const PriorityBadge(priority: Priority.high, showLabel: false));
      expect(find.text('High'), findsNothing);
      expect(find.byType(LeafIcon), findsNWidgets(3));
      expect(find.bySemanticsLabel('High priority'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('urgent is red, everything else green', (tester) async {
      Color? background() {
        final box = tester.widget<Container>(
          find.descendant(of: find.byType(PriorityBadge), matching: find.byType(Container)).first,
        );
        return (box.decoration! as BoxDecoration).color;
      }

      await pumpWidgetUnderTest(tester, const PriorityBadge(priority: Priority.urgent));
      expect(background(), PandaColors.overdueTint);
      await pumpWidgetUnderTest(tester, const PriorityBadge(priority: Priority.medium));
      expect(background(), PandaColors.bambooTint);
    });
  });

  group('PandaMascot and LeafIcon', () {
    testWidgets('mascot draws at the size requested, awake or asleep', (tester) async {
      await pumpWidgetUnderTest(tester, const PandaMascot(size: 120));
      expect(tester.getSize(find.byType(PandaMascot)), const Size(120, 120));
      await pumpWidgetUnderTest(tester, const PandaMascot(size: 48, sleeping: true));
      expect(tester.getSize(find.byType(PandaMascot)), const Size(48, 48));
      expect(tester.takeException(), isNull);
    });

    testWidgets('mascot repaints when it falls asleep', (tester) async {
      await pumpWidgetUnderTest(tester, const PandaMascot());
      await pumpWidgetUnderTest(tester, const PandaMascot(sleeping: true));
      expect(tester.takeException(), isNull);
    });

    testWidgets('mascot is hidden from screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpWidgetUnderTest(tester, const PandaMascot());
      expect(find.byType(ExcludeSemantics), findsWidgets);
      handle.dispose();
    });

    testWidgets('leaf draws at the size and colour requested', (tester) async {
      await pumpWidgetUnderTest(tester, const LeafIcon(size: 30, color: PandaColors.overdue));
      expect(tester.getSize(find.byType(LeafIcon)), const Size(30, 30));
      await pumpWidgetUnderTest(tester, const LeafIcon(size: 30, color: PandaColors.bambooDark));
      expect(tester.takeException(), isNull);
    });
  });
}
