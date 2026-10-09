import 'package:bamboozled/core/layout/breakpoints.dart';
import 'package:bamboozled/core/layout/compact_scale.dart';
import 'package:bamboozled/data/providers.dart';
import 'package:bamboozled/features/tasks/task_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// The screen size the pages are laid out for.
Size layoutSize(WidgetTester tester) => MediaQuery.sizeOf(tester.element(find.text('Do next')));

void main() {
  group('Compact layout on phone web', () {
    testWidgets('lays phones out larger and draws them smaller', (tester) async {
      final app = await TestApp.create();
      await app.pump(
        tester,
        size: const Size(390, 844),
        overrides: [compactPhoneLayoutProvider.overrideWithValue(true)],
      );
      final size = layoutSize(tester);
      expect(size.width, closeTo(390 / CompactScale.factor, 0.01));
      expect(size.height, closeTo(844 / CompactScale.factor, 0.01));
      // Still the phone layout, and drawn to fit the real screen.
      expect(Breakpoints.isPhone(tester.element(find.text('Do next'))), isTrue);
      final bottomRight = tester.getBottomRight(find.byType(NavigationBar));
      expect(bottomRight.dx, closeTo(390, 0.5));
      expect(bottomRight.dy, closeTo(844, 0.5));
      final title = tester.getBottomLeft(find.text('Do next')).dy - tester.getTopLeft(find.text('Do next')).dy;
      expect(title, closeTo(28 * CompactScale.factor, 0.5));
      await app.dispose(tester);
    });

    testWidgets('taps land where things are drawn, and sheets are scaled too', (tester) async {
      final app = await TestApp.create();
      await app.pump(
        tester,
        size: const Size(390, 844),
        overrides: [compactPhoneLayoutProvider.overrideWithValue(true)],
      );
      await tester.tap(find.byTooltip('Add task'));
      await TestApp.settle(tester);
      expect(find.byType(TaskEditor), findsOneWidget);
      expect(tester.getBottomRight(find.byType(TaskEditor)).dx, lessThanOrEqualTo(390.5));
      await tester.tap(find.text('Cancel'));
      await TestApp.settle(tester);
      expect(find.byType(TaskEditor), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('leaves tablets and desktops at full size', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, overrides: [compactPhoneLayoutProvider.overrideWithValue(true)]);
      expect(layoutSize(tester), const Size(1440, 1000));
      await app.dispose(tester);
    });

    testWidgets('leaves the installed apps at full size', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, size: const Size(390, 844));
      expect(layoutSize(tester), const Size(390, 844));
      await app.dispose(tester);
    });
  });
}
