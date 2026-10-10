import 'dart:ui' show PointerDeviceKind;

import 'package:bamboozled/domain/models/cards.dart';
import 'package:bamboozled/features/notes/widgets/collectible_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CardDef card(Rarity r, {String? artist = 'Ms Tan'}) => CardDef(
  id: 'bamboo-grove',
  number: 7,
  name: 'Bamboo Grove',
  rarity: r,
  photo: 'assets/cards/bamboo-grove.jpg',
  text: 'Take a proper lunch break today.',
  artist: artist,
);

void main() {
  testWidgets('every finish and rarity draws without errors', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          child: Wrap(
            children: [
              for (final f in Finish.values)
                for (final r in Rarity.values) CollectibleCard(card: card(r), finish: f, width: 90),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(CollectibleCard), findsNWidgets(Finish.values.length * Rarity.values.length));
    expect(find.text('#007'), findsWidgets);
    expect(find.text('Ms Tan'), findsWidgets, reason: 'signed cards carry the artist');
    expect(find.text('Holo'), findsWidgets, reason: 'the finish is named at the foot');
  });

  testWidgets('it describes itself to screen readers', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: CollectibleCard(card: card(Rarity.epic), finish: Finish.gold, width: 200),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Bamboo Grove, Epic, Gold. Take a proper lunch break today.'), findsOneWidget);
  });

  testWidgets('an interactive card tilts toward the pointer and settles back', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: CollectibleCard(
            card: card(Rarity.legendary, artist: null),
            finish: Finish.holo,
            width: 200,
            interactive: true,
          ),
        ),
      ),
    );
    Matrix4 tilt() =>
        tester.widgetList<Transform>(find.byType(Transform)).firstWhere((t) => t.transform.entry(3, 2) != 0).transform;
    expect(tilt().isIdentity(), isFalse, reason: 'perspective is always set');
    final flat = tilt().clone();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.byType(CollectibleCard)));
    await mouse.moveTo(tester.getTopLeft(find.byType(CollectibleCard)) + const Offset(10, 10));
    await tester.pump();
    expect(tilt(), isNot(flat));
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(tilt(), flat, reason: 'leaving resets it');
    await mouse.removePointer();

    final finger = await tester.startGesture(tester.getCenter(find.byType(CollectibleCard)));
    await finger.moveBy(const Offset(40, 40));
    await tester.pump();
    expect(tilt(), isNot(flat));
    await finger.up();
    await tester.pump();
    expect(tilt(), flat);
  });
}
