import '../models/cards.dart';
import 'stable_random.dart';

/// The kinds of pack. The daily pack is free; the others are bought at the Panda Exchange with
/// spare cards, and the better the pack, the rarer its cards and the more finishes it has.
enum PackType {
  bamboo(
    'Bamboo Booster',
    cost: 0,
    early: {Rarity.common: 80, Rarity.rare: 17, Rarity.epic: 3, Rarity.legendary: 0},
    late: {Rarity.common: 0, Rarity.rare: 60, Rarity.epic: 30, Rarity.legendary: 10},
    finishBoost: 1,
    lastFinishBoost: 2,
  ),
  jade(
    'Jade Booster',
    cost: 25,
    early: {Rarity.common: 65, Rarity.rare: 27, Rarity.epic: 7, Rarity.legendary: 1},
    late: {Rarity.common: 0, Rarity.rare: 40, Rarity.epic: 42, Rarity.legendary: 18},
    finishBoost: 2,
    lastFinishBoost: 3,
  ),
  golden(
    'Golden Booster',
    cost: 70,
    early: {Rarity.common: 50, Rarity.rare: 35, Rarity.epic: 12, Rarity.legendary: 3},
    late: {Rarity.common: 0, Rarity.rare: 15, Rarity.epic: 45, Rarity.legendary: 40},
    finishBoost: 3,
    lastFinishBoost: 4,
    guaranteeLegendary: true,
    guaranteeShiny: true,
  );

  const PackType(
    this.label, {
    required this.cost,
    required this.early,
    required this.late,
    required this.finishBoost,
    required this.lastFinishBoost,
    this.guaranteeLegendary = false,
    this.guaranteeShiny = false,
  });

  final String label;

  /// Bamboo shoots needed at the exchange (0 = the free daily pack).
  final int cost;

  /// Rarity odds (percent) for cards 1–5 and for cards 6–7.
  final Map<Rarity, double> early;
  final Map<Rarity, double> late;

  /// Multiplies the chance of every finish; the last card gets [lastFinishBoost] instead.
  final double finishBoost;
  final double lastFinishBoost;
  final bool guaranteeLegendary;
  final bool guaranteeShiny;
}

abstract final class PackRoller {
  static const cardsPerPack = 7;

  /// A Legendary is guaranteed once this many packs in a row have had none.
  static const pityAfter = 10;

  /// Rolls one pack. Uses only [random], so the same seed always gives the same pack.
  /// [pityDue] forces a Legendary into the last slot. Returns cards in the order they're revealed.
  static List<(CardDef, Finish)> roll(List<CardDef> cards, PackType type, StableRandom random, {bool pityDue = false}) {
    if (cards.isEmpty) return const [];
    final byRarity = {for (final r in Rarity.values) r: cards.where((c) => c.rarity == r).toList()};
    final out = <(CardDef, Finish)>[];
    for (var i = 0; i < cardsPerPack; i++) {
      var rarity = random.pick(i < 5 ? type.early : type.late);
      final last = i == cardsPerPack - 1;
      if (last && (type.guaranteeLegendary || pityDue) && !out.any((p) => p.$1.rarity == Rarity.legendary)) {
        rarity = Rarity.legendary;
      }
      final pool = _poolFor(rarity, byRarity);
      final card = pool[random.nextInt(pool.length)];
      final boost = last ? type.lastFinishBoost : type.finishBoost;
      final shinyOnly = type.guaranteeShiny && i == cardsPerPack - 2;
      out.add((card, rollFinish(card, random, boost: boost, shinyOnly: shinyOnly)));
    }
    return out;
  }

  /// A set may have no cards of some rarity yet: fall back to the nearest rarity that has some,
  /// preferring rarer over commoner.
  static List<CardDef> _poolFor(Rarity wanted, Map<Rarity, List<CardDef>> byRarity) {
    if (byRarity[wanted]!.isNotEmpty) return byRarity[wanted]!;
    for (var d = 1; d < Rarity.values.length; d++) {
      for (final i in [wanted.index + d, wanted.index - d]) {
        if (i >= 0 && i < Rarity.values.length && byRarity[Rarity.values[i]]!.isNotEmpty) {
          return byRarity[Rarity.values[i]]!;
        }
      }
    }
    return byRarity.values.firstWhere((l) => l.isNotEmpty);
  }

  static Finish rollFinish(CardDef card, StableRandom random, {double boost = 1, bool shinyOnly = false}) {
    final weights = {
      for (final f in Finish.values)
        if (!card.excluded.contains(f) && (!shinyOnly || f.kind == FinishKind.shiny))
          f: f == Finish.none ? f.weight : f.weight * boost,
    };
    if (weights.isEmpty) return Finish.none;
    return random.pick(weights);
  }

  /// Chance (percent) that a card gets any finish at all, for the odds table.
  static double finishChance(double boost) {
    final others = Finish.values.where((f) => f != Finish.none).fold<double>(0, (s, f) => s + f.weight * boost);
    return others / (others + Finish.none.weight) * 100;
  }
}
