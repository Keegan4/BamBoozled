import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle;

import '../../domain/trivia/trivia_question.dart';
import '../../domain/trivia/trivia_run.dart';
import '../local/app_database.dart';

/// Loads the bundled question bank (made by tool/fetch_trivia.dart).
Future<List<TriviaQuestion>> loadTriviaBank(AssetBundle bundle) async {
  final raw = await bundle.loadString(TriviaStore.bankAsset);
  return [for (final q in jsonDecode(raw) as List) TriviaQuestion.fromJson(q as Map<String, dynamic>)];
}

/// Trivia tries, kept on this device in the settings table as one JSON list of runs.
class TriviaStore {
  TriviaStore(this.db);
  final AppDatabase db;

  static const key = 'trivia_runs';
  static const bankAsset = 'assets/trivia/questions.json';

  /// Older runs are dropped so the setting stays small.
  static const keepDays = 400;

  /// Every saved try, grouped by day.
  static Map<int, TriviaDay> decode(String? value) {
    if (value == null) return {};
    try {
      final runs = [for (final r in jsonDecode(value) as List) TriviaRun.fromJson(r as Map<String, dynamic>)];
      return {
        for (final day in {for (final r in runs) r.day}) day: TriviaDay(day, runs),
      };
    } catch (_) {
      return {};
    }
  }

  Stream<Map<int, TriviaDay>> watch() => db.watchSetting(key).map(decode);

  /// Saves [run], replacing the earlier copy of the same day and try.
  Future<void> save(TriviaRun run) async {
    final days = decode(await db.getSetting(key));
    days[run.day] = (days[run.day] ?? TriviaDay(run.day, const [])).withRun(run);
    final kept = [
      for (final d in days.values)
        if (d.day > run.day - keepDays) ...d.tries,
    ]..sort((a, b) => a.day != b.day ? a.day - b.day : a.attempt - b.attempt);
    await db.setSetting(key, jsonEncode([for (final r in kept) r.toJson()]));
  }
}
