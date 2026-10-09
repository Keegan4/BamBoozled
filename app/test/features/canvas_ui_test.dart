import 'package:bamboozled/data/canvas/canvas_feed.dart';
import 'package:bamboozled/data/providers.dart';
import 'package:bamboozled/data/repositories/task_repository.dart';
import 'package:bamboozled/features/settings/canvas_card.dart';
import 'package:bamboozled/features/tasks/task_editor.dart';
import 'package:bamboozled/features/tasks/widgets/open_link.dart';
import 'package:bamboozled/features/tasks/widgets/task_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../canvas_samples.dart';
import '../helpers.dart';

const tall = Size(1440, 2000);
const link = 'https://canvas.nus.edu.sg/feeds/calendars/user_x.ics';

void main() {
  late List<Uri> fetched;
  late List<Uri> opened;
  late String body;
  Object? failure;

  setUp(() {
    fetched = [];
    opened = [];
    body = sampleFeed;
    failure = null;
  });

  final overrides = [
    canvasFetcherProvider.overrideWithValue((uri) async {
      fetched.add(uri);
      if (failure != null) throw failure!;
      return body;
    }),
    linkOpenerProvider.overrideWithValue((uri) async {
      opened.add(uri);
      return true;
    }),
  ];

  Finder inCard(Finder f) => find.descendant(of: find.byType(CanvasCard), matching: f);
  Finder inDialog(Finder f) => find.descendant(of: find.byType(ConnectCanvasDialog), matching: f);

  Future<TestApp> openSettings(WidgetTester tester, {bool withSampleTasks = false}) async {
    final app = await TestApp.create(withSampleTasks: withSampleTasks);
    await app.pump(tester, size: tall, location: '/settings', overrides: overrides);
    await TestApp.settle(tester);
    return app;
  }

  Future<void> connect(WidgetTester tester, [String pasted = link]) async {
    await tester.tap(inCard(find.text('Connect Canvas')));
    await TestApp.settle(tester);
    await tester.enterText(inDialog(find.byType(TextField)), pasted);
    await tester.tap(inDialog(find.widgetWithText(FilledButton, 'Connect')));
    await TestApp.settle(tester);
  }

  group('Settings → Canvas', () {
    testWidgets('explains what it does and offers to connect', (tester) async {
      final app = await openSettings(tester);
      expect(inCard(find.text('Canvas')), findsOneWidget);
      expect(inCard(find.textContaining('Canvas assignments')), findsOneWidget);
      expect(inCard(find.text('Connect Canvas')), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the dialog says where to find the link and to keep it private', (tester) async {
      final app = await openSettings(tester);
      await tester.tap(inCard(find.text('Connect Canvas')));
      await TestApp.settle(tester);
      expect(inDialog(find.textContaining('Calendar Feed')), findsOneWidget);
      expect(inDialog(find.textContaining('Keep this link private')), findsOneWidget);
      await tester.tap(inDialog(find.text('Cancel')));
      await TestApp.settle(tester);
      expect(find.byType(ConnectCanvasDialog), findsNothing);
      expect(fetched, isEmpty);
      await app.dispose(tester);
    });

    testWidgets('pasting the link imports the assignments and shows them as connected', (tester) async {
      final app = await openSettings(tester);
      await connect(tester);
      expect(fetched.single.toString(), link, reason: 'read once: no second download straight after connecting');
      expect(find.byType(ConnectCanvasDialog), findsNothing);
      expect(find.text('Connected! Found 2 assignments.'), findsOneWidget);
      expect(inCard(find.text('Connected to canvas.nus.edu.sg')), findsOneWidget);
      expect(inCard(find.textContaining('2 assignments · checks every hour')), findsOneWidget);
      final tasks = await tester.runAsync(() => app.repo.watchTasks().first);
      expect(tasks!.map((t) => t.title), ['Essay 2', 'Problem set 3, part A']);
      await app.dispose(tester);
    });

    testWidgets('a bad link explains and keeps the dialog open to try again', (tester) async {
      final app = await openSettings(tester);
      await connect(tester, 'not a link');
      expect(inDialog(find.textContaining('doesn’t look like a link')), findsOneWidget);
      expect(fetched, isEmpty);

      failure = const CanvasFeedException('Canvas didn’t recognise that link.');
      await tester.enterText(inDialog(find.byType(TextField)), link);
      await tester.tap(inDialog(find.widgetWithText(FilledButton, 'Connect')));
      await TestApp.settle(tester);
      expect(inDialog(find.text('Canvas didn’t recognise that link.')), findsOneWidget);

      failure = null;
      await tester.tap(inDialog(find.widgetWithText(FilledButton, 'Connect')));
      await TestApp.settle(tester);
      expect(find.byType(ConnectCanvasDialog), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('an unexpected error still gives a friendly message', (tester) async {
      final app = await openSettings(tester);
      failure = StateError('boom');
      await connect(tester);
      expect(inDialog(find.text('Something went wrong. Please try again.')), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('an empty feed connects and says there is nothing yet', (tester) async {
      body = feed([]);
      final app = await openSettings(tester);
      await connect(tester);
      expect(find.text('Connected. Canvas has no assignments to show yet.'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('"Update now" reads the feed again and says what changed', (tester) async {
      final app = await openSettings(tester);
      await connect(tester);
      fetched.clear();
      body = feed([vevent(uid: 'event-assignment-101', summary: 'Essay 2 (extended) [EN1101E Academic Writing]')]);
      await tester.tap(inCard(find.text('Update now')));
      await TestApp.settle(tester);
      expect(fetched, isNotEmpty);
      expect(find.text('Canvas updated: 1 changed, 1 removed'), findsOneWidget);
      await tester.tap(inCard(find.text('Update now')));
      await TestApp.settle(tester);
      expect(find.text('Canvas is up to date'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('a failed update is shown in red on the card', (tester) async {
      final app = await openSettings(tester);
      await connect(tester);
      failure = const CanvasFeedException('We couldn’t reach Canvas.');
      await tester.tap(inCard(find.text('Update now')));
      await TestApp.settle(tester);
      expect(inCard(find.text('We couldn’t reach Canvas.')), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('Disconnect asks first, then removes the Canvas tasks', (tester) async {
      final app = await openSettings(tester);
      await connect(tester);
      await tester.tap(inCard(find.text('Disconnect')));
      await TestApp.settle(tester);
      expect(find.text('Disconnect Canvas?'), findsOneWidget);
      await tester.tap(find.text('Keep connected'));
      await TestApp.settle(tester);
      expect(inCard(find.text('Connected to canvas.nus.edu.sg')), findsOneWidget);

      await tester.tap(inCard(find.text('Disconnect')));
      await TestApp.settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Disconnect'));
      await TestApp.settle(tester);
      expect(find.text('Canvas disconnected'), findsOneWidget);
      expect(inCard(find.text('Connect Canvas')), findsOneWidget);
      expect(await tester.runAsync(() => app.repo.watchTasks().first), isEmpty);
      await app.dispose(tester);
    });

    testWidgets('when connected, the app reads the feed as it opens', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await tester.runAsync(() => app.db.setSetting('canvas', '{"url":"$link","count":0}'));
      await app.pump(tester, size: tall, overrides: overrides);
      await TestApp.settle(tester);
      expect(fetched.single.toString(), link);
      expect(doNextTitles(tester), contains('Essay 2'));
      await app.dispose(tester);
    });
  });

  group('Canvas assignments in the app', () {
    Future<TestApp> withAssignments(WidgetTester tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await tester.runAsync(() => app.repo.applyCanvasItems(parseCanvasFeed(sampleFeed)));
      await app.pump(tester, size: tall, overrides: overrides);
      await TestApp.settle(tester);
      return app;
    }

    testWidgets('appear in Do next with a Canvas label and their course', (tester) async {
      final app = await withAssignments(tester);
      expect(doNextTitles(tester), ['Essay 2', 'Problem set 3, part A']);
      expect(
        find.descendant(of: cardFor('Essay 2'), matching: find.textContaining('EN1101E Academic Writing · Canvas')),
        findsOneWidget,
      );
      await app.dispose(tester);
    });

    testWidgets('the editor shows them as from Canvas, with no title, date or repeat boxes', (tester) async {
      final app = await withAssignments(tester);
      await tester.tap(find.descendant(of: cardFor('Essay 2'), matching: find.text('Essay 2')));
      await TestApp.settle(tester);
      expect(find.byKey(const ValueKey('from-canvas')), findsOneWidget);
      expect(find.text('What needs doing?'), findsNothing);
      expect(find.text('When is it due?'), findsNothing);
      expect(find.text('Repeat'), findsNothing);
      expect(find.text('How important is it?'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('"Open in Canvas" opens the assignment page', (tester) async {
      final app = await withAssignments(tester);
      await tester.tap(find.descendant(of: cardFor('Essay 2'), matching: find.text('Essay 2')));
      await TestApp.settle(tester);
      await tester.tap(find.text('Open in Canvas'));
      await TestApp.settle(tester);
      expect(opened.single.toString(), 'https://canvas.nus.edu.sg/courses/55/assignments/101');
      await app.dispose(tester);
    });

    testWidgets('if the browser cannot open, it says so', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await tester.runAsync(() => app.repo.applyCanvasItems(parseCanvasFeed(sampleFeed)));
      await app.pump(
        tester,
        size: tall,
        overrides: [linkOpenerProvider.overrideWithValue((uri) async => throw Exception('no browser'))],
      );
      await TestApp.settle(tester);
      await tester.tap(find.descendant(of: cardFor('Essay 2'), matching: find.text('Essay 2')));
      await TestApp.settle(tester);
      await tester.tap(find.text('Open in Canvas'));
      await TestApp.settle(tester);
      expect(find.textContaining('Couldn’t open the link'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('saving keeps Canvas’s title and due date and saves your priority', (tester) async {
      final app = await withAssignments(tester);
      await tester.tap(find.descendant(of: cardFor('Essay 2'), matching: find.text('Essay 2')));
      await TestApp.settle(tester);
      await tester.tap(find.descendant(of: find.byType(TaskEditor), matching: find.text('Urgent')));
      await tester.tap(find.text('Save changes'));
      await TestApp.settle(tester);
      final t = await tester.runAsync(() => app.repo.getTask(TaskRepository.canvasTaskId('event-assignment-101')));
      expect(t!.title, 'Essay 2');
      expect(t.dueAt, DateTime.utc(2026, 10, 15, 15, 59).toLocal());
      expect(t.priority.label, 'Urgent');
      await app.dispose(tester);
    });

    testWidgets('your own tasks still have the normal editor', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: tall, overrides: overrides);
      await tester.tap(find.descendant(of: cardFor('Mark 3A essays'), matching: find.text('Mark 3A essays')));
      await TestApp.settle(tester);
      expect(find.byKey(const ValueKey('from-canvas')), findsNothing);
      expect(find.text('What needs doing?'), findsOneWidget);
      expect(find.descendant(of: find.byType(TaskCard), matching: find.textContaining('Canvas')), findsNothing);
      await app.dispose(tester);
    });
  });
}
