import 'package:bamboozled/core/theme/appearance.dart';
import 'package:bamboozled/data/providers.dart';
import 'package:bamboozled/data/trivia/trivia_store.dart';
import 'package:bamboozled/domain/trivia/daily_trivia.dart';
import 'package:bamboozled/domain/trivia/trivia_run.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/trivia_test.dart' show fakeBank;
import '../helpers.dart';

final today = DailyTrivia.dayFor(testNow);

Future<TestApp> openPlay(WidgetTester tester, {bool emptyBank = false, Size size = const Size(1440, 1000)}) async {
  final app = await TestApp.create();
  await app.pump(
    tester,
    size: size,
    location: '/play',
    overrides: [triviaBankProvider.overrideWith((ref) async => emptyBank ? [] : fakeBank())],
  );
  return app;
}

/// Taps Start (or Continue) and waits through the reading time until the answers show.
Future<void> startAndRead(WidgetTester tester) async {
  await tester.tap(find.byType(FilledButton));
  await tester.pump();
  await nextAnswers(tester);
}

Future<void> nextAnswers(WidgetTester tester) async {
  expect(find.text('Get ready…'), findsOneWidget);
  await tester.pump(const Duration(milliseconds: 3600)); // longer than any reading time
  expect(find.text('Get ready…'), findsNothing);
}

/// Answers after [after], right or wrong, then lets the result show and moves on.
Future<void> answer(WidgetTester tester, {required bool right, Duration after = const Duration(seconds: 3)}) async {
  await tester.pump(after);
  await tester.tap(find.textContaining(right ? 'Right ' : 'Wrong ').first);
  await tester.pump();
}

Future<void> next(WidgetTester tester) => tester.pump(TriviaRules.revealPause + const Duration(milliseconds: 50));

int lives(WidgetTester tester) =>
    find.byKey(const ValueKey('life-0-full')).evaluate().length +
    find.byKey(const ValueKey('life-1-full')).evaluate().length;

Future<Map<int, TriviaRun>> stored(WidgetTester tester, TestApp app) async =>
    TriviaStore.decode(await tester.runAsync<String?>(() => app.db.getSetting(TriviaStore.key)));

void main() {
  testWidgets('the start card explains the rules', (tester) async {
    final app = await openPlay(tester);
    expect(find.text('Bamboo Trivia'), findsOneWidget);
    expect(find.textContaining('2 lives'), findsOneWidget);
    expect(find.textContaining('within 1 second'), findsOneWidget);
    expect(find.text('Streak: 0 days'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.textContaining('Open Trivia DB'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('the question shows alone first, then the answers and the timer', (tester) async {
    final app = await openPlay(tester);
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(find.text('Question 1 · Easy'), findsOneWidget);
    expect(find.byKey(const ValueKey('trivia-question')), findsOneWidget);
    expect(find.textContaining('Right '), findsNothing);
    await nextAnswers(tester);
    expect(find.textContaining('Right '), findsOneWidget);
    expect(find.textContaining('Wrong '), findsNWidgets(3));
    expect(lives(tester), 2);
    await app.dispose(tester);
  });

  testWidgets('a right answer scores, a wrong one costs a life and shows the right answer', (tester) async {
    final app = await openPlay(tester);
    await startAndRead(tester);
    await answer(tester, right: true);
    expect(find.text('Correct!'), findsOneWidget);
    expect(find.text('Score 1'), findsOneWidget);
    await next(tester);
    await nextAnswers(tester);
    expect(find.text('Question 2 · Easy'), findsOneWidget);
    await answer(tester, right: false);
    expect(find.text('Not quite'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Right .*, correct answer$')), findsOneWidget);
    expect(lives(tester), 1);
    expect(find.text('Score 1'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('a right answer within a second wins back a life', (tester) async {
    final app = await openPlay(tester);
    await startAndRead(tester);
    await answer(tester, right: true, after: const Duration(milliseconds: 500));
    expect(find.text('⚡ Lightning fast!'), findsOneWidget, reason: 'no life to win back yet');
    await next(tester);
    await nextAnswers(tester);
    await answer(tester, right: false);
    expect(lives(tester), 1);
    await next(tester);
    await nextAnswers(tester);
    await answer(tester, right: true, after: const Duration(milliseconds: 1500));
    expect(lives(tester), 1, reason: '1.5 s is too slow');
    await next(tester);
    await nextAnswers(tester);
    await answer(tester, right: true, after: const Duration(milliseconds: 800));
    expect(find.text('⚡ Lightning fast! +1 life'), findsOneWidget);
    expect(lives(tester), 2);
    await app.dispose(tester);
  });

  testWidgets('running out of time costs a life; Next skips the pause', (tester) async {
    final app = await openPlay(tester);
    await startAndRead(tester);
    await tester.pump(TriviaRules.timeLimit(1));
    await tester.pump();
    expect(find.text('Out of time'), findsOneWidget);
    expect(lives(tester), 1);
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Question 2 · Easy'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('two misses end the run; it can’t be played again today', (tester) async {
    final app = await openPlay(tester);
    await startAndRead(tester);
    await answer(tester, right: true);
    await next(tester);
    await nextAnswers(tester);
    await answer(tester, right: false);
    await next(tester);
    await nextAnswers(tester);
    await answer(tester, right: false);
    expect(find.text('See result'), findsOneWidget);
    await next(tester);
    await TestApp.settle(tester);
    expect(find.text('You got 1 right'), findsOneWidget);
    expect(find.text('Start'), findsNothing);
    expect(find.byTooltip('Question 3: wrong'), findsOneWidget);

    final runs = await stored(tester, app);
    expect(runs[today]!.squares, '🟩🟥🟥');

    // Leave and come back: still finished.
    await tester.tap(find.text('Home').first);
    await TestApp.settle(tester);
    await tester.tap(find.text('Play').first);
    await TestApp.settle(tester);
    expect(find.text('You got 1 right'), findsOneWidget);
    expect(find.text('Streak: 1 day'), findsOneWidget);
    expect(find.text('Best: 1'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('Copy result puts the share text on the clipboard', (tester) async {
    final app = await TestApp.create();
    await app.db.setSetting(
      TriviaStore.key,
      '[${'{"day":$today,"answers":[{"c":0,"ok":true,"ms":500},{"c":1,"ok":false,"ms":900},{"c":null,"ok":false,"ms":15000}]}'}]',
    );
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await app.pump(tester, location: '/play', overrides: [triviaBankProvider.overrideWith((ref) async => fakeBank())]);
    expect(find.byTooltip('Question 1: right, fast'), findsOneWidget);
    expect(find.byTooltip('Question 3: out of time'), findsOneWidget);
    await tester.tap(find.text('Copy result'));
    await TestApp.settle(tester);
    expect(copied, 'BamBoozled Trivia #${today + 1} 🐼 1 right\n⚡🟥🟥');
    expect(find.text('Result copied'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('leaving with the answers showing counts that question as missed', (tester) async {
    final app = await openPlay(tester);
    await startAndRead(tester);
    await TestApp.settle(tester); // let the "answers showing" note save
    await tester.tap(find.text('Home').first);
    await TestApp.settle(tester);
    await tester.tap(find.text('Play').first);
    await TestApp.settle(tester);
    expect(find.text('Continue (question 1)'), findsOneWidget);
    await tester.tap(find.text('Continue (question 1)'));
    await TestApp.settle(tester);
    expect(find.text('Question 2 · Easy'), findsOneWidget);
    expect(lives(tester), 1);
    await app.dispose(tester);
  });

  testWidgets('leaving twice with answers showing ends the run', (tester) async {
    final app = await TestApp.create();
    await app.db.setSetting(TriviaStore.key, '[{"day":$today,"answers":[{"c":1,"ok":false,"ms":900}],"shown":2}]');
    await app.pump(tester, location: '/play', overrides: [triviaBankProvider.overrideWith((ref) async => fakeBank())]);
    await tester.tap(find.text('Continue (question 2)'));
    await TestApp.settle(tester);
    expect(find.text('You got 0 right'), findsOneWidget);
    expect(find.text('The question you left half-way counted as missed.'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('with no questions it says so', (tester) async {
    final app = await openPlay(tester, emptyBank: true);
    expect(find.text('Questions are on their way'), findsOneWidget);
    expect(find.text('Start'), findsNothing);
    await app.dispose(tester);
  });

  testWidgets('plays on a phone in dark mode', (tester) async {
    final app = await TestApp.create();
    await app.db.setSetting(Appearance.key, 'dark;19:00;07:00');
    await app.pump(
      tester,
      size: const Size(412, 915),
      location: '/play',
      overrides: [triviaBankProvider.overrideWith((ref) async => fakeBank())],
    );
    expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('Play')), findsOneWidget);
    await startAndRead(tester);
    await answer(tester, right: true);
    expect(tester.takeException(), isNull);
    expect(Theme.of(tester.element(find.text('Correct!'))).brightness, Brightness.dark);
    await app.dispose(tester);
  });
}
