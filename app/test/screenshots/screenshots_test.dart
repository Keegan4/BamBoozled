// Renders the welcome page with real fonts to PNG files in design/app-screenshots/.
// Skipped by default; run with:
//
//   SCREENSHOTS=1 flutter test --update-goldens test/screenshots
import 'dart:io';

import 'package:bamboozled/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Nunito is loaded for every test by flutter_test_config.dart; screenshots also need the icon font.
Future<void> _loadIconFont() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
  final bytes = await File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes();
  await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(bytes)))).load();
}

void main() {
  final enabled = Platform.environment['SCREENSHOTS'] == '1';

  setUpAll(() async {
    if (enabled) await _loadIconFont();
  });
  // Draw real shadows (tests replace them with black outlines by default).
  void shot(String name, Future<void> Function(WidgetTester) body) => testWidgets(name, skip: !enabled, (tester) async {
    debugDisableShadows = false;
    try {
      await body(tester);
    } finally {
      debugDisableShadows = true;
    }
  });

  for (final (name, size) in [('desktop-welcome', const Size(1440, 1000)), ('android-welcome', const Size(412, 915))]) {
    shot(name, (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: size);
      await expectLater(find.byType(BamBoozledApp), matchesGoldenFile('../../../design/app-screenshots/$name.png'));
      await app.dispose(tester);
    });
  }

  shot('android-empty-state', (tester) async {
    final app = await TestApp.create(withSampleTasks: false);
    await app.pump(tester, size: const Size(412, 915));
    await expectLater(
      find.byType(BamBoozledApp),
      matchesGoldenFile('../../../design/app-screenshots/android-empty-state.png'),
    );
    await app.dispose(tester);
  });

  for (final (name, size) in [
    ('desktop-add-task', const Size(1440, 1000)),
    ('android-add-task', const Size(412, 915)),
  ]) {
    shot(name, (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: size);
      await tester.tap(
        find.byTooltip('Add task').evaluate().isNotEmpty ? find.byTooltip('Add task') : find.text('Add task'),
      );
      await TestApp.settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'e.g. Mark 3A essays'), 'Mark 3A essays');
      await TestApp.settle(tester);
      await expectLater(find.byType(BamBoozledApp), matchesGoldenFile('../../../design/app-screenshots/$name.png'));
      await app.dispose(tester);
    });
  }
}
