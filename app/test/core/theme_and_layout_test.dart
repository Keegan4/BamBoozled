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

  group('Panda theme', () {
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
