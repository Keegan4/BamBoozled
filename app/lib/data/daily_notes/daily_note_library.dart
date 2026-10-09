import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

import '../../domain/models/daily_note.dart';

/// Folder holding the cards: notes.yaml plus the photos.
const dailyNotesFolder = 'assets/daily_notes';

/// Longest message allowed on the back of a card.
const maxNoteTextLength = 400;

/// The cards that could be read, plus a reason for each entry that couldn't.
class DailyNoteLibrary {
  const DailyNoteLibrary(this.notes, [this.problems = const []]);
  final List<DailyNote> notes;
  final List<String> problems;
}

final _idPattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

/// Reads notes.yaml. Bad entries are skipped (with a reason in [DailyNoteLibrary.problems]) rather
/// than breaking the page; a test runs [parseDailyNotes] on the real file so CI catches mistakes.
/// [assetExists] says whether a photo is in the app.
DailyNoteLibrary parseDailyNotes(String yamlText, {required bool Function(String path) assetExists}) {
  final Object? doc;
  try {
    doc = loadYaml(yamlText);
  } on YamlException catch (e) {
    return DailyNoteLibrary(const [], ['notes.yaml could not be read: ${e.message}']);
  }
  if (doc == null) return const DailyNoteLibrary([]);
  if (doc is! YamlList) {
    return const DailyNoteLibrary([], ['notes.yaml should be a list of cards, each starting with "- id:"']);
  }

  final notes = <DailyNote>[];
  final problems = <String>[];
  final seen = <String>{};
  for (final (i, entry) in doc.indexed) {
    final where = 'Card ${i + 1}';
    if (entry is! YamlMap) {
      problems.add('$where is not a card (expected id, photo and text)');
      continue;
    }
    String? field(String key) => entry[key]?.toString().trim();

    final id = field('id');
    final photo = field('photo');
    final title = field('title');
    final text = field('text');
    if (id == null || !_idPattern.hasMatch(id)) {
      problems.add('$where: id must be lowercase letters, numbers and dashes, e.g. "bamboo-forest"');
      continue;
    }
    if (!seen.add(id)) {
      problems.add('$where: the id "$id" is used twice');
      continue;
    }
    if (photo == null || photo.isEmpty || photo.contains('/') || photo.contains('\\')) {
      problems.add('$id: photo must be the name of a file in $dailyNotesFolder');
      continue;
    }
    final path = '$dailyNotesFolder/$photo';
    if (!assetExists(path)) {
      problems.add('$id: the photo "$photo" is not in $dailyNotesFolder');
      continue;
    }
    if (text == null || text.isEmpty) {
      problems.add('$id: text is missing');
      continue;
    }
    if (text.length > maxNoteTextLength) {
      problems.add('$id: text is ${text.length} characters; keep it to $maxNoteTextLength');
      continue;
    }
    notes.add(DailyNote(id: id, photo: path, title: title == null || title.isEmpty ? null : title, text: text));
  }
  return DailyNoteLibrary(notes, problems);
}

/// Loads the cards bundled with the app.
Future<DailyNoteLibrary> loadDailyNotes(AssetBundle bundle) async {
  final manifest = await AssetManifest.loadFromAssetBundle(bundle);
  final assets = manifest.listAssets().toSet();
  final String text;
  try {
    text = await bundle.loadString('$dailyNotesFolder/notes.yaml');
  } catch (_) {
    return const DailyNoteLibrary([]);
  }
  final library = parseDailyNotes(text, assetExists: assets.contains);
  for (final p in library.problems) {
    debugPrint('Daily notes: $p');
  }
  return library;
}
