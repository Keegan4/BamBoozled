import 'dart:math' as math;

import '../services/daily_note_picker.dart';
import '../services/stable_random.dart';
import 'trivia_question.dart';

/// The rules of the daily trivia run, in one place so they're easy to tune. See docs/trivia.md.
abstract final class TriviaRules {
  /// Lives at the start, and the most you can have.
  static const maxLives = 3;

  /// Tries each day. Each try has its own questions; the better score counts.
  static const triesPerDay = 2;

  /// A correct answer this quick (after the answers appear) wins back a life.
  static const fastAnswer = Duration(seconds: 1);

  /// How long the result of an answer stays on screen before the next question.
  static const revealPause = Duration(milliseconds: 1200);

  /// How long a question is shown on its own before the answers appear: longer for longer questions.
  static Duration readingTime(String question) =>
      Duration(milliseconds: (1200 + 30 * question.length).clamp(1500, 3500));

  /// Time to answer question [number] (1-based): 15 s, then 0.8 s less each question, never under 5 s.
  static Duration timeLimit(int number) => Duration(milliseconds: math.max(15000 - 800 * (number - 1), 5000));

  /// Questions 1–5 are easy, 6–12 medium, then hard.
  static TriviaDifficulty difficultyFor(int number) => number <= 5
      ? TriviaDifficulty.easy
      : number <= 12
      ? TriviaDifficulty.medium
      : TriviaDifficulty.hard;
}

/// One try's questions: the same questions, in the same order with the same answer order, for
/// everyone on that day and try.
///
/// Each difficulty has its own pool, shuffled with [StableRandom] (so phones, computers and the
/// browser agree). Every try gets its own slot, `day × triesPerDay + (attempt − 1)`, and slot s takes
/// its easy questions from position s × 5 of the easy pool, medium from s × 7 and hard from s × 8:
/// just enough for a typical run. So the two tries of a day never share questions, each day carries
/// on from the last, and a pool is only reshuffled once it has been used up (with ~3,900 questions,
/// after roughly three months).
class DailyTrivia {
  DailyTrivia(this.day, Iterable<TriviaQuestion> bank, {this.attempt = 1})
    : _pools = {
        for (final d in TriviaDifficulty.values)
          d: [
            for (final q in bank)
              if (q.difficulty == d) q,
          ]..sort((a, b) => a.question.compareTo(b.question)),
      };

  /// Days since 1 January 2026 ([DailyNotePicker.dayIndex]).
  final int day;

  /// 1 for the day's first try, 2 for the second.
  final int attempt;
  final Map<TriviaDifficulty, List<TriviaQuestion>> _pools;

  int get _slot => day * TriviaRules.triesPerDay + (attempt - 1);

  static const _perDay = {TriviaDifficulty.easy: 5, TriviaDifficulty.medium: 7, TriviaDifficulty.hard: 8};

  static int dayFor(DateTime date) => DailyNotePicker.dayIndex(date);

  bool get isEmpty => _pools.values.every((p) => p.isEmpty);

  /// Question [number] (1-based) of today's run, or null if the bank is empty.
  TriviaRound? round(int number) {
    final wanted = TriviaRules.difficultyFor(number);
    final difficulty = _fallback(wanted);
    if (difficulty == null) return null;
    final pool = _pools[difficulty]!;
    // Position within today's slice of this difficulty.
    final firstOfBand = switch (wanted) {
      TriviaDifficulty.easy => 1,
      TriviaDifficulty.medium => 6,
      TriviaDifficulty.hard => 13,
    };
    final index = _slot * _perDay[wanted]! + (number - firstOfBand);
    final position = index % pool.length;
    final cycle = (index - position) ~/ pool.length;
    final question = StableRandom('trivia#${difficulty.name}#$cycle').shuffled(pool)[position];
    final answers = StableRandom('trivia-answers#$day#$attempt#$number').shuffled([question.answer, ...question.wrong]);
    return TriviaRound(
      number: number,
      question: question,
      answers: answers,
      correctIndex: answers.indexOf(question.answer),
    );
  }

  /// [wanted] if it has questions, otherwise the nearest easier one, otherwise the nearest harder one.
  TriviaDifficulty? _fallback(TriviaDifficulty wanted) {
    final order = [
      for (var i = wanted.index; i >= 0; i--) TriviaDifficulty.values[i],
      for (var i = wanted.index + 1; i < TriviaDifficulty.values.length; i++) TriviaDifficulty.values[i],
    ];
    for (final d in order) {
      if (_pools[d]!.isNotEmpty) return d;
    }
    return null;
  }
}
