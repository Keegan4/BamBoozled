import 'dart:math' as math;

import 'daily_trivia.dart';

/// What happened on one question.
class TriviaAnswer {
  const TriviaAnswer({required this.chosen, required this.correct, required this.millis});

  /// The answer picked (in the order shown), or null if time ran out.
  final int? chosen;
  final bool correct;

  /// Time from the answers appearing to the tap.
  final int millis;

  bool get timedOut => chosen == null;

  /// Right, and within [TriviaRules.fastAnswer]: wins back a life.
  bool get fast => correct && millis <= TriviaRules.fastAnswer.inMilliseconds;

  Map<String, dynamic> toJson() => {'c': chosen, 'ok': correct, 'ms': millis};

  factory TriviaAnswer.fromJson(Map<String, dynamic> j) =>
      TriviaAnswer(chosen: j['c'] as int?, correct: j['ok'] as bool, millis: j['ms'] as int);
}

/// A day's run so far. Lives and score are worked out from the answers, so they can't disagree.
class TriviaRun {
  const TriviaRun({required this.day, this.answers = const [], this.shown});

  final int day;
  final List<TriviaAnswer> answers;

  /// The question whose answers are on screen but not answered yet. If the app is left at that
  /// point, the question counts as missed when the run is picked up again, so leaving can't be used
  /// to skip a question.
  final int? shown;

  /// Lives left: start with [TriviaRules.maxLives]; a miss loses one, a fast correct answer wins one back.
  int get lives {
    var lives = TriviaRules.maxLives;
    for (final a in answers) {
      if (!a.correct) {
        lives--;
      } else if (a.fast) {
        lives = math.min(lives + 1, TriviaRules.maxLives);
      }
      if (lives <= 0) return 0;
    }
    return lives;
  }

  /// Questions answered correctly.
  int get score => answers.where((a) => a.correct).length;

  bool get finished => lives == 0;
  bool get started => answers.isNotEmpty || shown != null;

  /// The number of the question to ask next (1-based).
  int get nextNumber => answers.length + 1;

  /// True when a question was left with its answers showing (see [shown]).
  bool get leftMidQuestion => shown != null && shown == nextNumber && !finished;

  TriviaRun showing(int number) => TriviaRun(day: day, answers: answers, shown: number);

  TriviaRun answer(int chosen, {required bool correct, required int millis}) => TriviaRun(
    day: day,
    answers: [
      ...answers,
      TriviaAnswer(chosen: chosen, correct: correct, millis: millis),
    ],
  );

  TriviaRun timeout(int millis) => TriviaRun(
    day: day,
    answers: [
      ...answers,
      TriviaAnswer(chosen: null, correct: false, millis: millis),
    ],
  );

  /// One square per question: 🟩 right, ⚡ right and fast (a life back), 🟥 wrong or too slow.
  String get squares => answers.map((a) => a.fast ? '⚡' : (a.correct ? '🟩' : '🟥')).join();

  /// Text to paste into a chat, e.g. "BamBoozled Trivia #282 🐼 14 right\n🟩🟩⚡🟥…".
  String get shareText => 'BamBoozled Trivia #${day + 1} 🐼 $score right\n$squares';

  Map<String, dynamic> toJson() => {
    'day': day,
    'answers': [for (final a in answers) a.toJson()],
    'shown': shown,
  };

  factory TriviaRun.fromJson(Map<String, dynamic> j) => TriviaRun(
    day: j['day'] as int,
    answers: [for (final a in j['answers'] as List) TriviaAnswer.fromJson(a as Map<String, dynamic>)],
    shown: j['shown'] as int?,
  );
}

/// Days in a row with a finished or started run, ending today or yesterday (so the streak doesn't
/// look broken before today's run).
int triviaStreak(Map<int, TriviaRun> runs, int today) {
  var day = runs[today]?.started ?? false ? today : today - 1;
  var streak = 0;
  while (runs[day]?.started ?? false) {
    streak++;
    day--;
  }
  return streak;
}

/// The best score of any day, or 0.
int triviaBest(Map<int, TriviaRun> runs) => runs.values.fold(0, (best, r) => math.max(best, r.score));
