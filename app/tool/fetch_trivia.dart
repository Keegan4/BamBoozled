// Builds the trivia question bank, assets/trivia/questions.json, from Open Trivia DB
// (https://opentdb.com, questions licensed CC BY-SA 4.0). Run it by hand when the bank needs
// refreshing, then commit the JSON:
//
//   dart run tool/fetch_trivia.dart
//
// It downloads every verified multiple-choice question (about 10 minutes: the site allows one request
// every 5 seconds), drops ones that don't suit the app (see _keep), and keeps any questions already
// in the file, so running it again only adds.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _out = 'assets/trivia/questions.json';

/// Categories that are mostly about one country's pop culture or need niche knowledge.
const _skipCategories = {
  'Celebrities',
  'Politics',
  'Entertainment: Japanese Anime & Manga',
  'Entertainment: Comics',
  'Entertainment: Cartoon & Animations',
  'Entertainment: Musicals & Theatres',
};

/// Words that mark a question as US-only or likely to go out of date.
final _skipWords = RegExp(
  r'\b(NFL|NBA|MLB|NHL|NASCAR|Super Bowl|U\.?S\.? state|US state|Congress|Senator|Governor|President of the United States|'
  r'current|currently|as of|this year|latest)\b',
  caseSensitive: false,
);

/// Answers that only make sense in a fixed order.
final _orderedAnswer = RegExp(r'^(all|none|both|neither) of (the|these) ', caseSensitive: false);

Future<void> main() async {
  final kept = <String, Map<String, dynamic>>{};
  final existing = File(_out);
  if (existing.existsSync()) {
    for (final q in jsonDecode(existing.readAsStringSync()) as List) {
      kept[_norm((q as Map<String, dynamic>)['q'] as String)] = q;
    }
  }
  final before = kept.length;

  final token = (await _getJson('https://opentdb.com/api_token.php?command=request'))['token'] as String;
  var fetched = 0;
  while (true) {
    await Future<void>.delayed(const Duration(milliseconds: 5500));
    final page = await _getJson('https://opentdb.com/api.php?amount=50&type=multiple&encode=base64&token=$token');
    final code = page['response_code'] as int;
    if (code == 5) continue; // rate limited: wait and ask again
    if (code == 4 || code == 1) break; // token has seen every question
    if (code != 0) throw StateError('Open Trivia DB answered code $code');
    for (final raw in page['results'] as List) {
      fetched++;
      final r = raw as Map<String, dynamic>;
      String d(Object? s) => utf8.decode(base64.decode(s! as String)).trim();
      final q = {
        'q': d(r['question']),
        'a': d(r['correct_answer']),
        'wrong': [for (final w in r['incorrect_answers'] as List) d(w)],
        'cat': d(r['category']),
        'diff': d(r['difficulty']),
      };
      if (_keep(q)) kept.putIfAbsent(_norm(q['q']! as String), () => q);
    }
    stdout.write('\rFetched $fetched, keeping ${kept.length}   ');
  }

  final list = kept.values.toList()..sort((a, b) => (a['q'] as String).compareTo(b['q'] as String));
  existing.parent.createSync(recursive: true);
  existing.writeAsStringSync('${const JsonEncoder.withIndent(' ').convert(list)}\n');
  stdout.writeln('\nWrote ${list.length} questions to $_out (${list.length - before} new).');
}

bool _keep(Map<String, dynamic> q) {
  final question = q['q'] as String;
  final answers = [q['a'] as String, ...(q['wrong'] as List).cast<String>()];
  return !_skipCategories.contains(q['cat']) &&
      question.length <= 140 &&
      !_skipWords.hasMatch(question) &&
      answers.length == 4 &&
      answers.toSet().length == 4 &&
      answers.every((a) => a.isNotEmpty && a.length <= 60 && !_orderedAnswer.hasMatch(a)) &&
      const {'easy', 'medium', 'hard'}.contains(q['diff']);
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

Future<Map<String, dynamic>> _getJson(String url) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode} for $url');
  return jsonDecode(response.body) as Map<String, dynamic>;
}
