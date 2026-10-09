import 'package:bamboozled/core/theme/colors.dart';
import 'package:bamboozled/core/theme/panda_theme.dart';
import 'package:bamboozled/core/widgets/leaf_icon.dart';
import 'package:bamboozled/core/widgets/priority_badge.dart';
import 'package:bamboozled/domain/models/category.dart';
import 'package:bamboozled/domain/models/priority.dart';
import 'package:bamboozled/domain/models/task.dart';
import 'package:bamboozled/features/tasks/widgets/task_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 10, 8, 9);
final teaching = Category(id: 'teaching', name: 'Teaching', color: PandaColors.sky, updatedAt: now);

Task makeTask({String title = 'Mark 3A essays', DateTime? due, Priority priority = Priority.high, DateTime? done}) =>
    Task(
      id: 't',
      title: title,
      dueAt: due ?? DateTime(2026, 10, 9, 17),
      priority: priority,
      categoryId: 'teaching',
      completedAt: done,
      createdAt: now,
      updatedAt: now,
    );

Future<void> pumpCard(
  WidgetTester tester, {
  Task? task,
  Category? category,
  double width = 480,
  VoidCallback? onToggle,
  VoidCallback? onOpen,
  String? tooltip,
}) => tester.pumpWidget(
  MaterialApp(
    theme: buildPandaTheme(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: TaskCard(
            task: task ?? makeTask(),
            category: category ?? teaching,
            now: now,
            onToggleDone: onToggle ?? () {},
            onOpen: onOpen ?? () {},
            tooltip: tooltip,
          ),
        ),
      ),
    ),
  ),
);

Color? stripeColor(WidgetTester tester) {
  final stripe = tester.widgetList<Container>(find.byType(Container)).firstWhere((c) {
    final constraints = c.constraints;
    return c.color != null && constraints?.maxWidth == 8;
  });
  return stripe.color;
}

void main() {
  testWidgets('shows the title, the due label with the category name, and the priority', (tester) async {
    await pumpCard(tester);
    expect(find.text('Mark 3A essays'), findsOneWidget);
    expect(find.text('Due tomorrow, 5:00 pm · Teaching'), findsOneWidget);
    expect(find.byType(PriorityBadge), findsOneWidget);
    expect(find.byType(LeafIcon), findsNWidgets(3));
    expect(find.text('High'), findsOneWidget);
  });

  testWidgets('the stripe on the left is the category colour', (tester) async {
    await pumpCard(tester);
    expect(stripeColor(tester), PandaColors.sky);
  });

  testWidgets('with no category it uses a neutral stripe and no category name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPandaTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 480,
            child: TaskCard(task: makeTask(), category: null, now: now, onToggleDone: () {}, onOpen: () {}),
          ),
        ),
      ),
    );
    expect(stripeColor(tester), PandaColors.stone);
    expect(find.text('Due tomorrow, 5:00 pm'), findsOneWidget);
  });

  testWidgets('an overdue task is marked in red with how late it is', (tester) async {
    await pumpCard(tester, task: makeTask(due: DateTime(2026, 10, 7, 23, 59)));
    final meta = tester.widget<Text>(find.text('Overdue by 1 day · Teaching'));
    expect(meta.style!.color, PandaColors.overdue);
    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
  });

  testWidgets('an upcoming task is not red', (tester) async {
    await pumpCard(tester);
    final meta = tester.widget<Text>(find.text('Due tomorrow, 5:00 pm · Teaching'));
    expect(meta.style!.color, PandaColors.muted);
  });

  testWidgets('a finished task is struck through, dimmed, ticked, and never overdue', (tester) async {
    await pumpCard(
      tester,
      task: makeTask(due: DateTime(2026, 10, 1), done: now),
    );
    final title = tester.widget<Text>(find.text('Mark 3A essays'));
    expect(title.style!.decoration, TextDecoration.lineThrough);
    expect(tester.widget<Opacity>(find.byType(Opacity).first).opacity, 0.7);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.textContaining('Overdue'), findsNothing);
  });

  testWidgets('a to-do task has an empty circle and no tick', (tester) async {
    await pumpCard(tester);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
  });

  testWidgets('tapping the circle toggles done without opening the task', (tester) async {
    var toggled = 0, opened = 0;
    await pumpCard(tester, onToggle: () => toggled++, onOpen: () => opened++);
    await tester.tapAt(tester.getCenter(find.byType(AnimatedContainer)));
    expect(toggled, 1);
    expect(opened, 0);
  });

  testWidgets('tapping the card opens the task', (tester) async {
    var toggled = 0, opened = 0;
    await pumpCard(tester, onToggle: () => toggled++, onOpen: () => opened++);
    await tester.tap(find.text('Mark 3A essays'));
    expect(opened, 1);
    expect(toggled, 0);
  });

  testWidgets('the tick box describes itself to screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpCard(tester);
    expect(find.bySemanticsLabel('Mark "Mark 3A essays" as done'), findsOneWidget);
    await pumpCard(tester, task: makeTask(done: now));
    expect(find.bySemanticsLabel('Mark "Mark 3A essays" as not done'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the tick box is a comfortable touch target', (tester) async {
    await pumpCard(tester);
    final box = tester.getSize(find.byWidgetPredicate((w) => w is SizedBox && w.width == 56));
    expect(box.width, greaterThanOrEqualTo(48));
    expect(tester.getSize(find.byType(TaskCard)).height, greaterThanOrEqualTo(48));
  });

  testWidgets('a tooltip explains the rank when one is given', (tester) async {
    await pumpCard(tester, tooltip: 'Due tomorrow · High priority');
    expect(find.byTooltip('Due tomorrow · High priority'), findsOneWidget);
    await pumpCard(tester);
    expect(find.byType(Tooltip), findsNothing);
  });

  group('on a narrow phone', () {
    testWidgets('priority is shown as leaves only and long titles wrap to two lines', (tester) async {
      await pumpCard(tester, width: 340, task: makeTask(title: 'Prepare the Secondary 2 mathematics end of term quiz'));
      expect(find.text('High'), findsNothing);
      expect(find.byType(LeafIcon), findsNWidgets(3));
      final title = tester.widget<Text>(find.textContaining('Prepare the Secondary 2'));
      expect(title.maxLines, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('on a wide card the title stays on one line', (tester) async {
      await pumpCard(tester, width: 480);
      expect(tester.widget<Text>(find.text('Mark 3A essays')).maxLines, 1);
    });
  });

  testWidgets('a very long title is cut off with an ellipsis instead of overflowing', (tester) async {
    await pumpCard(tester, width: 480, task: makeTask(title: 'Word ' * 80));
    expect(tester.takeException(), isNull);
    expect(tester.widget<Text>(find.textContaining('Word Word')).overflow, TextOverflow.ellipsis);
  });
}
