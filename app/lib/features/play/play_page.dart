import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/panda_theme.dart';
import '../../core/widgets/panda_mascot.dart';
import '../../core/widgets/pills.dart';
import '../../data/providers.dart';
import '../../domain/trivia/daily_trivia.dart';
import '../../domain/trivia/trivia_question.dart';
import '../../domain/trivia/trivia_run.dart';

/// Credit required by the CC BY-SA licence of the questions.
const triviaCredit = 'Questions from Open Trivia DB (opentdb.com), CC BY-SA 4.0';

enum _Phase { reading, answering, reveal }

/// The Play tab: one daily trivia run. Two lives; questions get harder and the timer shorter; a
/// correct answer within a second wins a life back. The score is how many were answered correctly.
class PlayPage extends ConsumerStatefulWidget {
  const PlayPage({super.key});

  @override
  ConsumerState<PlayPage> createState() => _PlayPageState();
}

class _PlayPageState extends ConsumerState<PlayPage> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);

  /// Fraction for the bar on screen: the "get ready" bar while reading, then the time left.
  final _bar = ValueNotifier<double>(0);

  Duration _elapsed = Duration.zero;
  Duration _phaseStart = Duration.zero;
  _Phase _phase = _Phase.reading;
  DailyTrivia? _trivia;
  TriviaRun? _run; // non-null while playing
  TriviaRound? _round;
  int? _chosen;

  /// Shown on the start or game-over card when a question left half-way was counted as missed.
  bool _leftCounted = false;

  @override
  void dispose() {
    _ticker.dispose();
    _bar.dispose();
    super.dispose();
  }

  Duration get _sincePhase => _elapsed - _phaseStart;

  void _tick(Duration elapsed) {
    _elapsed = elapsed;
    final round = _round;
    if (round == null) return;
    switch (_phase) {
      case _Phase.reading:
        final read = TriviaRules.readingTime(round.question.question);
        _bar.value = (_sincePhase.inMicroseconds / read.inMicroseconds).clamp(0.0, 1.0);
        if (_sincePhase >= read) _showAnswers();
      case _Phase.answering:
        final limit = TriviaRules.timeLimit(round.number);
        _bar.value = (1 - _sincePhase.inMicroseconds / limit.inMicroseconds).clamp(0.0, 1.0);
        if (_sincePhase >= limit) _timeout();
      case _Phase.reveal:
        if (_sincePhase >= TriviaRules.revealPause) _next();
    }
  }

  void _setPhase(_Phase phase) => setState(() {
    _phase = phase;
    _phaseStart = _elapsed;
  });

  Future<void> _save(TriviaRun run) {
    _run = run;
    return ref.read(triviaStoreProvider).save(run);
  }

  Future<void> _start(int day, List<TriviaQuestion> bank, TriviaRun saved) async {
    var run = saved;
    if (run.leftMidQuestion) {
      run = run.timeout(TriviaRules.timeLimit(run.nextNumber).inMilliseconds);
      await _save(run);
      setState(() => _leftCounted = true);
      if (run.finished) {
        setState(() => _run = null);
        return;
      }
    }
    _trivia = DailyTrivia(day, bank, attempt: run.attempt);
    _run = run;
    if (!_ticker.isActive) {
      // A restarted ticker counts from zero again, so the clock the phases are measured on must too.
      _elapsed = Duration.zero;
      _ticker.start();
    }
    _ask(run.nextNumber);
  }

  void _ask(int number) {
    final round = _trivia!.round(number);
    _round = round;
    _chosen = null;
    _bar.value = 0;
    _setPhase(_Phase.reading);
  }

  void _showAnswers() {
    _bar.value = 1;
    _setPhase(_Phase.answering);
    _save(_run!.showing(_round!.number));
  }

  void _answer(int index) {
    if (_phase != _Phase.answering) return;
    final round = _round!;
    final millis = _sincePhase.inMilliseconds;
    _chosen = index;
    _save(_run!.answer(index, correct: index == round.correctIndex, millis: millis));
    _setPhase(_Phase.reveal);
  }

  void _timeout() {
    _chosen = null;
    _save(_run!.timeout(TriviaRules.timeLimit(_round!.number).inMilliseconds));
    _setPhase(_Phase.reveal);
  }

  void _next() {
    final run = _run!;
    if (run.finished) {
      _ticker.stop();
      setState(() {
        _run = null;
        _round = null;
      });
    } else {
      _ask(run.nextNumber);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = Breakpoints.isPhone(context);
    final trivia = ref.watch(todayTriviaProvider);
    final days = ref.watch(triviaRunsProvider).value ?? const <int, TriviaDay>{};
    final day = ref.watch(triviaDayProvider);
    final today = days[day] ?? TriviaDay(day, const []);
    final now = ref.watch(clockProvider);
    final current = today.current;
    final lastFinished = today.tries.where((r) => r.finished).lastOrNull;

    final Widget body = switch (trivia) {
      AsyncData(value: (_, final bank)) when bank.isEmpty => const _NoQuestions(),
      AsyncData() when _run != null && _round != null => _QuestionView(
        run: _run!,
        round: _round!,
        phase: _phase,
        chosen: _chosen,
        bar: _bar,
        onAnswer: _answer,
        onNext: _next,
      ),
      AsyncData(value: (final d, final bank)) when lastFinished != null && current == null => _GameOver(
        today: today,
        run: lastFinished,
        best: triviaBest(days),
        streak: triviaStreak(days, day),
        leftCounted: _leftCounted,
        onTryAgain: today.next == null ? null : () => _start(d, bank, today.next!),
      ),
      AsyncData(value: (final d, final bank)) => _StartCard(
        date: now,
        run: today.next!,
        todayBest: lastFinished == null ? null : today.best,
        best: triviaBest(days),
        streak: triviaStreak(days, day),
        onStart: () => _start(d, bank, today.next!),
      ),
      AsyncError() => const _NoQuestions(),
      _ => const SizedBox(height: 300, child: Center(child: CircularProgressIndicator())),
    };

    return ListView(
      padding: EdgeInsets.fromLTRB(phone ? 16 : 40, phone ? 20 : 32, phone ? 16 : 40, 40),
      children: [
        Text('Bamboo Trivia', style: phone ? PandaText.title : PandaText.display),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: body),
        ),
      ],
    );
  }
}

/// Hearts for the lives left, with a label for screen readers.
class _Lives extends StatelessWidget {
  const _Lives(this.lives);
  final int lives;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$lives ${lives == 1 ? 'life' : 'lives'} left',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < TriviaRules.maxLives; i++)
          Icon(
            i < lives ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            key: ValueKey('life-$i-${i < lives ? 'full' : 'empty'}'),
            color: context.panda.overdue,
            size: 26,
          ),
      ],
    ),
  );
}

class _StartCard extends StatelessWidget {
  const _StartCard({
    required this.date,
    required this.run,
    required this.todayBest,
    required this.best,
    required this.streak,
    required this.onStart,
  });

  final DateTime date;

  /// The try to start or continue.
  final TriviaRun run;

  /// The better score of today's finished tries, or null before the first one ends.
  final int? todayBest;
  final int best;
  final int streak;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final p = context.panda;
    Widget rule(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: p.bambooDark),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: PandaText.body)),
        ],
      ),
    );
    return PandaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const PandaMascot(size: 72),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Try ${run.attempt} of ${TriviaRules.triesPerDay}',
                      key: const ValueKey('trivia-try'),
                      style: PandaText.title,
                    ),
                    Text(DateFormat('EEEE d MMMM').format(date), style: PandaText.body.copyWith(color: p.muted)),
                    if (todayBest != null)
                      Text(
                        'Today’s best so far: $todayBest',
                        style: PandaText.bodyStrong.copyWith(color: p.bambooDark),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          rule(
            Icons.favorite_rounded,
            'You have ${TriviaRules.maxLives} lives. A wrong answer, or running out of time, costs one.',
          ),
          rule(Icons.trending_up_rounded, 'Each question is a little harder, with a little less time.'),
          rule(Icons.bolt_rounded, 'Answer correctly within 1 second of the answers appearing to win back a life.'),
          rule(
            Icons.emoji_events_rounded,
            'Your score is how many you get right. Two tries a day, with different questions: your better score counts.',
          ),
          const SizedBox(height: 8),
          _Stats(best: best, streak: streak),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(
              run.started
                  ? 'Continue (question ${run.nextNumber})'
                  : run.attempt == 1
                  ? 'Start'
                  : 'Start try ${run.attempt}',
            ),
          ),
          const SizedBox(height: 16),
          Text(triviaCredit, style: PandaText.caption.copyWith(color: p.muted)),
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.best, required this.streak});
  final int best;
  final int streak;

  @override
  Widget build(BuildContext context) {
    final p = context.panda;
    Widget stat(IconData icon, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: p.bambooDark),
        const SizedBox(width: 6),
        Text(text, style: PandaText.bodyStrong),
      ],
    );
    return Wrap(
      spacing: 24,
      runSpacing: 8,
      children: [
        stat(Icons.local_fire_department_rounded, 'Streak: $streak ${streak == 1 ? 'day' : 'days'}'),
        stat(Icons.emoji_events_rounded, 'Best: $best'),
      ],
    );
  }
}

class _QuestionView extends StatelessWidget {
  const _QuestionView({
    required this.run,
    required this.round,
    required this.phase,
    required this.chosen,
    required this.bar,
    required this.onAnswer,
    required this.onNext,
  });

  final TriviaRun run;
  final TriviaRound round;
  final _Phase phase;
  final int? chosen;
  final ValueNotifier<double> bar;
  final ValueChanged<int> onAnswer;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final p = context.panda;
    final last = phase == _Phase.reveal ? run.answers.last : null;
    final limit = TriviaRules.timeLimit(round.number);
    return PandaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Lives(run.lives),
              const Spacer(),
              Text('Score ${run.score}', key: const ValueKey('trivia-score'), style: PandaText.heading),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Question ${round.number} · ${TriviaRules.difficultyFor(round.number).label}',
                style: PandaText.captionStrong.copyWith(color: p.muted),
              ),
              if (round.question.category.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(color: p.bambooTint, borderRadius: BorderRadius.circular(PandaSizes.pill)),
                  child: Text(
                    _shortCategory(round.question.category),
                    style: PandaText.caption.copyWith(color: p.bambooDark),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(round.question.question, key: const ValueKey('trivia-question'), style: PandaText.title),
          const SizedBox(height: 20),
          if (phase == _Phase.reading) ...[
            Text('Get ready…', style: PandaText.body.copyWith(color: p.muted)),
            const SizedBox(height: 8),
            _Bar(bar: bar, color: (_) => p.bambooTint),
            const SizedBox(height: 220),
          ] else ...[
            _Bar(
              bar: bar,
              color: (v) => phase == _Phase.answering && v * limit.inMilliseconds < 3000 ? p.overdue : p.bamboo,
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < round.answers.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AnswerButton(
                  label: round.answers[i],
                  look: phase != _Phase.reveal
                      ? _Look.plain
                      : i == round.correctIndex
                      ? _Look.right
                      : i == chosen
                      ? _Look.wrong
                      : _Look.faded,
                  onTap: phase == _Phase.answering ? () => onAnswer(i) : null,
                ),
              ),
          ],
          if (last != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    last.fast && run.lives > _livesBefore(run)
                        ? '⚡ Lightning fast! +1 life'
                        : last.fast
                        ? '⚡ Lightning fast!'
                        : last.correct
                        ? 'Correct!'
                        : last.timedOut
                        ? 'Out of time'
                        : 'Not quite',
                    key: const ValueKey('trivia-feedback'),
                    style: PandaText.heading.copyWith(color: last.correct ? p.bambooDark : p.overdue),
                  ),
                ),
                TextButton(onPressed: onNext, child: Text(run.finished ? 'See result' : 'Next')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Lives before the last answer.
int _livesBefore(TriviaRun run) =>
    TriviaRun(day: run.day, answers: run.answers.sublist(0, run.answers.length - 1)).lives;

/// "Entertainment: Film" → "Film".
String _shortCategory(String category) => category.contains(': ') ? category.split(': ').last : category;

class _Bar extends StatelessWidget {
  const _Bar({required this.bar, required this.color});
  final ValueNotifier<double> bar;
  final Color Function(double) color;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: bar,
    builder: (context, v, _) => LinearProgressIndicator(
      value: v,
      minHeight: 8,
      borderRadius: BorderRadius.circular(PandaSizes.pill),
      color: color(v),
      backgroundColor: context.panda.line,
    ),
  );
}

enum _Look { plain, right, wrong, faded }

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({required this.label, required this.look, required this.onTap});
  final String label;
  final _Look look;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.panda;
    final (bg, fg, border, icon) = switch (look) {
      _Look.right => (p.bambooTint, p.bambooDark, p.bambooDark, Icons.check_circle_rounded),
      _Look.wrong => (p.overdueTint, p.overdue, p.overdue, Icons.cancel_rounded),
      _Look.faded => (p.surface, p.muted, p.line, null),
      _Look.plain => (p.surface, p.ink, p.line, null),
    };
    return Semantics(
      button: true,
      label: switch (look) {
        _Look.right => '$label, correct answer',
        _Look.wrong => '$label, wrong',
        _ => label,
      },
      excludeSemantics: true,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PandaSizes.tileRadius),
          side: BorderSide(color: border, width: look == _Look.plain || look == _Look.faded ? 1.5 : 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: p.bambooTint,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(label, style: PandaText.bodyStrong.copyWith(color: fg)),
                  ),
                  if (icon != null) Icon(icon, color: fg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GameOver extends StatelessWidget {
  const _GameOver({
    required this.today,
    required this.run,
    required this.best,
    required this.streak,
    required this.leftCounted,
    required this.onTryAgain,
  });

  final TriviaDay today;

  /// The try that just ended.
  final TriviaRun run;
  final int best;
  final int streak;
  final bool leftCounted;

  /// Starts the next try; null when today's tries are used up.
  final VoidCallback? onTryAgain;

  @override
  Widget build(BuildContext context) {
    final p = context.panda;
    final finished = [
      for (final r in today.tries)
        if (r.finished) r,
    ];
    final allDone = onTryAgain == null;
    final left = today.triesLeft;
    return PandaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: PandaMascot(size: 88, sleeping: run.score == 0)),
          const SizedBox(height: 12),
          Text(
            'You got ${run.score} right',
            key: const ValueKey('trivia-final'),
            textAlign: TextAlign.center,
            style: PandaText.display,
          ),
          const SizedBox(height: 4),
          Text(
            allDone
                ? 'Today’s score: ${today.best} (your better try). New questions tomorrow.'
                : 'Today’s best so far: ${today.best}. You have $left ${left == 1 ? 'try' : 'tries'} left.',
            key: const ValueKey('trivia-today'),
            textAlign: TextAlign.center,
            style: PandaText.body.copyWith(color: p.muted),
          ),
          if (allDone && today.best >= best && today.best > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Your best day yet!',
              textAlign: TextAlign.center,
              style: PandaText.bodyStrong.copyWith(color: p.bambooDark),
            ),
          ],
          if (leftCounted) ...[
            const SizedBox(height: 4),
            Text(
              'The question you left half-way counted as missed.',
              textAlign: TextAlign.center,
              style: PandaText.caption.copyWith(color: p.muted),
            ),
          ],
          const SizedBox(height: 16),
          for (final r in finished)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                children: [
                  if (finished.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        'Try ${r.attempt}: ${r.score} right',
                        style: PandaText.captionStrong.copyWith(color: p.muted),
                      ),
                    ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final (i, a) in r.answers.indexed)
                        _ResultSquare(attempt: r.attempt, number: i + 1, answer: a),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Center(
            child: _Stats(best: best, streak: streak),
          ),
          const SizedBox(height: 20),
          Center(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                if (onTryAgain != null)
                  FilledButton.icon(
                    onPressed: onTryAgain,
                    icon: const Icon(Icons.replay_rounded),
                    label: Text('Try again ($left ${left == 1 ? 'try' : 'tries'} left)'),
                  ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: (today.bestTry ?? run).shareText));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Result copied')));
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy result'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            triviaCredit,
            textAlign: TextAlign.center,
            style: PandaText.caption.copyWith(color: p.muted),
          ),
        ],
      ),
    );
  }
}

/// One question's result: a green tick, a lightning bolt (right and fast), or a red cross.
class _ResultSquare extends StatelessWidget {
  const _ResultSquare({required this.attempt, required this.number, required this.answer});
  final int attempt;
  final int number;
  final TriviaAnswer answer;

  @override
  Widget build(BuildContext context) {
    final p = context.panda;
    final (bg, fg, icon, label) = answer.fast
        ? (p.bamboo, p.onBamboo, Icons.bolt_rounded, 'right, fast')
        : answer.correct
        ? (p.bambooTint, p.bambooDark, Icons.check_rounded, 'right')
        : (p.overdueTint, p.overdue, Icons.close_rounded, answer.timedOut ? 'out of time' : 'wrong');
    return Tooltip(
      message: 'Try $attempt, question $number: $label',
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 20, color: fg),
      ),
    );
  }
}

class _NoQuestions extends StatelessWidget {
  const _NoQuestions();

  @override
  Widget build(BuildContext context) => PandaCard(
    child: Column(
      children: [
        const PandaMascot(size: 72, sleeping: true),
        const SizedBox(height: 12),
        const Text('Questions are on their way', style: PandaText.title, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(
          'This version of the app has no trivia questions yet. They arrive with the next update.',
          textAlign: TextAlign.center,
          style: PandaText.body.copyWith(color: context.panda.muted),
        ),
      ],
    ),
  );
}
