// Fails if test coverage is below a minimum.
//
//   flutter test --coverage
//   dart run tool/check_coverage.dart 90
//
// Generated code is left out: it is exercised by the tests but not worth measuring.
import 'dart:io';

const _ignored = [
  '.g.dart', // drift / build_runner output
  'lib/data/local/tables.dart', // table definitions, only read by the generated code
];

void main(List<String> args) {
  final minimum = args.isEmpty ? 90.0 : double.parse(args.first);
  final file = File('coverage/lcov.info');
  if (!file.existsSync()) {
    stderr.writeln('coverage/lcov.info not found. Run `flutter test --coverage` first.');
    exit(2);
  }

  final perFile = <String, (int hit, int total)>{};
  String? current;
  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      current = line.substring(3).replaceAll(r'\', '/');
      perFile[current] = (0, 0);
    } else if (line.startsWith('DA:') && current != null) {
      final hits = int.parse(line.split(',')[1]);
      final (hit, total) = perFile[current]!;
      perFile[current] = (hit + (hits > 0 ? 1 : 0), total + 1);
    }
  }

  var hit = 0, total = 0;
  final rows = <String>[];
  for (final MapEntry(:key, :value) in perFile.entries) {
    if (_ignored.any(key.endsWith)) continue;
    hit += value.$1;
    total += value.$2;
    if (value.$1 < value.$2) {
      rows.add('${(100 * value.$1 / value.$2).toStringAsFixed(1).padLeft(5)}%  ${value.$1}/${value.$2}  $key');
    }
  }
  rows.sort();
  if (rows.isNotEmpty) {
    stdout.writeln('Files with uncovered lines (lowest first):');
    rows.forEach(stdout.writeln);
  }

  final percent = total == 0 ? 0.0 : 100 * hit / total;
  stdout.writeln('\nCoverage: ${percent.toStringAsFixed(1)}% ($hit of $total lines), minimum $minimum%');
  if (percent < minimum) {
    stderr.writeln('Coverage is below the minimum.');
    exit(1);
  }
}
