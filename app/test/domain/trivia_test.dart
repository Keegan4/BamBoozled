import 'dart:convert';
import 'dart:io';

import 'package:bamboozled/data/local/app_database.dart';
import 'package:bamboozled/data/trivia/trivia_store.dart';
import 'package:bamboozled/domain/trivia/daily_trivia.dart';
import 'package:bamboozled/domain/trivia/trivia_question.dart';
import 'package:bamboozled/domain/trivia/trivia_run.dart';
import 'package:drift/drift.dart' show DatabaseConnection, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// [n] questions of each difficulty, e.g. "Easy question 3?".
List<TriviaQuestion> fakeBank({int n = 20, Set<TriviaDifficulty> only = const {...TriviaDifficulty.values}}) => [
  for (final d in only)
    for (var i = 1; i <= n; i++)
      TriviaQuestion(
        question: '${d.label} question $i?',
        answer: 'Right ${d.name} $i',
        wrong: ['Wrong ${d.name} $i a', 'Wrong ${d.name} $i b', 'Wrong ${d.name} $i c'],
        category: 'General Knowledge',
        difficulty: d,
      ),
];

TriviaRun runOf(List<(bool correct, int millis)> answers) {
  var run = const TriviaRun(day: 1);
  for (final (correct, ms) in answers) {
    run = run.answer(correct ? 0 : 1, correct: correct, millis: ms);
  }
  return run;
}

void main() {
  group('rules', () {
    test('the timer starts at 15 s and loses 0.8 s a question, down to 5 s', () {
      expect(TriviaRules.timeLimit(1), const Duration(seconds: 15));
      expect(TriviaRules.timeLimit(2), const Duration(milliseconds: 14200));
      expect(TriviaRules.timeLimit(6), const Duration(milliseconds: 11000));
      expect(TriviaRules.timeLimit(13), const Duration(milliseconds: 5400));
      expect(TriviaRules.timeLimit(14), const Duration(seconds: 5));
      expect(TriviaRules.timeLimit(100), const Duration(seconds: 5));
    });

    test('reading time grows with the question, between 1.5 s and 3.5 s', () {
      expect(TriviaRules.readingTime('Hi?'), const Duration(milliseconds: 1500));
      expect(TriviaRules.readingTime('x' * 50), const Duration(milliseconds: 2700));
      expect(TriviaRules.readingTime('x' * 200), const Duration(milliseconds: 3500));
    });

    test('questions 1–5 are easy, 6–12 medium, then hard', () {
      expect([1, 5, 6, 12, 13, 40].map(TriviaRules.difficultyFor), [
        TriviaDifficulty.easy,
        TriviaDifficulty.easy,
        TriviaDifficulty.medium,
        TriviaDifficulty.medium,
        TriviaDifficulty.hard,
        TriviaDifficulty.hard,
      ]);
    });
  });

  group('daily questions', () {
    final bank = fakeBank();

    test('are the same for everyone on the same day, whatever order the bank is in', () {
      final a = DailyTrivia(100, bank), b = DailyTrivia(100, bank.reversed);
      for (var n = 1; n <= 20; n++) {
        expect(a.round(n)!.question.question, b.round(n)!.question.question);
        expect(a.round(n)!.answers, b.round(n)!.answers);
      }
    });

    test('follow the difficulty of each question number', () {
      final t = DailyTrivia(3, bank);
      for (var n = 1; n <= 20; n++) {
        expect(t.round(n)!.question.difficulty, TriviaRules.difficultyFor(n), reason: 'question $n');
      }
    });

    test('mark the right answer among four shuffled ones', () {
      final r = DailyTrivia(7, bank).round(2)!;
      expect(r.answers, hasLength(4));
      expect(r.answers[r.correctIndex], r.question.answer);
      expect(r.answers.toSet(), {r.question.answer, ...r.question.wrong});
    });

    test('change from day to day, with no repeats within a run or across a cycle', () {
      final today = [for (var n = 1; n <= 5; n++) DailyTrivia(10, bank).round(n)!.question.question];
      final tomorrow = [for (var n = 1; n <= 5; n++) DailyTrivia(11, bank).round(n)!.question.question];
      expect(today.toSet().intersection(tomorrow.toSet()), isEmpty);
      expect(today.toSet(), hasLength(5));
      // 20 easy questions, 5 a day: days 0–3 use each exactly once.
      final cycle = [
        for (var d = 0; d < 4; d++)
          for (var n = 1; n <= 5; n++) DailyTrivia(d, bank).round(n)!.question.question,
      ];
      expect(cycle.toSet(), hasLength(20));
    });

    test('borrow from an easier pool, then a harder one, when a difficulty is missing', () {
      final noHard = DailyTrivia(1, fakeBank(only: {TriviaDifficulty.easy, TriviaDifficulty.medium}));
      expect(noHard.round(13)!.question.difficulty, TriviaDifficulty.medium);
      final onlyHard = DailyTrivia(1, fakeBank(only: {TriviaDifficulty.hard}));
      expect(onlyHard.round(1)!.question.difficulty, TriviaDifficulty.hard);
    });

    test('an empty bank has no questions', () {
      final t = DailyTrivia(1, const []);
      expect(t.isEmpty, isTrue);
      expect(t.round(1), isNull);
    });

    test('day numbers count calendar days from 1 January 2026', () {
      expect(DailyTrivia.dayFor(DateTime(2026, 1, 1, 23, 59)), 0);
      expect(DailyTrivia.dayFor(DateTime(2026, 10, 8, 9)), 280);
    });
  });

  group('a run', () {
    test('starts with 2 lives and no score', () {
      const run = TriviaRun(day: 1);
      expect((run.lives, run.score, run.finished, run.started, run.nextNumber), (2, 0, false, false, 1));
    });

    test('loses a life for a wrong answer or running out of time, and ends at 0', () {
      final one = runOf([(true, 3000), (false, 2000)]);
      expect((one.lives, one.score, one.finished), (1, 1, false));
      final over = one.timeout(15000);
      expect((over.lives, over.score, over.finished), (0, 1, true));
      expect(over.answers.last.timedOut, isTrue);
    });

    test('a correct answer within 1 second wins back exactly one life, up to 2', () {
      expect(runOf([(false, 2000), (true, 1000)]).lives, 2);
      expect(runOf([(false, 2000), (true, 1001)]).lives, 1);
      expect(runOf([(true, 200), (true, 300)]).lives, 2);
      expect(runOf([(false, 2000), (false, 2000), (true, 100)]).lives, 0, reason: 'a finished run stays finished');
    });

    test('a fast wrong answer is still wrong', () {
      final run = runOf([(false, 300)]);
      expect(run.answers.single.fast, isFalse);
      expect(run.lives, 1);
    });

    test('remembers a question left with its answers showing', () {
      final run = runOf([(true, 3000)]).showing(2);
      expect(run.leftMidQuestion, isTrue);
      expect(runOf([(true, 3000)]).showing(1).leftMidQuestion, isFalse, reason: 'already answered');
      expect(run.answer(0, correct: true, millis: 900).shown, isNull);
    });

    test('share text has the day, score and a square per question', () {
      final run = runOf([(true, 500), (true, 4000), (false, 2000)]);
      expect(run.squares, '⚡🟩🟥');
      expect(run.shareText, 'BamBoozled Trivia #2 🐼 2 right\n⚡🟩🟥');
    });

    test('round-trips through JSON', () {
      final run = runOf([(true, 500), (false, 2000)]).showing(3);
      final back = TriviaRun.fromJson(jsonDecode(jsonEncode(run.toJson())) as Map<String, dynamic>);
      expect((back.day, back.lives, back.score, back.shown, back.squares), (1, 1, 1, 3, run.squares));
    });
  });

  group('streak and best', () {
    TriviaRun played(int day, int score) => TriviaRun(
      day: day,
      answers: [for (var i = 0; i < score; i++) const TriviaAnswer(chosen: 0, correct: true, millis: 3000)],
    ).timeout(5000);

    test('counts days in a row ending today, or yesterday before today’s run', () {
      final runs = {
        for (final d in [5, 6, 7, 9]) d: played(d, 1),
      };
      expect(triviaStreak(runs, 9), 1);
      expect(triviaStreak(runs, 8), 3);
      expect(triviaStreak(runs, 10), 1);
      expect(triviaStreak(runs, 11), 0);
      expect(triviaStreak({}, 3), 0);
    });

    test('best is the highest score', () {
      expect(triviaBest({1: played(1, 4), 2: played(2, 9), 3: played(3, 2)}), 9);
      expect(triviaBest({}), 0);
    });
  });

  group('storage', () {
    late AppDatabase db;
    setUp(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    });
    tearDown(() => db.close());

    test('saves runs by day and drops ones over 400 days old', () async {
      final store = TriviaStore(db);
      await store.save(const TriviaRun(day: 1).timeout(15000));
      await store.save(const TriviaRun(day: 300).answer(2, correct: true, millis: 800));
      var runs = await store.watch().first;
      expect(runs.keys, [1, 300]);
      expect(runs[300]!.score, 1);
      await store.save(const TriviaRun(day: 401));
      runs = await store.watch().first;
      expect(runs.keys, [300, 401]);
    });

    test('unreadable data reads as no runs', () {
      expect(TriviaStore.decode(null), isEmpty);
      expect(TriviaStore.decode('not json'), isEmpty);
    });
  });

  group('the bundled question bank', () {
    final raw = File('assets/trivia/questions.json').readAsStringSync();
    final bank = [for (final q in jsonDecode(raw) as List) TriviaQuestion.fromJson(q as Map<String, dynamic>)];

    test('every question has one right and three different wrong answers', () {
      for (final q in bank) {
        expect({q.answer, ...q.wrong}, hasLength(4), reason: q.question);
        expect(q.question, isNot(matches(RegExp(r'&[a-z]+;|&#\d+;'))), reason: 'HTML entities left in');
      }
    });

    test('loads through the asset bundle', () async {
      final loaded = await loadTriviaBank(_FileBundle());
      expect(loaded, hasLength(bank.length));
    });

    test('questions survive a JSON round trip', () {
      for (final q in [...bank.take(20), ...fakeBank(n: 1)]) {
        final back = TriviaQuestion.fromJson(q.toJson());
        expect(
          (back.question, back.answer, back.wrong.join('|'), back.difficulty),
          (q.question, q.answer, q.wrong.join('|'), q.difficulty),
        );
      }
      final unknown = TriviaQuestion.fromJson({
        'q': 'Q?',
        'a': 'A',
        'wrong': ['B', 'C', 'D'],
        'diff': 'extreme',
      });
      expect((unknown.difficulty, unknown.category), (TriviaDifficulty.medium, ''));
    });
  });
}

class _FileBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(File(key).readAsBytesSync());
}
