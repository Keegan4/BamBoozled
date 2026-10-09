/// How hard a question is, as rated by Open Trivia DB.
enum TriviaDifficulty {
  easy('Easy'),
  medium('Medium'),
  hard('Hard');

  const TriviaDifficulty(this.label);
  final String label;
}

/// One multiple-choice question from the bundled bank (`assets/trivia/questions.json`).
class TriviaQuestion {
  const TriviaQuestion({
    required this.question,
    required this.answer,
    required this.wrong,
    required this.category,
    required this.difficulty,
  });

  final String question;
  final String answer;

  /// The three wrong answers.
  final List<String> wrong;
  final String category;
  final TriviaDifficulty difficulty;

  factory TriviaQuestion.fromJson(Map<String, dynamic> j) => TriviaQuestion(
    question: j['q'] as String,
    answer: j['a'] as String,
    wrong: [for (final w in j['wrong'] as List) w as String],
    category: j['cat'] as String? ?? '',
    difficulty: TriviaDifficulty.values.asNameMap()[j['diff']] ?? TriviaDifficulty.medium,
  );

  Map<String, dynamic> toJson() => {
    'q': question,
    'a': answer,
    'wrong': wrong,
    'cat': category,
    'diff': difficulty.name,
  };
}

/// A question as asked: its answers in the order shown, and which one is right.
class TriviaRound {
  const TriviaRound({required this.number, required this.question, required this.answers, required this.correctIndex});

  /// 1 for the first question of the run.
  final int number;
  final TriviaQuestion question;
  final List<String> answers;
  final int correctIndex;
}
