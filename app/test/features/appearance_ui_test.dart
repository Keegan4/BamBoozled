import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bamboozled/app.dart';
import 'package:bamboozled/core/theme/appearance.dart';
import 'package:bamboozled/core/theme/colors.dart';
import 'package:bamboozled/core/theme/panda_theme.dart';
import 'package:bamboozled/core/widgets/panda_mascot.dart';
import 'package:bamboozled/data/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// The brightness the app is showing, read from a widget on the page.
Brightness shownBrightness(WidgetTester tester) => Theme.of(tester.element(find.text('Settings').first)).brightness;

Future<String?> stored(WidgetTester tester, TestApp app) =>
    tester.runAsync<String?>(() => app.db.getSetting(Appearance.key));

void main() {
  group('Settings → Appearance', () {
    testWidgets('starts in light mode with all four choices', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, location: '/settings');
      expect(find.text('Appearance'), findsOneWidget);
      for (final label in ['Light', 'Dark', 'Match device', 'On a schedule']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(shownBrightness(tester), Brightness.light);
      expect(find.textContaining('Dark from'), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('choosing Dark switches the whole app to the dark palette', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, location: '/settings');
      await tester.tap(find.text('Dark'));
      await TestApp.settle(tester);
      await tester.pumpAndSettle();
      expect(shownBrightness(tester), Brightness.dark);
      final context = tester.element(find.text('Settings').first);
      expect(context.panda, PandaPalette.dark);
      expect(await stored(tester, app), 'dark;19:00;07:00');

      await tester.tap(find.text('Light'));
      await TestApp.settle(tester);
      await tester.pumpAndSettle();
      expect(shownBrightness(tester), Brightness.light);
      await app.dispose(tester);
    });

    testWidgets('Match device follows the device setting', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final app = await TestApp.create();
      await app.pump(tester, location: '/settings');
      expect(shownBrightness(tester), Brightness.light);
      await tester.tap(find.text('Match device'));
      await TestApp.settle(tester);
      await tester.pumpAndSettle();
      expect(shownBrightness(tester), Brightness.dark);
      await app.dispose(tester);
    });

    testWidgets('On a schedule is light in the morning and dark in the evening', (tester) async {
      final app = await TestApp.create();
      await app.db.setSetting(Appearance.key, 'scheduled;19:00;07:00');
      await app.pump(tester, location: '/settings'); // 9:00 am
      expect(shownBrightness(tester), Brightness.light);
      expect(find.text('Dark from 7:00 pm'), findsOneWidget);
      expect(find.text('Light from 7:00 am'), findsOneWidget);
      expect(find.text('Light now, until 7:00 pm.'), findsOneWidget);
      await app.dispose(tester);

      final evening = await TestApp.create();
      await evening.db.setSetting(Appearance.key, 'scheduled;19:00;07:00');
      await evening.pump(tester, location: '/settings', now: DateTime(2026, 10, 8, 20, 30));
      await tester.pumpAndSettle();
      expect(shownBrightness(tester), Brightness.dark);
      expect(find.text('Dark now, until 7:00 am.'), findsOneWidget);
      await evening.dispose(tester);
    });

    testWidgets('the switch-over times can be changed', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, location: '/settings');
      await tester.tap(find.text('On a schedule'));
      await TestApp.settle(tester);
      expect(await stored(tester, app), 'scheduled;19:00;07:00');

      await tester.tap(find.text('Dark from 7:00 pm'));
      await tester.pumpAndSettle();
      expect(find.text('Turn dark at'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '8');
      await tester.tap(find.text('OK'));
      await TestApp.settle(tester);
      expect(find.text('Dark from 8:00 pm'), findsOneWidget);
      expect(await stored(tester, app), 'scheduled;20:00;07:00');

      await tester.tap(find.text('Light from 7:00 am'));
      await tester.pumpAndSettle();
      expect(find.text('Turn light at'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await TestApp.settle(tester);
      expect(await stored(tester, app), 'scheduled;20:00;07:00');
      await app.dispose(tester);
    });

    testWidgets('says so when both times are the same', (tester) async {
      final app = await TestApp.create();
      await app.db.setSetting(Appearance.key, 'scheduled;08:00;08:00');
      await app.pump(tester, location: '/settings');
      expect(find.text('The two times are the same, so the app stays light.'), findsOneWidget);
      await app.dispose(tester);
    });
  });

  group('Dark mode screens', () {
    for (final (name, size) in [('desktop', const Size(1440, 1000)), ('phone', const Size(412, 915))]) {
      testWidgets('the $name welcome page draws in dark mode', (tester) async {
        final app = await TestApp.create();
        await app.db.setSetting(Appearance.key, 'dark;19:00;07:00');
        await app.pump(tester, size: size);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(Theme.of(tester.element(find.text('Do next'))).brightness, Brightness.dark);
        await app.dispose(tester);
      });
    }

    testWidgets('the theme mode provider ignores the clock unless on a schedule', (tester) async {
      final app = await TestApp.create();
      await app.db.setSetting(Appearance.key, 'device;19:00;07:00');
      await app.pump(tester, now: DateTime(2026, 10, 8, 23));
      final container = ProviderScope.containerOf(tester.element(find.byType(BamBoozledApp)));
      expect(container.read(themeModeProvider), ThemeMode.system);
      await app.dispose(tester);
    });
  });

  testWidgets('the panda looks exactly the same in light and dark mode', (tester) async {
    Future<Uint8List> render(Brightness b) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildPandaTheme(brightness: b),
          home: Center(
            child: RepaintBoundary(key: key, child: const PandaMascot(size: 96)),
          ),
        ),
      );
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      return (await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        return bytes!.buffer.asUint8List();
      }))!;
    }

    final light = await render(Brightness.light);
    final dark = await render(Brightness.dark);
    expect(dark, light);
  });
}
