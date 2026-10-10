import 'dart:io';

import 'package:bamboozled/data/cards/card_library.dart';
import 'package:bamboozled/data/cards/collection_store.dart';
import 'package:bamboozled/data/local/app_database.dart';
import 'package:bamboozled/domain/models/cards.dart';
import 'package:bamboozled/domain/services/pack_roller.dart';
import 'package:drift/drift.dart' show DatabaseConnection, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

CardLibrary parse(String yaml) => parseCards(yaml, assetExists: (p) => p.endsWith('.jpg'));

void main() {
  group('parseCards', () {
    test('reads a card with every field', () {
      final lib = parse('''
- id: tea-break
  name: Tea Break
  rarity: Rare
  photo: tea.jpg
  text: Step away.
  flavour: Steam curls.
  artist: Ms Tan
  set: Staffroom
  exclude: [full-art, holo]
''');
      expect(lib.problems, isEmpty);
      final c = lib.cards.single;
      expect(c.id, 'tea-break');
      expect(c.number, 1);
      expect(c.name, 'Tea Break');
      expect(c.rarity, Rarity.rare);
      expect(c.photo, 'assets/cards/tea.jpg');
      expect(c.flavour, 'Steam curls.');
      expect(c.artist, 'Ms Tan');
      expect(c.set, 'Staffroom');
      expect(c.excluded, {Finish.fullArt, Finish.holo});
      expect(lib.byId('tea-break'), c);
      expect(lib.byId('nope'), isNull);
    });

    test('rarity defaults to common and title works as a name', () {
      final c = parse('- {id: a, title: A, photo: a.jpg, text: t}').cards.single;
      expect(c.rarity, Rarity.common);
      expect(c.name, 'A');
    });

    test('bad entries are skipped with a reason, good ones kept and numbered', () {
      final lib = parse('''
- just text
- {id: Bad Id, name: X, photo: a.jpg, text: t}
- {id: ok, name: OK, photo: a.jpg, text: t}
- {id: ok, name: Again, photo: a.jpg, text: t}
- {id: noname, photo: a.jpg, text: t}
- {id: odd, name: Odd, rarity: mythic, photo: a.jpg, text: t}
- {id: path, name: P, photo: x/a.jpg, text: t}
- {id: gone, name: G, photo: a.png, text: t}
- {id: notext, name: N, photo: a.jpg}
- {id: long, name: L, photo: a.jpg, text: t, flavour: "${'x' * 301}"}
- {id: ex, name: E, photo: a.jpg, text: t, exclude: [sparkly, none]}
- {id: second, name: S, photo: a.jpg, text: t}
''');
      expect(lib.cards.map((c) => c.id), ['ok', 'ex', 'second']);
      expect(lib.cards.map((c) => c.number), [1, 2, 3]);
      expect(lib.problems, hasLength(11));
      expect(lib.problems.join('\n'), allOf(contains('used twice'), contains('mythic'), contains('not a finish')));
    });

    test('a file that is not a list, or not YAML, is a problem; an empty one is not', () {
      expect(parse('a: 1').problems.single, contains('should be a list'));
      expect(parse('- [unclosed').problems.single, contains('could not be read'));
      expect(parse('').cards, isEmpty);
      expect(parse('').problems, isEmpty);
    });

    test('the bundled cards are all valid', () {
      final lib = parseCards(
        File('assets/cards/cards.yaml').readAsStringSync(),
        assetExists: (p) => File(p).existsSync(),
      );
      expect(lib.problems, isEmpty);
      expect(lib.cards.length, greaterThanOrEqualTo(PackRoller.cardsPerPack));
      for (final r in Rarity.values) {
        expect(lib.cards.where((c) => c.rarity == r), isNotEmpty, reason: 'needs a ${r.label} card');
      }
    });

    test('every photo is used by a card and is under 1 MB', () {
      final lib = parseCards(File('assets/cards/cards.yaml').readAsStringSync(), assetExists: (_) => true);
      final used = lib.cards.map((c) => c.photo).toSet();
      final photos = Directory('assets/cards').listSync().whereType<File>().where((f) => !f.path.endsWith('.yaml'));
      for (final f in photos) {
        final path = f.path.replaceAll(r'\', '/');
        expect(used, contains(path), reason: '$path is not used by any card');
        expect(f.lengthSync(), lessThan(1024 * 1024), reason: '$path is over 1 MB');
      }
    });

    test('loadCards reads the bundle', () async {
      final lib = await loadCards(DiskAssetBundle());
      expect(lib.cards, isNotEmpty);
      expect(lib.problems, isEmpty);
    });
  });

  group('CollectionStore', () {
    late AppDatabase db;
    late CollectionStore store;
    late CardLibrary lib;
    final now = DateTime(2026, 10, 8, 9);
    DateTime later(int minutes) => now.add(Duration(minutes: minutes));

    setUp(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
      store = CollectionStore(db);
      lib = parseCards(File('assets/cards/cards.yaml').readAsStringSync(), assetExists: (p) => true);
    });
    tearDown(() => db.close());

    test('starts with 2 packs; each pack is the same for the same seed and number', () async {
      expect((await store.read()).packsAt(now), 2);
      final first = await store.openPack(lib, 'seed', now);
      final second = await store.openPack(lib, 'seed', now);
      expect(first, hasLength(7));
      expect(second, hasLength(7));
      expect(second.map((p) => p.key), isNot(first.map((p) => p.key)));
      expect(await store.openPack(lib, 'seed', now), isEmpty, reason: 'none left');
      final state = await store.read();
      expect(state.opened, 2);
      expect(state.copies.values.fold<int>(0, (a, b) => a + b), 14);
      expect(state.last!.resolve(lib).map((p) => p.key), second.map((p) => p.key));

      final other = CollectionStore(
        AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true)),
      );
      final again = await other.openPack(lib, 'seed', later(500));
      expect(again.map((p) => p.key), first.map((p) => p.key));
      await other.db.close();
    });

    test('a pack refills every 2 hours, and at most 2 wait', () async {
      await store.openPack(lib, 's', now); // was full: the timer starts now
      var state = await store.read();
      expect(state.packsAt(now), 1);
      expect(state.nextPackAt(now), later(120));
      expect(state.packsAt(later(119)), 1);
      expect(state.packsAt(later(120)), 2);
      expect(state.nextPackAt(later(120)), isNull, reason: 'full');
      expect(state.packsAt(later(60 * 24)), 2, reason: 'never more than 2');

      // Opening while one is filling keeps the time already spent on it.
      await store.openPack(lib, 's', later(90));
      state = await store.read();
      expect(state.packsAt(later(90)), 0);
      expect(state.nextPackAt(later(90)), later(120));
      expect(await store.openPack(lib, 's', later(100)), isEmpty);
      expect((await store.read()).packsAt(later(240)), 2);

      // Three intervals later with one spare: the leftover time carries on.
      await store.openPack(lib, 's', later(250));
      state = await store.read();
      expect(state.packsAt(later(250)), 1);
      expect(state.nextPackAt(later(250)), later(370), reason: 'full again at 240, so the timer restarted at 250');
    });

    test('a clock set backwards gives nothing extra', () async {
      await store.openPack(lib, 's', now);
      await store.openPack(lib, 's', later(30));
      final state = await store.read();
      expect(state.packsAt(now.subtract(const Duration(days: 1))), 0);
      expect(state.nextPackAt(now.subtract(const Duration(days: 1))), later(120));
    });

    test('marks new cards and new finishes, once each', () async {
      final pulls = await store.openPack(lib, 'marks', now);
      final seen = <String>{};
      final seenKeys = <String>{};
      for (final p in pulls) {
        expect(p.newCard, !seen.contains(p.card.id));
        expect(p.newFinish, seen.contains(p.card.id) && !seenKeys.contains(p.key));
        seen.add(p.card.id);
        seenKeys.add(p.key);
      }
    });

    test('no cards, no pack', () async {
      expect(await store.openPack(const CardLibrary([]), 's', now), isEmpty);
      expect((await store.read()).packsAt(now), 2);
    });

    test('counts packs since a Legendary and guarantees one after 10', () async {
      var at = now;
      for (var i = 0; i < 30; i++) {
        final pulls = await store.openPack(lib, 'pity', at);
        final state = await store.read();
        final legendary = pulls.any((p) => p.card.rarity == Rarity.legendary);
        expect(state.packsSinceLegendary, legendary ? 0 : greaterThan(0));
        expect(state.packsSinceLegendary, lessThan(PackRoller.pityAfter));
        at = at.add(const Duration(hours: 2));
      }
    });

    test('watch follows changes', () async {
      final states = store.watch().take(2).toList();
      await store.openPack(lib, 'w', now);
      final got = await states;
      expect(got.first.copies, isEmpty);
      expect(got.last.copies, isNotEmpty);
    });

    test('the install id is made once', () async {
      var made = 0;
      String create() => 'id${made++}';
      expect(await store.installId(create), 'id0');
      expect(await store.installId(create), 'id0');
      expect(made, 1);
    });
  });

  group('CollectionState', () {
    test('round-trips through the setting', () {
      final s = CollectionState(
        copies: const {'a|none': 2, 'a|holo': 1, 'b|full-art': 1},
        stored: 1,
        refillFrom: DateTime(2026, 10, 8, 9, 30),
        opened: 5,
        packsSinceLegendary: 3,
        last: OpenedPack(PackType.bamboo, '2026-10-08', const [('a|holo', true, false), ('b|full-art', false, true)]),
      );
      final back = CollectionState.fromSetting(s.toSetting());
      expect(back.copies, s.copies);
      expect(back.stored, 1);
      expect(back.refillFrom, DateTime(2026, 10, 8, 9, 30));
      expect(back.opened, 5);
      expect(back.packsSinceLegendary, 3);
      expect(back.last!.pulls, s.last!.pulls);
      expect(back.copiesOf('a'), 3);
      expect(back.copiesIn('a', Finish.holo), 1);
      expect(back.finishesOf('a'), [Finish.holo, Finish.none]);
    });

    test('a missing or broken setting is an empty collection', () {
      expect(CollectionState.fromSetting(null).copies, isEmpty);
      expect(CollectionState.fromSetting('not json').copies, isEmpty);
      expect(CollectionState.fromSetting('{}').last, isNull);
      expect(CollectionState.fromSetting('{}').packsAt(DateTime(2026)), 2, reason: 'starts full');
    });

    test('resolve skips cards and finishes that no longer exist', () {
      final lib = CardLibrary([
        const CardDef(id: 'a', number: 1, name: 'A', rarity: Rarity.common, photo: 'p', text: 't'),
      ]);
      final pack = OpenedPack(PackType.bamboo, 'd', const [
        ('a|holo', true, false),
        ('gone|none', true, false),
        ('a|sparkly', false, false),
        ('nobar', false, false),
      ]);
      expect(pack.resolve(lib).map((p) => p.key), ['a|holo']);
    });
  });
}
