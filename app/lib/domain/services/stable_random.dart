/// A tiny seeded random-number generator that gives the same numbers on phones, desktops and in the
/// browser (`dart:math`'s Random doesn't promise that), for anything that must match on every device
/// without syncing, such as the daily card and the daily trivia questions.
class StableRandom {
  /// Seeded from a string, e.g. `'trivia#easy#3'`.
  StableRandom(String seed) : _state = fnv1a(seed);

  int _state;

  /// mulberry32: small, fast and good enough for shuffling.
  int _next() {
    _state = (_state + 0x6d2b79f5) & 0xffffffff;
    var t = _state;
    t = _imul(t ^ (t >>> 15), t | 1);
    t ^= (t + _imul(t ^ (t >>> 7), t | 61)) & 0xffffffff;
    return (t ^ (t >>> 14)) & 0xffffffff;
  }

  /// 0 ≤ result < [max].
  int nextInt(int max) => (_next() / 0x100000000 * max).floor();

  /// A shuffled copy of [items] (Fisher–Yates).
  List<T> shuffled<T>(Iterable<T> items) {
    final list = List.of(items);
    for (var i = list.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final t = list[i];
      list[i] = list[j];
      list[j] = t;
    }
    return list;
  }

  /// 32-bit FNV-1a hash of the UTF-16 code units: stable everywhere, unlike String.hashCode.
  static int fnv1a(String s) {
    var h = 0x811c9dc5;
    for (final unit in s.codeUnits) {
      h ^= unit;
      h = _imul(h, 0x01000193);
    }
    return h;
  }
}

/// 32-bit multiply that stays exact when compiled to JavaScript (where ints are doubles).
int _imul(int a, int b) {
  final lo = (a & 0xffff) * b;
  final hi = (((a >>> 16) & 0xffff) * b) & 0xffff;
  return (lo + (hi << 16)) & 0xffffffff;
}
