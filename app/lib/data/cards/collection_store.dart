import 'dart:convert';

import '../../domain/models/cards.dart';
import '../../domain/services/pack_roller.dart';
import '../../domain/services/stable_random.dart';
import '../local/app_database.dart';
import 'card_library.dart';

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The last pack opened, kept so its overview can be shown again.
class OpenedPack {
  const OpenedPack(this.type, this.date, this.pulls);
  final PackType type;
  final String date;

  /// (card + finish key, new card, new finish)
  final List<(String, bool, bool)> pulls;

  List<Pull> resolve(CardLibrary library) => [
    for (final (key, newCard, newFinish) in pulls)
      if (_split(key) case (final id, final finish)?)
        if (library.byId(id) case final card?) Pull(card, finish, newCard: newCard, newFinish: newFinish),
  ];
}

(String, Finish)? _split(String key) {
  final i = key.lastIndexOf('|');
  if (i < 0) return null;
  final f = Finish.fromKey(key.substring(i + 1));
  return f == null ? null : (key.substring(0, i), f);
}

/// The card collection, kept on this device in the settings table.
class CollectionState {
  const CollectionState({this.copies = const {}, this.dailyOpenedOn, this.packsSinceLegendary = 0, this.last});

  /// card + finish key → copies owned.
  final Map<String, int> copies;

  /// Date key of the last day the free daily pack was opened.
  final String? dailyOpenedOn;
  final int packsSinceLegendary;
  final OpenedPack? last;

  static const key = 'card_collection';

  bool dailyAvailable(DateTime today) => dailyOpenedOn != dateKey(today);

  int copiesOf(String cardId) {
    var n = 0;
    for (final e in copies.entries) {
      if (e.key.startsWith('$cardId|')) n += e.value;
    }
    return n;
  }

  int copiesIn(String cardId, Finish f) => copies[Pull.keyOf(cardId, f)] ?? 0;

  /// The finishes owned for a card, showiest first.
  List<Finish> finishesOf(String cardId) => [
    for (final f in Finish.showiest)
      if (copiesIn(cardId, f) > 0) f,
  ];

  static CollectionState fromSetting(String? value) {
    if (value == null) return const CollectionState();
    try {
      final j = jsonDecode(value) as Map<String, dynamic>;
      final last = j['last'] as Map<String, dynamic>?;
      return CollectionState(
        copies: {for (final e in (j['copies'] as Map<String, dynamic>? ?? {}).entries) e.key: e.value as int},
        dailyOpenedOn: j['daily'] as String?,
        packsSinceLegendary: j['sinceLegendary'] as int? ?? 0,
        last: last == null
            ? null
            : OpenedPack(PackType.values.asNameMap()[last['type']] ?? PackType.bamboo, last['date'] as String, [
                for (final p in last['pulls'] as List<dynamic>)
                  (p['k'] as String, p['newCard'] == true, p['newFinish'] == true),
              ]),
      );
    } catch (_) {
      return const CollectionState();
    }
  }

  String toSetting() => jsonEncode({
    'copies': copies,
    'daily': dailyOpenedOn,
    'sinceLegendary': packsSinceLegendary,
    if (last != null)
      'last': {
        'type': last!.type.name,
        'date': last!.date,
        'pulls': [
          for (final (k, newCard, newFinish) in last!.pulls) {'k': k, 'newCard': newCard, 'newFinish': newFinish},
        ],
      },
  });

  CollectionState copyWith({
    Map<String, int>? copies,
    String? dailyOpenedOn,
    int? packsSinceLegendary,
    OpenedPack? last,
  }) => CollectionState(
    copies: copies ?? this.copies,
    dailyOpenedOn: dailyOpenedOn ?? this.dailyOpenedOn,
    packsSinceLegendary: packsSinceLegendary ?? this.packsSinceLegendary,
    last: last ?? this.last,
  );
}

class CollectionStore {
  CollectionStore(this.db);
  final AppDatabase db;

  Stream<CollectionState> watch() => db.watchSetting(CollectionState.key).map(CollectionState.fromSetting);

  Future<CollectionState> read() async => CollectionState.fromSetting(await db.getSetting(CollectionState.key));

  Future<void> _save(CollectionState s) => db.setSetting(CollectionState.key, s.toSetting());

  /// Opens today's free pack. It is the same for the same [seed] and day on every device. Returns
  /// the cards, or an empty list if today's pack is already open (or there are no cards).
  Future<List<Pull>> openDaily(CardLibrary library, String seed, DateTime today) async {
    final state = await read();
    if (library.cards.isEmpty || !state.dailyAvailable(today)) return const [];
    const type = PackType.bamboo;
    final random = StableRandom('$seed#daily#${dateKey(today)}');
    final rolled = PackRoller.roll(
      library.cards,
      type,
      random,
      pityDue: state.packsSinceLegendary >= PackRoller.pityAfter - 1,
    );
    final copies = Map.of(state.copies);
    final pulls = <Pull>[];
    for (final (card, finish) in rolled) {
      final hadCard = copies.keys.any((k) => k.startsWith('${card.id}|') && copies[k]! > 0);
      final key = Pull.keyOf(card.id, finish);
      final hadFinish = (copies[key] ?? 0) > 0;
      copies[key] = (copies[key] ?? 0) + 1;
      pulls.add(Pull(card, finish, newCard: !hadCard, newFinish: hadCard && !hadFinish));
    }
    final gotLegendary = rolled.any((p) => p.$1.rarity == Rarity.legendary);
    await _save(
      state.copyWith(
        copies: copies,
        dailyOpenedOn: dateKey(today),
        packsSinceLegendary: gotLegendary ? 0 : state.packsSinceLegendary + 1,
        last: OpenedPack(type, dateKey(today), [for (final p in pulls) (p.key, p.newCard, p.newFinish)]),
      ),
    );
    return pulls;
  }

  /// An id for this install, used to shuffle packs when not signed in. Made once, then kept.
  Future<String> installId(String Function() create) async {
    const key = 'install_id';
    final existing = await db.getSetting(key);
    if (existing != null) return existing;
    final id = create();
    await db.setSetting(key, id);
    return id;
  }
}
