import 'package:flutter/painting.dart' show Color;

/// How rare a card is. Set per card in assets/cards/cards.yaml.
enum Rarity {
  common('Common', 1, Color(0xFFF1F1EE)),
  rare('Rare', 3, Color(0xFF3F8EF0)),
  epic('Epic', 8, Color(0xFFA45BE0)),
  legendary('Legendary', 20, Color(0xFFF5A623));

  const Rarity(this.label, this.value, this.gem);
  final String label;

  /// Bamboo shoots a spare copy is worth at the Panda Exchange (before the finish multiplier).
  final int value;

  /// The colour of the rarity gem, and of the glow around a rare card.
  final Color gem;
}

enum FinishKind {
  none,

  /// A colour filter over the photo.
  tint,

  /// Changes how the card is laid out.
  layout,

  /// A sheen that follows the pointer.
  shiny,
}

/// A visual treatment rolled for a card each time it's pulled, separately from its rarity, so one
/// photo can be collected many ways. [weight] is the chance per card in a standard pack, in percent.
enum Finish {
  none('No finish', 70, 1, FinishKind.none, null),
  ink('Ink wash', 5, 2, FinishKind.tint, 'Chinese brush painting'),
  bamboo('Bamboo', 4.5, 2, FinishKind.tint, 'BamBoozled original'),
  moonlight('Moonlight', 4.5, 2, FinishKind.tint, 'BamBoozled original'),
  vintage('Vintage', 4, 2, FinishKind.tint, 'Old photographs'),
  fullArt('Full art', 3, 3, FinishKind.layout, 'Pokémon full art, Magic borderless'),
  signed('Signed', 3, 3, FinishKind.layout, 'Hearthstone Signature cards'),
  reverseHolo('Reverse holo', 3, 3, FinishKind.shiny, 'Pokémon reverse holo'),
  holo('Holo', 1.5, 3, FinishKind.shiny, 'Pokémon holofoil, Magic foil'),
  gold('Gold', 0.4, 5, FinishKind.shiny, 'Hearthstone Golden'),
  cosmos('Cosmos', 0.3, 5, FinishKind.shiny, 'Pokémon cosmos holo'),
  ghost('Ghost', 0.3, 5, FinishKind.shiny, 'Yu-Gi-Oh! Ghost Rare'),
  rainbow('Rainbow', 0.4, 8, FinishKind.shiny, 'Pokémon Rainbow Rare'),
  misprint('Misprint', 0.1, 12, FinishKind.layout, 'Real printing errors');

  const Finish(this.label, this.weight, this.value, this.kind, this.inspiredBy);
  final String label;
  final double weight;

  /// Multiplies a spare copy's value at the exchange.
  final int value;
  final FinishKind kind;
  final String? inspiredBy;

  /// The name used in cards.yaml (e.g. `exclude: [full-art]`) and in saved collections.
  String get key => switch (this) {
    Finish.fullArt => 'full-art',
    Finish.reverseHolo => 'reverse-holo',
    _ => name,
  };

  static Finish? fromKey(String key) {
    for (final f in values) {
      if (f.key == key) return f;
    }
    return null;
  }

  /// Showiest first, for picking which copy to show in the binder.
  static const showiest = [
    misprint,
    rainbow,
    gold,
    cosmos,
    ghost,
    holo,
    reverseHolo,
    signed,
    fullArt,
    ink,
    bamboo,
    moonlight,
    vintage,
    none,
  ];
}

/// One card in the set.
class CardDef {
  const CardDef({
    required this.id,
    required this.number,
    required this.name,
    required this.rarity,
    required this.photo,
    required this.text,
    this.flavour,
    this.artist,
    this.set = 'Bamboo Grove',
    this.excluded = const {},
  });

  final String id;

  /// Position in cards.yaml, from 1. Shown as #001.
  final int number;
  final String name;
  final Rarity rarity;

  /// Asset path of the photo.
  final String photo;
  final String text;
  final String? flavour;
  final String? artist;
  final String set;
  final Set<Finish> excluded;

  String get numberLabel => '#${number.toString().padLeft(3, '0')}';

  @override
  String toString() => 'CardDef($id)';
}

/// A card as pulled from a pack.
class Pull {
  const Pull(this.card, this.finish, {this.newCard = false, this.newFinish = false});

  final CardDef card;
  final Finish finish;

  /// The first copy of this card ever.
  final bool newCard;

  /// The card was already owned, but not in this finish.
  final bool newFinish;

  /// Key of a card + finish in a collection, e.g. `bamboo-grove|holo`.
  String get key => keyOf(card.id, finish);
  static String keyOf(String id, Finish f) => '$id|${f.key}';
}
