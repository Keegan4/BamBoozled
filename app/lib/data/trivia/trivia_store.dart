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

/// Trivia runs, kept on this device in the settings table as one JSON map (day → run).
class TriviaStore {
  TriviaStore(this.db);
  final AppDatabase db;

  static const key = 'trivia_runs';
  static const bankAsset = 'assets/trivia/questions.json';

  /// Older runs are dropped so the setting stays small.
  static const keepDays = 400;

  static Map<int, TriviaRun> decode(String? value) {
    if (value == null) return {};
    try {
      return {
        for (final r in (jsonDecode(value) as List).map((r) => TriviaRun.fromJson(r as Map<String, dynamic>))) r.day: r,
      };
    } catch (_) {
      return {};
    }
  }

  Stream<Map<int, TriviaRun>> watch() => db.watchSetting(key).map(decode);

  Future<void> save(TriviaRun run) async {
    final runs = decode(await db.getSetting(key))..[run.day] = run;
    final kept = runs.values.where((r) => r.day > run.day - keepDays).toList()..sort((a, b) => a.day - b.day);
    await db.setSetting(key, jsonEncode([for (final r in kept) r.toJson()]));
  }
}
