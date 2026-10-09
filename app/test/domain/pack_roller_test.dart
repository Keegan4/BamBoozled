import 'package:bamboozled/domain/models/cards.dart';
import 'package:bamboozled/domain/services/pack_roller.dart';
import 'package:bamboozled/domain/services/seeded_random.dart';
import 'package:flutter_test/flutter_test.dart';

CardDef card(String id, Rarity r, {Set<Finish> excluded = const {}}) =>
    CardDef(id: id, number: 1, name: id, rarity: r, photo: 'p.jpg', text: 't', excluded: excluded);

final set = [
  for (var i = 0; i < 5; i++) card('c$i', Rarity.common),
  for (var i = 0; i < 3; i++) card('r$i', Rarity.rare),
  card('e0', Rarity.epic),
  card('e1', Rarity.epic),
  card('l0', Rarity.legendary),
  card('l1', Rarity.legendary),
];

void main() {
  group('SeededRandom', () {
    test('the same seed gives the same numbers', () {
      final a = SeededRandom('panda'), b = SeededRandom('panda');
      expect([for (var i = 0; i < 20; i++) a.nextDouble()], [for (var i = 0; i < 20; i++) b.nextDouble()]);
    });

    test('different seeds give different numbers', () {
      expect(SeededRandom('a').nextDouble(), isNot(SeededRandom('b').nextDouble()));
    });

    test('numbers stay in range', () {
      final r = SeededRandom('range');
      for (var i = 0; i < 1000; i++) {
        final d = r.nextDouble();
        expect(d, inInclusiveRange(0, 1));
        expect(d, lessThan(1));
        expect(r.nextInt(7), inInclusiveRange(0, 6));
      }
    });

    test('FNV-1a matches the published value', () {
      expect(SeededRandom.fnv1a(''), 0x811c9dc5);
      expect(SeededRandom.fnv1a('a'), 0xe40c292c);
    });

    test('pick follows the weights', () {
      final r = SeededRandom('weights');
      var a = 0;
      for (var i = 0; i < 10000; i++) {
        if (r.pick({'a': 3.0, 'b': 1.0}) == 'a') a++;
      }
      expect(a / 10000, closeTo(0.75, 0.03));
    });
  });

  group('PackRoller', () {
    test('a pack has 7 cards and is the same for the same seed', () {
      final a = PackRoller.roll(set, PackType.bamboo, SeededRandom('x'));
      final b = PackRoller.roll(set, PackType.bamboo, SeededRandom('x'));
      expect(a, hasLength(PackRoller.cardsPerPack));
      expect(a.map((p) => '${p.$1.id}${p.$2}'), b.map((p) => '${p.$1.id}${p.$2}'));
    });

    test('no cards, no pack', () {
      expect(PackRoller.roll(const [], PackType.bamboo, SeededRandom('x')), isEmpty);
    });

    test('rarities follow the odds: mostly commons first, never commons last', () {
      final counts = <Rarity, int>{};
      final lateCounts = <Rarity, int>{};
      for (var i = 0; i < 2000; i++) {
        final pack = PackRoller.roll(set, PackType.bamboo, SeededRandom('odds$i'));
        for (final (j, (c, _)) in pack.indexed) {
          final m = j < 5 ? counts : lateCounts;
          m[c.rarity] = (m[c.rarity] ?? 0) + 1;
        }
      }
      expect(counts[Rarity.common]! / 10000, closeTo(0.80, 0.03));
      expect(counts[Rarity.legendary], isNull);
      expect(lateCounts[Rarity.common], isNull);
      expect(lateCounts[Rarity.rare]! / 4000, closeTo(0.60, 0.04));
      expect(lateCounts[Rarity.legendary]! / 4000, closeTo(0.10, 0.03));
    });

    test('when pity is due the last card is Legendary', () {
      for (var i = 0; i < 50; i++) {
        final pack = PackRoller.roll(set, PackType.bamboo, SeededRandom('pity$i'), pityDue: true);
        expect(pack.any((p) => p.$1.rarity == Rarity.legendary), isTrue);
      }
    });

    test('a Golden Booster always has a Legendary and a shiny card', () {
      for (var i = 0; i < 50; i++) {
        final pack = PackRoller.roll(set, PackType.golden, SeededRandom('gold$i'));
        expect(pack.any((p) => p.$1.rarity == Rarity.legendary), isTrue);
        expect(pack[5].$2.kind, FinishKind.shiny);
      }
    });

    test('a missing rarity falls back to the nearest one, rarer first', () {
      final commonsOnly = [card('a', Rarity.common), card('b', Rarity.common)];
      final pack = PackRoller.roll(commonsOnly, PackType.golden, SeededRandom('few'));
      expect(pack, hasLength(7));
      final noRares = [card('a', Rarity.common), card('e', Rarity.epic)];
      for (var i = 0; i < 30; i++) {
        final late = PackRoller.roll(noRares, PackType.bamboo, SeededRandom('fb$i')).last;
        expect(late.$1.id, 'e');
      }
    });

    test('excluded finishes are never rolled', () {
      final plain = card('p', Rarity.common, excluded: {...Finish.values}..remove(Finish.none));
      for (var i = 0; i < 200; i++) {
        expect(PackRoller.rollFinish(plain, SeededRandom('ex$i'), boost: 4), Finish.none);
      }
      final noShiny = card(
        'n',
        Rarity.common,
        excluded: {
          for (final f in Finish.values)
            if (f.kind == FinishKind.shiny) f,
        },
      );
      expect(PackRoller.rollFinish(noShiny, SeededRandom('s'), shinyOnly: true), Finish.none);
    });

    test('about 30% of cards get a finish, more with a boost', () {
      expect(PackRoller.finishChance(1), closeTo(30, 0.5));
      expect(PackRoller.finishChance(2), greaterThan(PackRoller.finishChance(1)));
      final r = SeededRandom('finishes');
      final c = card('c', Rarity.common);
      var any = 0;
      for (var i = 0; i < 10000; i++) {
        if (PackRoller.rollFinish(c, r) != Finish.none) any++;
      }
      expect(any / 10000, closeTo(0.30, 0.02));
    });
  });

  group('Finish', () {
    test('keys round-trip', () {
      for (final f in Finish.values) {
        expect(Finish.fromKey(f.key), f);
      }
      expect(Finish.fromKey('sparkly'), isNull);
      expect(Finish.fullArt.key, 'full-art');
    });

    test('the showiest list has every finish once', () {
      expect(Finish.showiest.toSet(), Finish.values.toSet());
      expect(Finish.showiest, hasLength(Finish.values.length));
    });

    test('card numbers are padded', () {
      expect(card('x', Rarity.common).numberLabel, '#001');
    });
  });
}
