import 'dart:math' as math;

import 'package:bamboozled/core/layout/breakpoints.dart';
import 'package:bamboozled/core/theme/colors.dart';
import 'package:bamboozled/core/theme/panda_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG contrast ratio between two colours.
double _contrast(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final l1 = lum(a), l2 = lum(b);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

void main() {
  group('Panda colours', () {
    test('body text on every background meets WCAG AA (4.5:1)', () {
      for (final bg in [PandaColors.rice, PandaColors.surface, PandaColors.bambooTint, PandaColors.overdueTint]) {
        expect(_contrast(PandaColors.ink, bg), greaterThanOrEqualTo(4.5), reason: 'ink on $bg');
      }
      expect(_contrast(PandaColors.muted, PandaColors.surface), greaterThanOrEqualTo(4.5), reason: 'muted on white');
      expect(_contrast(PandaColors.muted, PandaColors.rice), greaterThanOrEqualTo(4.5), reason: 'muted on rice');
      expect(_contrast(PandaColors.bambooDark, PandaColors.bambooTint), greaterThanOrEqualTo(4.5));
    });

    test('overdue red is readable as large/bold text on white (3:1)', () {
      expect(_contrast(PandaColors.overdue, PandaColors.surface), greaterThanOrEqualTo(3));
    });

    test('category colours are all distinct', () {
      final values = PandaColors.categoryChoices.values.toSet();
      expect(values.length, PandaColors.categoryChoices.length);
    });

    test('category choices all have friendly names', () {
      expect(PandaColors.categoryChoices.keys, containsAll(['Sky', 'Honey', 'Blush', 'Lavender', 'Mint']));
    });
  });

  group('Dark palette', () {
    const d = PandaPalette.dark;

    test('matches the dark mode mockup', () {
      expect(d.rice, const Color(0xFF121412));
      expect(d.surface, const Color(0xFF1B1E1B));
      expect(d.ink, const Color(0xFFEDEBE4));
      expect(d.line, const Color(0xFF2D312C));
      expect(d.muted, const Color(0xFFA2A69E));
      expect(d.bamboo, const Color(0xFF8CC490));
      expect(d.bambooDark, const Color(0xFFA9D8AC));
      expect(d.bambooTint, const Color(0xFF223426));
      expect(d.overdue, const Color(0xFFF28B8B));
      expect(d.overdueTint, const Color(0xFF3B2323));
    });

    test('the light palette is the original Panda colours', () {
      const l = PandaPalette.light;
      expect(
        [l.ink, l.rice, l.surface, l.muted, l.line, l.bamboo, l.bambooDark, l.bambooTint, l.overdue],
        [
          PandaColors.ink,
          PandaColors.rice,
          PandaColors.surface,
          PandaColors.muted,
          PandaColors.line,
          PandaColors.bamboo,
          PandaColors.bambooDark,
          PandaColors.bambooTint,
          PandaColors.overdue,
        ],
      );
    });

    test('body text on every dark background meets WCAG AA (4.5:1)', () {
      for (final bg in [d.rice, d.surface, d.bambooTint, d.overdueTint]) {
        expect(_contrast(d.ink, bg), greaterThanOrEqualTo(4.5), reason: 'ink on $bg');
      }
      for (final bg in [d.rice, d.surface]) {
        expect(_contrast(d.muted, bg), greaterThanOrEqualTo(4.5), reason: 'muted on $bg');
        expect(_contrast(d.overdue, bg), greaterThanOrEqualTo(4.5), reason: 'overdue on $bg');
      }
      expect(_contrast(d.bambooDark, d.bambooTint), greaterThanOrEqualTo(4.5));
      expect(_contrast(d.overdue, d.overdueTint), greaterThanOrEqualTo(4.5));
    });

    test('button text on bamboo is readable in both modes', () {
      for (final p in [PandaPalette.light, d]) {
        expect(_contrast(p.onBamboo, p.bamboo), greaterThanOrEqualTo(4.5));
      }
    });

    test('blends smoothly between light and dark', () {
      expect(PandaPalette.light.lerp(d, 0), PandaPalette.light.copyWith());
      expect(PandaPalette.light.lerp(d, 1).rice, d.rice);
      expect(PandaPalette.light.lerp(null, 0.5), PandaPalette.light);
      expect(d.copyWith(ink: PandaColors.ink).ink, PandaColors.ink);
    });
  });

  group('Panda theme', () {
    test('dark theme uses the dark palette on the same type and shapes', () {
      final dark = buildPandaTheme(brightness: Brightness.dark);
      expect(dark.brightness, Brightness.dark);
      expect(dark.scaffoldBackgroundColor, PandaPalette.dark.rice);
      expect(dark.extension<PandaPalette>(), PandaPalette.dark);
      expect(dark.colorScheme.primary, PandaPalette.dark.bamboo);
      expect(dark.textTheme.bodyLarge!.color, PandaPalette.dark.ink);
      expect(dark.textTheme.bodyLarge!.fontFamily, 'Nunito');
      expect(buildPandaTheme().extension<PandaPalette>(), PandaPalette.light);
    });

    testWidgets('context.panda falls back to the light palette outside the app theme', (tester) async {
      late PandaPalette found;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            found = context.panda;
            return const SizedBox();
          },
        ),
      );
      expect(found, PandaPalette.light);
    });

    test('uses Nunito and the rice background', () {
      final theme = buildPandaTheme();
      expect(theme.scaffoldBackgroundColor, PandaColors.rice);
      expect(theme.textTheme.bodyLarge!.fontFamily, 'Nunito');
      expect(theme.useMaterial3, isTrue);
    });

    test('body text is at least 16px and captions at least 14px', () {
      expect(PandaText.body.fontSize, greaterThanOrEqualTo(16));
      expect(PandaText.bodyStrong.fontSize, greaterThanOrEqualTo(16));
      expect(PandaText.caption.fontSize, greaterThanOrEqualTo(14));
    });

    test('buttons are at least 48px tall', () {
      final theme = buildPandaTheme();
      expect(theme.filledButtonTheme.style!.minimumSize!.resolve({})!.height, greaterThanOrEqualTo(48));
      expect(theme.outlinedButtonTheme.style!.minimumSize!.resolve({})!.height, greaterThanOrEqualTo(48));
      expect(PandaSizes.minTouch, greaterThanOrEqualTo(48));
    });
  });

  group('Breakpoints', () {
    Future<List<bool>> probe(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late List<bool> out;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            out = [Breakpoints.isPhone(context), Breakpoints.isDesktop(context)];
            return const SizedBox();
          },
        ),
      );
      return out;
    }

    testWidgets('412 is a phone', (tester) async => expect(await probe(tester, 412), [true, false]));
    testWidgets('599 is still a phone', (tester) async => expect(await probe(tester, 599), [true, false]));
    testWidgets('600 is a tablet', (tester) async => expect(await probe(tester, 600), [false, false]));
    testWidgets('1099 is still a tablet', (tester) async => expect(await probe(tester, 1099), [false, false]));
    testWidgets('1100 is a desktop', (tester) async => expect(await probe(tester, 1100), [false, true]));
    testWidgets('1440 is a desktop', (tester) async => expect(await probe(tester, 1440), [false, true]));
  });
}
