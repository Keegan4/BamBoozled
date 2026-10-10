import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

import '../../domain/models/cards.dart';

/// Folder holding the cards: cards.yaml, themes.yaml and the photos.
const cardsFolder = 'assets/cards';

const maxCardTextLength = 90;
const maxFlavourLength = 300;
const maxCardNameLength = 24;

/// The cards that could be read, plus a reason for each entry that couldn't.
class CardLibrary {
  const CardLibrary(this.cards, [this.problems = const [], this.themes = const []]);
  final List<CardDef> cards;
  final List<String> problems;

  /// Themes that have at least one card, in themes.yaml order.
  final List<StoryTheme> themes;

  List<CardDef> cardsIn(String themeId) => [
    for (final c in cards)
      if (c.themes.contains(themeId)) c,
  ];

  StoryTheme? themeById(String id) {
    for (final t in themes) {
      if (t.id == id) return t;
    }
    return null;
  }

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
///
/// [themeIds] are the themes in themes.yaml; a card tagged with any other theme is kept, without
/// that tag, and the tag is reported.
CardLibrary parseCards(String yamlText, {required bool Function(String path) assetExists, Set<String>? themeIds}) {
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
    final themes = <String>[];
    final tags = entry['themes'] ?? entry['theme'];
    for (final t in tags is YamlList ? tags : [?tags]) {
      final tag = t.toString().trim().toLowerCase();
      if (themeIds != null && !themeIds.contains(tag)) {
        problems.add('$id: the theme "$t" is not in themes.yaml');
      } else if (!themes.contains(tag)) {
        themes.add(tag);
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
        themes: themes,
      ),
    );
  }
  return CardLibrary(cards, problems);
}

const maxStoryLength = 1500;

/// Reads themes.yaml: a list of themes, each with an id, a name and the story it unlocks.
(List<StoryTheme>, List<String>) parseThemes(String yamlText) {
  final Object? doc;
  try {
    doc = loadYaml(yamlText);
  } on YamlException catch (e) {
    return (const <StoryTheme>[], ['themes.yaml could not be read: ${e.message}']);
  }
  if (doc == null) return (const <StoryTheme>[], const <String>[]);
  if (doc is! YamlList) {
    return (const <StoryTheme>[], ['themes.yaml should be a list of themes, each starting with "- id:"']);
  }
  final themes = <StoryTheme>[];
  final problems = <String>[];
  for (final (i, entry) in doc.indexed) {
    final where = 'Theme ${i + 1}';
    if (entry is! YamlMap) {
      problems.add('$where is not a theme (expected id, name and story)');
      continue;
    }
    String? field(String key) {
      final v = entry[key]?.toString().trim();
      return v == null || v.isEmpty ? null : v;
    }

    final id = field('id');
    if (id == null || !_idPattern.hasMatch(id)) {
      problems.add('$where: id must be lowercase letters, numbers and dashes, e.g. "school-day"');
      continue;
    }
    if (themes.any((t) => t.id == id)) {
      problems.add('$where: the id "$id" is used twice');
      continue;
    }
    final name = field('name');
    final story = field('story');
    if (name == null || name.length > 40) {
      problems.add('$id: name is missing or longer than 40 characters');
      continue;
    }
    if (story == null || story.length > maxStoryLength) {
      problems.add('$id: story is missing or longer than $maxStoryLength characters');
      continue;
    }
    // Lines within a paragraph are joined, so the story wraps to the screen; blank lines between
    // paragraphs are kept.
    final paragraphs = [
      for (final para in story.split(RegExp(r'\n\s*\n'))) para.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim(),
    ];
    themes.add(StoryTheme(id: id, name: name, story: paragraphs.join('\n\n'), blurb: field('blurb')));
  }
  return (themes, problems);
}

/// Puts cards and themes together, keeping only themes that have cards.
CardLibrary buildLibrary(String cardsYaml, String? themesYaml, {required bool Function(String path) assetExists}) {
  final (themes, themeProblems) = themesYaml == null
      ? (const <StoryTheme>[], const <String>[])
      : parseThemes(themesYaml);
  final parsed = parseCards(cardsYaml, assetExists: assetExists, themeIds: {for (final t in themes) t.id});
  final used = {for (final c in parsed.cards) ...c.themes};
  return CardLibrary(
    parsed.cards,
    [...themeProblems, ...parsed.problems],
    [
      for (final t in themes)
        if (used.contains(t.id)) t,
    ],
  );
}

/// Loads the cards bundled with the app.
Future<CardLibrary> loadCards(AssetBundle bundle) async {
  Future<String?> read(String name) async {
    try {
      return await bundle.loadString('$cardsFolder/$name');
    } catch (_) {
      return null;
    }
  }

  // All three at once.
  final (manifest, text, themes) = await (
    AssetManifest.loadFromAssetBundle(bundle),
    read('cards.yaml'),
    read('themes.yaml'),
  ).wait;
  if (text == null) return const CardLibrary([]);
  final assets = manifest.listAssets().toSet();
  final library = buildLibrary(text, themes, assetExists: assets.contains);
  for (final p in library.problems) {
    debugPrint('Cards: $p');
  }
  return library;
}
