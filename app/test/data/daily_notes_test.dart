import 'dart:io';

import 'package:bamboozled/data/daily_notes/daily_note_library.dart';
import 'package:bamboozled/data/daily_notes/daily_note_store.dart';
import 'package:bamboozled/data/local/app_database.dart';
import 'package:bamboozled/domain/models/daily_note.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  DailyNoteLibrary parse(String yaml, {Set<String> photos = const {'a.jpg', 'b.jpg'}}) =>
      parseDailyNotes(yaml, assetExists: (path) => photos.any((p) => path == 'assets/daily_notes/$p'));

  test('two cards with the same content are equal', () {
    const a = DailyNote(id: 'a', photo: 'p.jpg', text: 't');
    expect(a, const DailyNote(id: 'a', photo: 'p.jpg', text: 't'));
    expect(a.hashCode, const DailyNote(id: 'a', photo: 'p.jpg', text: 't').hashCode);
    expect(a, isNot(const DailyNote(id: 'a', photo: 'p.jpg', text: 'other')));
    expect('$a', 'DailyNote(a)');
  });

  group('reading notes.yaml', () {
    test('reads every field, including multi-line text and an optional title', () {
      final lib = parse('''
- id: first-card
  photo: a.jpg
  title: Hello
  text: |
    Line one.
    Line two.
- id: second
  photo: b.jpg
  text: Just text
''');
      expect(lib.problems, isEmpty);
      expect(lib.notes, [
        const DailyNote(
          id: 'first-card',
          photo: 'assets/daily_notes/a.jpg',
          title: 'Hello',
          text: 'Line one.\nLine two.',
        ),
        const DailyNote(id: 'second', photo: 'assets/daily_notes/b.jpg', text: 'Just text'),
      ]);
    });

    test('bad cards are skipped with a reason, good ones still load', () {
      final lib = parse('''
- id: Bad Id
  photo: a.jpg
  text: x
- id: good
  photo: a.jpg
  text: fine
- id: good
  photo: b.jpg
  text: duplicate id
- id: no-photo-file
  photo: missing.jpg
  text: x
- id: sneaky
  photo: ../secret.jpg
  text: x
- id: no-text
  photo: a.jpg
- id: too-long
  photo: a.jpg
  text: ${'x' * 401}
- just a string
''');
      expect(lib.notes.map((n) => n.id), ['good']);
      expect(lib.problems, hasLength(7));
      expect(lib.problems.join('\n'), allOf(contains('used twice'), contains('missing.jpg'), contains('400')));
    });

    test('an empty, broken or wrongly shaped file gives no cards instead of crashing', () {
      expect(parse('').notes, isEmpty);
      expect(parse('- id: [unclosed').problems.single, contains('could not be read'));
      expect(parse('id: not-a-list').problems.single, contains('list of cards'));
    });

    test('loads from the app bundle, and copes with notes.yaml being missing', () async {
      final lib = await loadDailyNotes(rootBundle);
      expect(lib.notes, isNotEmpty);
      expect(lib.problems, isEmpty);
      expect((await loadDailyNotes(_EmptyBundle())).notes, isEmpty);
    });
  });

  // Checks the real cards in the repo, so a mistake in what you add fails CI instead of the app.
  group('the cards in assets/daily_notes', () {
    final folder = Directory('assets/daily_notes');
    final yaml = File('assets/daily_notes/notes.yaml').readAsStringSync();
    final lib = parseDailyNotes(yaml, assetExists: (path) => File(path).existsSync());

    test('every card in notes.yaml is valid', () {
      expect(lib.problems, isEmpty, reason: lib.problems.join('\n'));
      expect(lib.notes, isNotEmpty);
    });

    test('every photo is under 1 MB, so the app (and the web version) stays quick', () {
      for (final n in lib.notes) {
        expect(File(n.photo).lengthSync(), lessThan(1024 * 1024), reason: n.photo);
      }
    });

    test('no photo in the folder is left unused', () {
      final used = {for (final n in lib.notes) n.photo.split('/').last};
      final files = folder
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((name) => RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false).hasMatch(name));
      expect(files.toSet().difference(used), isEmpty, reason: 'add these to notes.yaml or delete them');
    });
  });

  group('what has been opened', () {
    late AppDatabase db;
    late DailyNoteStore store;
    final oct9 = DateTime(2026, 10, 9, 14);
    final oct10 = DateTime(2026, 10, 10, 8);

    setUp(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
      store = DailyNoteStore(db);
    });
    tearDown(() => db.close());

    test('starts with nothing opened and today hidden', () async {
      final s = await store.read();
      expect(s.history, isEmpty);
      expect(s.stageOn(oct9), CardStage.hidden);
    });

    test('revealing collects the card; flipping keeps it; the stage is remembered for the day only', () async {
      await store.setStage(oct9, 'a', CardStage.revealed);
      await store.setStage(oct9, 'a', CardStage.back);
      final s = await store.read();
      expect(s.history, [(DateTime(2026, 10, 9), 'a')]);
      expect(s.stageOn(oct9), CardStage.back);
      expect(s.stageOn(oct10), CardStage.hidden);
    });

    test('the collection is newest first, one card per day', () async {
      await store.setStage(oct9, 'a', CardStage.revealed);
      await store.setStage(oct10, 'b', CardStage.revealed);
      await store.setStage(oct10, 'c', CardStage.revealed); // today's card is already fixed as b
      expect((await store.read()).history, [(DateTime(2026, 10, 10), 'b'), (DateTime(2026, 10, 9), 'a')]);
    });

    test('watching shows changes as they happen', () async {
      final states = <DailyNoteState>[];
      final sub = store.watch().listen(states.add);
      await store.setStage(oct9, 'a', CardStage.revealed);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      expect(states.last.history.single.$2, 'a');
    });

    test('unreadable saved data counts as nothing opened', () {
      expect(DailyNoteState.fromSetting('not json').history, isEmpty);
      expect(DailyNoteState.fromSetting('{"stage":"weird"}').stage, CardStage.hidden);
    });

    test('the install id is made once and then kept', () async {
      var made = 0;
      String make() => 'id-${++made}';
      expect(await store.installId(make), 'id-1');
      expect(await store.installId(make), 'id-1');
      expect(made, 1);
    });
  });
}

class _EmptyBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') return const StandardMessageCodec().encodeMessage(<String, Object>{})!;
    throw StateError('no $key');
  }
}
