import 'stable_random.dart';

/// Chooses the card for a day. Pure and deterministic, so the same person gets the same card on
/// every device without anything being synced:
///
/// * the cards are shuffled into an order that depends only on the person (the [seed]) and a cycle
///   number; one card is shown a day, and a cycle lasts as many days as there are cards, so no card
///   repeats until all have been seen, then a new shuffle starts;
/// * the shuffle uses [StableRandom] (not `dart:math`), so it gives the same answer on phones,
///   desktops and in the browser.
///
/// Adding cards changes the cycle length, so the order is reshuffled from then on.
abstract final class DailyNotePicker {
  /// Day 0. Any fixed date works; it only has to never change.
  static final _epoch = DateTime.utc(2026, 1, 1);

  /// Whole days from the epoch to [date]'s calendar day (local date, counted in UTC so daylight
  /// saving changes can't make a day 23 or 25 hours long).
  static int dayIndex(DateTime date) => DateTime.utc(date.year, date.month, date.day).difference(_epoch).inDays;

  /// The id of the card for [date], or null if there are no cards.
  static String? pick(Iterable<String> ids, String seed, DateTime date) {
    final sorted = ids.toSet().toList()..sort();
    if (sorted.isEmpty) return null;
    final n = sorted.length;
    final day = dayIndex(date);
    final position = day % n; // Dart's % is never negative for a positive divisor
    final cycle = (day - position) ~/ n;
    return orderFor(sorted, seed, cycle)[position];
  }

  /// The shuffled order of [sortedIds] for one cycle. A new cycle never starts with the card the
  /// previous one ended on, so the same card is never shown two days running.
  static List<String> orderFor(List<String> sortedIds, String seed, int cycle) {
    if (sortedIds.length == 2) {
      // Only two cards: keep alternating (a fresh shuffle would repeat one half the time).
      return StableRandom.fnv1a(seed).isEven ? List.of(sortedIds) : sortedIds.reversed.toList();
    }
    final order = _shuffled(sortedIds, seed, cycle);
    if (order.length > 2 && order.first == _shuffled(sortedIds, seed, cycle - 1).last) {
      final t = order[0];
      order[0] = order[1];
      order[1] = t;
    }
    return order;
  }

  static List<String> _shuffled(List<String> sortedIds, String seed, int cycle) =>
      StableRandom('$seed#$cycle').shuffled(sortedIds);
}
