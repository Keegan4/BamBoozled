/// A small random-number generator that gives the same numbers for the same seed on phones,
/// desktops and in the browser (unlike `dart:math`'s Random, whose sequence isn't guaranteed).
/// Used so the same person gets the same daily pack on every device.
class SeededRandom {
  SeededRandom(String seed) : _state = fnv1a(seed);

  int _state;

  /// 32-bit FNV-1a hash of the UTF-16 code units: stable everywhere, unlike String.hashCode.
  static int fnv1a(String s) {
    var h = 0x811c9dc5;
    for (final unit in s.codeUnits) {
      h ^= unit;
      h = _imul(h, 0x01000193);
    }
    return h;
  }

  /// mulberry32: tiny, fast and good enough for games.
  int _next() {
    _state = (_state + 0x6d2b79f5) & 0xffffffff;
    var t = _state;
    t = _imul(t ^ (t >>> 15), t | 1);
    t ^= (t + _imul(t ^ (t >>> 7), t | 61)) & 0xffffffff;
    return (t ^ (t >>> 14)) & 0xffffffff;
  }

  /// 0 ≤ result < 1.
  double nextDouble() => _next() / 0x100000000;

  /// 0 ≤ result < [max].
  int nextInt(int max) => (nextDouble() * max).floor();

  /// Picks a key with probability proportional to its weight. Zero weights are never picked.
  T pick<T>(Map<T, double> weights) {
    final entries = weights.entries.where((e) => e.value > 0).toList();
    final total = entries.fold<double>(0, (s, e) => s + e.value);
    var r = nextDouble() * total;
    for (final e in entries) {
      r -= e.value;
      if (r < 0) return e.key;
    }
    return entries.last.key;
  }
}

/// 32-bit multiply that stays exact when compiled to JavaScript (where ints are doubles).
int _imul(int a, int b) {
  final lo = (a & 0xffff) * b;
  final hi = (((a >>> 16) & 0xffff) * b) & 0xffff;
  return (lo + (hi << 16)) & 0xffffffff;
}
