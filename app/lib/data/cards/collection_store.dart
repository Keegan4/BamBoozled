import 'dart:convert';

import '../../domain/models/cards.dart';
import '../../domain/services/pack_roller.dart';
import '../../domain/services/stable_random.dart';
import '../local/app_database.dart';
import 'card_library.dart';

/// The last pack opened, kept so its overview can be shown again.
class OpenedPack {
  const OpenedPack(this.type, this.date, this.pulls);
  final PackType type;

  /// When it was opened (ISO 8601).
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

/// Free packs: one more every [PackTimer.every], and at most [PackTimer.max] waiting.
abstract final class PackTimer {
  static const every = Duration(hours: 2);
  static const max = 2;
}

/// The card collection, kept on this device in the settings table.
class CollectionState {
  const CollectionState({
    this.copies = const {},
    this.stored = PackTimer.max,
    this.refillFrom,
    this.opened = 0,
    this.packsSinceLegendary = 0,
    this.last,
  });

  /// card + finish key → copies owned.
  final Map<String, int> copies;

  /// Packs waiting as of [refillFrom] (a new collection starts full).
  final int stored;

  /// When the next pack started filling. Null while full.
  final DateTime? refillFrom;

  /// Packs opened so far, which numbers each pack (and picks its cards).
  final int opened;
  final int packsSinceLegendary;
  final OpenedPack? last;

  static const key = 'card_collection';

  /// Packs ready to open at [now]: [stored] plus one for each whole [PackTimer.every] since
  /// [refillFrom], up to [PackTimer.max].
  int packsAt(DateTime now) {
    if (stored >= PackTimer.max || refillFrom == null) return PackTimer.max;
    final earned = now.difference(refillFrom!).inMicroseconds ~/ PackTimer.every.inMicroseconds;
    return (stored + (earned < 0 ? 0 : earned)).clamp(0, PackTimer.max);
  }

  /// When the next pack arrives, or null when the store is full.
  DateTime? nextPackAt(DateTime now) {
    if (packsAt(now) >= PackTimer.max) return null;
    final earned = now.difference(refillFrom!).inMicroseconds ~/ PackTimer.every.inMicroseconds;
    return refillFrom!.add(PackTimer.every * ((earned < 0 ? 0 : earned) + 1));
  }

  /// The state after one pack is taken at [now] (there must be one).
  CollectionState _takePack(DateTime now) {
    final have = packsAt(now);
    assert(have > 0);
    if (have >= PackTimer.max) {
      // Was full: the timer starts now.
      return copyWith(stored: have - 1, refillFrom: now);
    }
    // Keep the time already spent filling the next one.
    final earned = now.difference(refillFrom!).inMicroseconds ~/ PackTimer.every.inMicroseconds;
    final from = refillFrom!.add(PackTimer.every * (earned < 0 ? 0 : earned));
    return copyWith(stored: have - 1, refillFrom: from);
  }

  int copiesOf(String cardId) {
    var n = 0;
    for (final e in copies.entries) {
      if (e.key.startsWith('$cardId|')) n += e.value;
    }
    return n;
  }

  int copiesIn(String cardId, Finish f) => copies[Pull.keyOf(cardId, f)] ?? 0;

  /// How many of [cards] have at least one copy.
  int ownedAmong(Iterable<CardDef> cards) => cards.where((c) => copiesOf(c.id) > 0).length;

  /// Whether every one of [cards] is owned (and there is at least one), e.g. a whole theme.
  bool ownsAll(Iterable<CardDef> cards) => cards.isNotEmpty && cards.every((c) => copiesOf(c.id) > 0);

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
      final from = j['refillFrom'] as int?;
      return CollectionState(
        copies: {for (final e in (j['copies'] as Map<String, dynamic>? ?? {}).entries) e.key: e.value as int},
        stored: j['stored'] as int? ?? PackTimer.max,
        refillFrom: from == null ? null : DateTime.fromMillisecondsSinceEpoch(from),
        opened: j['opened'] as int? ?? 0,
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
    'stored': stored,
    if (refillFrom != null) 'refillFrom': refillFrom!.millisecondsSinceEpoch,
    'opened': opened,
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
    int? stored,
    DateTime? refillFrom,
    int? opened,
    int? packsSinceLegendary,
    OpenedPack? last,
  }) => CollectionState(
    copies: copies ?? this.copies,
    stored: stored ?? this.stored,
    refillFrom: refillFrom ?? this.refillFrom,
    opened: opened ?? this.opened,
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

  /// Opens a waiting pack. The n-th pack is the same for the same [seed] on every device. Returns
  /// the cards, or an empty list if no pack is ready (or there are no cards).
  Future<List<Pull>> openPack(CardLibrary library, String seed, DateTime now) async {
    final state = await read();
    if (library.cards.isEmpty || state.packsAt(now) == 0) return const [];
    const type = PackType.bamboo;
    final number = state.opened + 1;
    final random = StableRandom('$seed#pack#$number');
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
      state
          ._takePack(now)
          .copyWith(
            copies: copies,
            opened: number,
            packsSinceLegendary: gotLegendary ? 0 : state.packsSinceLegendary + 1,
            last: OpenedPack(type, now.toIso8601String(), [for (final p in pulls) (p.key, p.newCard, p.newFinish)]),
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
