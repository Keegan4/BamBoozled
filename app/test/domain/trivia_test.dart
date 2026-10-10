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
      // 20 easy questions, 5 a try, 2 tries a day: days 0–1 use each exactly once.
      final cycle = [
        for (var d = 0; d < 2; d++)
          for (var attempt = 1; attempt <= 2; attempt++)
            for (var n = 1; n <= 5; n++) DailyTrivia(d, bank, attempt: attempt).round(n)!.question.question,
      ];
      expect(cycle.toSet(), hasLength(20));
    });

    test('the second try has different questions, the same for everyone', () {
      final big = fakeBank(n: 200);
      List<String> run(int day, int attempt) => [
        for (var n = 1; n <= 20; n++) DailyTrivia(day, big, attempt: attempt).round(n)!.question.question,
      ];
      expect(run(5, 2), run(5, 2));
      expect(run(5, 1).take(5).toSet().intersection(run(5, 2).take(5).toSet()), isEmpty);
      expect(run(5, 2).take(5).toSet().intersection(run(6, 1).take(5).toSet()), isEmpty);
      expect(DailyTrivia(5, big).round(1)!.question.question, run(5, 1).first, reason: 'try 1 is the default');
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
    test('starts with 3 lives and no score', () {
      const run = TriviaRun(day: 1);
      expect(
        (run.lives, run.score, run.finished, run.started, run.nextNumber, run.attempt),
        (3, 0, false, false, 1, 1),
      );
    });

    test('loses a life for a wrong answer or running out of time, and ends at 0', () {
      final one = runOf([(true, 3000), (false, 2000), (false, 2000)]);
      expect((one.lives, one.score, one.finished), (1, 1, false));
      final over = one.timeout(15000);
      expect((over.lives, over.score, over.finished), (0, 1, true));
      expect(over.answers.last.timedOut, isTrue);
    });

    test('a correct answer within 1 second wins back exactly one life, up to 3', () {
      expect(runOf([(false, 2000), (true, 1000)]).lives, 3);
      expect(runOf([(false, 2000), (false, 2000), (true, 1000)]).lives, 2);
      expect(runOf([(false, 2000), (true, 1001)]).lives, 2);
      expect(runOf([(true, 200), (true, 300)]).lives, 3);
      expect(
        runOf([(false, 2000), (false, 2000), (false, 2000), (true, 100)]).lives,
        0,
        reason: 'a finished run stays finished',
      );
    });

    test('a fast wrong answer is still wrong', () {
      final run = runOf([(false, 300)]);
      expect(run.answers.single.fast, isFalse);
      expect(run.lives, 2);
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
      expect(run.shareText, 'BamBoozled Trivia #2 (try 1) 🐼 2 right\n⚡🟩🟥');
      expect(const TriviaRun(day: 1, attempt: 2).shareText, startsWith('BamBoozled Trivia #2 (try 2)'));
    });

    test('round-trips through JSON', () {
      final run = TriviaRun(day: 1, attempt: 2).answer(0, correct: true, millis: 500).timeout(9000).showing(3);
      final back = TriviaRun.fromJson(jsonDecode(jsonEncode(run.toJson())) as Map<String, dynamic>);
      expect((back.day, back.attempt, back.lives, back.score, back.shown, back.squares), (1, 2, 2, 1, 3, run.squares));
      final old = TriviaRun.fromJson({'day': 4, 'answers': []});
      expect(old.attempt, 1, reason: 'runs saved before tries existed are try 1');
    });
  });

  group('tries and days', () {
    TriviaRun played(int day, int score, {int attempt = 1}) => TriviaRun(
      day: day,
      attempt: attempt,
      answers: [for (var i = 0; i < score; i++) const TriviaAnswer(chosen: 0, correct: true, millis: 3000)],
    ).timeout(5000).timeout(5000).timeout(5000);

    test('a day offers two tries; its score is the better one', () {
      var day = TriviaDay(7, const []);
      expect((day.started, day.triesLeft, day.best, day.current, day.bestTry), (false, 2, 0, null, null));
      expect(day.next!.attempt, 1);

      final going = played(
        7,
        4,
      ).answers.take(4).fold(const TriviaRun(day: 7), (r, a) => r.answer(0, correct: true, millis: 3000));
      day = day.withRun(going);
      expect(day.current, same(going));
      expect(day.next, same(going));

      day = day.withRun(played(7, 4));
      expect((day.triesLeft, day.best, day.current), (1, 4, null));
      expect(day.next!.attempt, 2);

      day = day.withRun(played(7, 9, attempt: 2));
      expect((day.triesLeft, day.best, day.next), (0, 9, null));
      expect(day.bestTry!.attempt, 2);
      expect(day.tries.map((r) => r.attempt), [1, 2]);
    });

    test('a tie keeps the earlier try as the best', () {
      final day = TriviaDay(1, [played(1, 5, attempt: 2), played(1, 5)]);
      expect(day.bestTry!.attempt, 1);
    });

    test('streak counts days with a try, ending today or yesterday', () {
      final days = {
        for (final d in [5, 6, 7, 9]) d: TriviaDay(d, [played(d, 1)]),
      };
      expect(triviaStreak(days, 9), 1);
      expect(triviaStreak(days, 8), 3);
      expect(triviaStreak(days, 10), 1);
      expect(triviaStreak(days, 11), 0);
      expect(triviaStreak({}, 3), 0);
    });

    test('best is the best day, using each day’s better try', () {
      final days = {
        1: TriviaDay(1, [played(1, 4), played(1, 11, attempt: 2)]),
        2: TriviaDay(2, [played(2, 9)]),
      };
      expect(triviaBest(days), 11);
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
      await store.save(const TriviaRun(day: 300).answer(2, correct: true, millis: 800).timeout(5000));
      await store.save(const TriviaRun(day: 300, attempt: 2).answer(1, correct: false, millis: 800));
      var days = await store.watch().first;
      expect(days.keys, [1, 300]);
      expect(days[300]!.tries.map((r) => (r.attempt, r.answers.length)), [(1, 2), (2, 1)]);
      expect(days[300]!.best, 1);
      await store.save(const TriviaRun(day: 401));
      days = await store.watch().first;
      expect(days.keys, [300, 401]);
    });

    test('unreadable data reads as no runs', () {
      expect(TriviaStore.decode(null), isEmpty);
      expect(TriviaStore.decode('not json'), isEmpty);
    });
  });

  group('the bundled question bank', () {
    final raw = File('assets/trivia/questions.json').readAsStringSync();
    final bank = [for (final q in jsonDecode(raw) as List) TriviaQuestion.fromJson(q as Map<String, dynamic>)];

    test('has plenty of questions of every difficulty', () {
      expect(bank.length, greaterThanOrEqualTo(1500));
      for (final d in TriviaDifficulty.values) {
        expect(bank.where((q) => q.difficulty == d).length, greaterThanOrEqualTo(200), reason: d.name);
      }
    });

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
