import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

import '../../domain/models/cards.dart';

/// Folder holding the cards: cards.yaml plus the photos.
const cardsFolder = 'assets/cards';

const maxCardTextLength = 90;
const maxFlavourLength = 300;
const maxCardNameLength = 24;

/// The cards that could be read, plus a reason for each entry that couldn't.
class CardLibrary {
  const CardLibrary(this.cards, [this.problems = const []]);
  final List<CardDef> cards;
  final List<String> problems;

  CardDef? byId(String id) {
    for (final c in cards) {
      if (c.id == id) return c;
    }
    return null;
  }
}

final _idPattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

/// Reads cards.yaml. Bad entries are skipped (with a reason) rather than breaking the page; a test
/// runs this on the real file so CI catches mistakes. [assetExists] says whether a photo is in the app.
CardLibrary parseCards(String yamlText, {required bool Function(String path) assetExists}) {
  final Object? doc;
  try {
    doc = loadYaml(yamlText);
  } on YamlException catch (e) {
    return CardLibrary(const [], ['cards.yaml could not be read: ${e.message}']);
  }
  if (doc == null) return const CardLibrary([]);
  if (doc is! YamlList) {
    return const CardLibrary([], ['cards.yaml should be a list of cards, each starting with "- id:"']);
  }

  final cards = <CardDef>[];
  final problems = <String>[];
  final seen = <String>{};
  for (final (i, entry) in doc.indexed) {
    final where = 'Card ${i + 1}';
    if (entry is! YamlMap) {
      problems.add('$where is not a card (expected id, name, photo and text)');
      continue;
    }
    String? field(String key) {
      final v = entry[key]?.toString().trim();
      return v == null || v.isEmpty ? null : v;
    }

    final id = field('id');
    if (id == null || !_idPattern.hasMatch(id)) {
      problems.add('$where: id must be lowercase letters, numbers and dashes, e.g. "bamboo-grove"');
      continue;
    }
    if (!seen.add(id)) {
      problems.add('$where: the id "$id" is used twice');
      continue;
    }
    final name = field('name') ?? field('title');
    if (name == null || name.length > maxCardNameLength) {
      problems.add('$id: name is missing or longer than $maxCardNameLength characters');
      continue;
    }
    final rarityText = field('rarity') ?? 'common';
    final rarity = Rarity.values.asNameMap()[rarityText.toLowerCase()];
    if (rarity == null) {
      problems.add('$id: rarity must be common, rare, epic or legendary (not "$rarityText")');
      continue;
    }
    final photo = field('photo');
    if (photo == null || photo.contains('/') || photo.contains('\\')) {
      problems.add('$id: photo must be the name of a file in $cardsFolder');
      continue;
    }
    if (!assetExists('$cardsFolder/$photo')) {
      problems.add('$id: the photo "$photo" is not in $cardsFolder');
      continue;
    }
    final text = field('text');
    if (text == null || text.length > maxCardTextLength) {
      problems.add('$id: text is missing or longer than $maxCardTextLength characters');
      continue;
    }
    final flavour = field('flavour');
    if (flavour != null && flavour.length > maxFlavourLength) {
      problems.add('$id: flavour is ${flavour.length} characters; keep it to $maxFlavourLength');
      continue;
    }
    final excluded = <Finish>{};
    final exclude = entry['exclude'];
    if (exclude is YamlList) {
      for (final e in exclude) {
        final f = Finish.fromKey(e.toString().trim().toLowerCase());
        if (f == null || f == Finish.none) {
          problems.add('$id: "$e" in exclude is not a finish');
        } else {
          excluded.add(f);
        }
      }
    }
    cards.add(
      CardDef(
        id: id,
        number: cards.length + 1,
        name: name,
        rarity: rarity,
        photo: '$cardsFolder/$photo',
        text: text,
        flavour: flavour,
        artist: field('artist'),
        set: field('set') ?? 'Bamboo Grove',
        excluded: excluded,
      ),
    );
  }
  return CardLibrary(cards, problems);
}

/// Loads the cards bundled with the app.
Future<CardLibrary> loadCards(AssetBundle bundle) async {
  final manifest = await AssetManifest.loadFromAssetBundle(bundle);
  final assets = manifest.listAssets().toSet();
  final String text;
  try {
    text = await bundle.loadString('$cardsFolder/cards.yaml');
  } catch (_) {
    return const CardLibrary([]);
  }
  final library = parseCards(text, assetExists: assets.contains);
  for (final p in library.problems) {
    debugPrint('Cards: $p');
  }
  return library;
}
