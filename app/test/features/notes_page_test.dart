import 'dart:ui' show ImageFilter, PointerDeviceKind;

import 'package:bamboozled/data/cards/card_library.dart';
import 'package:bamboozled/data/cards/collection_store.dart';
import 'package:bamboozled/data/providers.dart';
import 'package:bamboozled/domain/models/cards.dart';
import 'package:bamboozled/features/notes/binder_page.dart';
import 'package:bamboozled/features/notes/widgets/booster_pack.dart';
import 'package:bamboozled/features/notes/widgets/card_detail.dart';
import 'package:bamboozled/features/notes/widgets/collectible_card.dart';
import 'package:bamboozled/features/notes/widgets/pack_help.dart';
import 'package:bamboozled/features/notes/widgets/rarity_fanfare.dart';
import 'package:bamboozled/features/notes/widgets/pack_opening.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

const phone = Size(412, 915);

/// The pack in front (a second waiting pack peeks out behind it, but can't be touched).
final pack = find.byKey(const ValueKey('booster-pack')).hitTestable();
final stackTop = find.byKey(const ValueKey('stack-top'));

/// Lets drift (real async), the pack's animations and the overlay all finish.
Future<void> settleFully(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Slides across the top of the pack, [fraction] of the way.
Future<void> slide(WidgetTester tester, {double fraction = 1}) async {
  final w = tester.getSize(pack).width;
  await tester.dragFrom(tester.getTopLeft(pack) + const Offset(6, 20), Offset(w * fraction, 0));
  await settleFully(tester);
}

String count(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('stack-count'))).data!;

Future<CollectionState> collection(TestApp app) async =>
    CollectionState.fromSetting(await app.db.getSetting(CollectionState.key));

Future<void> own(TestApp app, Map<String, int> copies) =>
    app.db.setSetting(CollectionState.key, CollectionState(copies: copies).toSetting());

void main() {
  group('card packs', () {
    testWidgets('starts sealed, with the binder empty', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, location: '/notes');
      expect(find.text('Card packs'), findsOneWidget);
      expect(pack, findsOneWidget);
      expect(find.byKey(const ValueKey('spare-pack')), findsOneWidget);
      expect(find.text('2 packs ready. Slide across the top to tear one open.'), findsOneWidget);
      expect(find.text('2 of 2 packs ready'), findsOneWidget);
      expect(find.text('See your last pack'), findsNothing);
      expect(find.text('0 of 12 cards collected'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Bamboo Booster, sealed')), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('a short slide springs back and leaves it sealed', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, location: '/notes');
      await slide(tester, fraction: 0.4);
      expect(pack, findsOneWidget);
      expect(find.byType(PackOpening), findsNothing);
      expect((await tester.runAsync(() => collection(app)))!.copies, isEmpty);
      await app.dispose(tester);
    });

    testWidgets('a quick flick opens it even if it does not reach the end', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, location: '/notes');
      await tester.flingFrom(tester.getTopLeft(pack) + const Offset(6, 20), const Offset(140, 0), 2000);
      await settleFully(tester);
      expect(find.byType(PackOpening), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('sliding across tears it open into a face-up stack over the blurred app', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, location: '/notes');
      await slide(tester);

      expect(find.byType(PackOpening), findsOneWidget);
      final blur = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(blur.filter, ImageFilter.blur(sigmaX: 12, sigmaY: 12));
      expect(count(tester), '1 / 7');
      expect(find.byKey(const ValueKey('pull-0')), findsOneWidget);

      final saved = (await tester.runAsync(() => collection(app)))!;
      expect(saved.copies.values.fold<int>(0, (a, b) => a + b), 7);
      expect(saved.opened, 1);
      expect(saved.packsAt(testNow), 1);

      // Tap, swipe either way, or use the keyboard: each slides the top card off.
      await tester.tap(stackTop);
      await settleFully(tester);
      expect(count(tester), '2 / 7');
      await tester.drag(stackTop, const Offset(-200, 0));
      await settleFully(tester);
      expect(count(tester), '3 / 7');
      await tester.drag(stackTop, const Offset(200, 0));
      await settleFully(tester);
      expect(count(tester), '4 / 7');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await settleFully(tester);
      expect(count(tester), '5 / 7');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await settleFully(tester);
      expect(count(tester), '6 / 7');

      // A small nudge isn't a swipe.
      await tester.drag(stackTop, const Offset(30, 0));
      await settleFully(tester);
      expect(count(tester), '6 / 7');

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await settleFully(tester);
      expect(count(tester), '7 / 7');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settleFully(tester);

      // Then the overview, with the new ones marked.
      expect(find.text('Your pack'), findsOneWidget);
      final pulls = saved.last!.pulls;
      expect(find.text('New'), findsNWidgets(pulls.where((p) => p.$2).length));
      expect(find.text('New finish'), findsNWidgets(pulls.where((p) => p.$3).length));
      for (var i = 0; i < 7; i++) {
        expect(find.byKey(ValueKey('overview-$i')), findsOneWidget);
      }

      await tester.tap(find.text('Done'));
      await settleFully(tester);
      expect(find.byType(PackOpening), findsNothing);
      // One pack is left, and the next starts filling.
      expect(pack, findsOneWidget);
      expect(find.byKey(const ValueKey('spare-pack')), findsNothing);
      expect(find.text('1 pack ready, another in 2 h. Slide across the top to tear it open.'), findsOneWidget);
      expect(find.text('See your last pack'), findsOneWidget);

      // The second pack starts sealed and opens the same way.
      await slide(tester);
      expect(count(tester), '1 / 7');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleFully(tester);
      expect(pack, findsNothing);
      expect(find.text('No packs ready. The next one arrives in 2 h.'), findsOneWidget);
      expect(find.byKey(const ValueKey('last-fan')), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the pack is the same for the same person on another device', (tester) async {
      Future<List<String>> openOnce() async {
        final app = await TestApp.create(withSampleTasks: false);
        await app.pump(tester, location: '/notes', overrides: [packSeedProvider.overrideWith((ref) async => 'user-1')]);
        await slide(tester);
        final keys = (await tester.runAsync(() => collection(app)))!.last!.pulls.map((p) => p.$1).toList();
        await app.dispose(tester);
        return keys;
      }

      expect(await openOnce(), await openOnce());
    });

    testWidgets('Enter opens a focused pack, and Escape closes the stack', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, location: '/notes');
      await tester.tap(pack);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settleFully(tester);
      expect(find.byType(PackOpening), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleFully(tester);
      expect(find.byType(PackOpening), findsNothing);
      expect(find.text('See your last pack'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the last pack can be seen again, looked at closely, and lead to the binder', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, size: phone, location: '/notes');
      await slide(tester);
      await tester.tap(find.byTooltip('Close'));
      await settleFully(tester);

      await tester.tap(find.text('See your last pack'));
      await settleFully(tester);
      expect(find.text('Your pack'), findsOneWidget, reason: 'goes straight to the overview');
      expect(find.byKey(const ValueKey('stack-count')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('overview-0')));
      await settleFully(tester);
      expect(find.byType(CardDetail), findsOneWidget);
      expect(find.byKey(const ValueKey('card-lore')), findsOneWidget);
      await tester.tap(find.byTooltip('Close').last);
      await settleFully(tester);
      expect(find.byType(CardDetail), findsNothing);

      await tester.ensureVisible(find.text('See binder'));
      await tester.tap(find.text('See binder'));
      await settleFully(tester);
      expect(find.byType(BinderPage), findsOneWidget);
      expect(find.byType(PackOpening), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('once both packs are open, the fan of the last one opens its overview', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, location: '/notes');
      for (var i = 0; i < 2; i++) {
        await slide(tester);
        await tester.tapAt(const Offset(4, 4));
        await settleFully(tester);
        expect(find.byType(PackOpening), findsNothing, reason: 'tapping the blurred background closes it');
      }
      await tester.tap(find.byKey(const ValueKey('last-fan')));
      await settleFully(tester);
      expect(find.text('Your pack'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('a pack comes back after 2 hours', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.db.setSetting(
        CollectionState.key,
        CollectionState(stored: 0, refillFrom: testNow.subtract(const Duration(hours: 2, minutes: 10))).toSetting(),
      );
      await app.pump(tester, location: '/notes');
      expect(pack, findsOneWidget);
      expect(find.text('1 of 2 packs ready'), findsOneWidget);
      expect(find.text('1 pack ready, another in 1 h 50 min. Slide across the top to tear it open.'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the countdown reads naturally', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.db.setSetting(CollectionState.key, CollectionState(stored: 0, refillFrom: testNow).toSetting());
      for (final (time, text) in [
        (testNow.add(const Duration(minutes: 119, seconds: 30)), 'in a minute'),
        (testNow.add(const Duration(minutes: 80)), 'in 40 min'),
        (testNow.add(const Duration(minutes: 30)), 'in 1 h 30 min'),
      ]) {
        await app.pump(tester, location: '/notes', now: time);
        expect(find.text('No packs ready. The next one arrives $text.'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }
      await app.dispose(tester);
    });

    testWidgets('with reduced motion everything still works, without the animations', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, location: '/notes');
      await slide(tester, fraction: 0.3);
      expect(pack, findsOneWidget);
      await slide(tester);
      expect(count(tester), '1 / 7');
      await tester.tap(stackTop);
      await settleFully(tester);
      expect(count(tester), '2 / 7');
      final card = find.byKey(const ValueKey('pull-1'));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: tester.getCenter(card));
      await gesture.moveTo(tester.getTopLeft(card) + const Offset(10, 10));
      await tester.pump();
      final tilts = tester
          .widgetList<Transform>(find.descendant(of: card, matching: find.byType(Transform)))
          .where((t) => t.transform.entry(3, 2) != 0);
      expect(tilts, isEmpty, reason: 'no tilt');
      await gesture.removePointer();
      await app.dispose(tester);
    });

    testWidgets('with no cards there is a friendly note instead', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(
        tester,
        location: '/notes',
        overrides: [cardLibraryProvider.overrideWith((ref) async => const CardLibrary([]))],
      );
      expect(find.text('No cards yet'), findsOneWidget);
      expect(pack, findsNothing);
      await app.dispose(tester);
    });
  });

  testWidgets('the help explains rarities, odds and every finish', (tester) async {
    final app = await TestApp.create(withSampleTasks: false);
    await app.pump(tester, size: phone, location: '/notes');
    await tester.tap(find.byTooltip('About packs'));
    await settleFully(tester);
    expect(find.text('About packs'), findsOneWidget);
    expect(find.textContaining('A new pack arrives every 2 hours, and up to 2 can wait'), findsOneWidget);
    final table = find.byKey(const ValueKey('rarity-table'));
    for (final r in Rarity.values) {
      expect(find.descendant(of: table, matching: find.text(r.label)), findsOneWidget);
    }
    expect(find.descendant(of: table, matching: find.text('80%')), findsOneWidget);
    expect(find.descendant(of: table, matching: find.text('60%')), findsOneWidget);
    expect(find.textContaining('About 30% of cards get a finish'), findsOneWidget);
    for (final f in Finish.values) {
      final row = find.byKey(ValueKey('help-${f.key}'));
      await tester.scrollUntilVisible(row, 200, scrollable: find.byType(Scrollable).last);
      expect(
        find.descendant(of: row, matching: find.text(f.label)),
        findsWidgets,
        reason: f.label,
      );
      expect(find.descendant(of: row, matching: find.text(finishDescriptions[f]!)), findsOneWidget);
      expect(find.descendant(of: row, matching: find.byType(CollectibleCard)), findsOneWidget);
    }
    expect(find.text('0.1%'), findsOneWidget, reason: 'misprint');
    await tester.tap(find.byTooltip('Close'));
    await settleFully(tester);
    expect(find.text('About packs'), findsNothing);
    await app.dispose(tester);
  });

  group('binder', () {
    testWidgets('shows progress, copies, finishes and gaps', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await own(app, {'bamboo-grove|none': 1, 'bamboo-grove|holo': 1, 'tea-break|none': 1, 'starry-snooze|gold': 1});
      await app.pump(tester, location: '/notes/binder');
      expect(find.text('3 of 12 cards · 4 finishes collected'), findsOneWidget);
      expect(find.text('×2'), findsOneWidget);
      expect(find.byKey(const ValueKey('missing-early-start')), findsOneWidget);
      expect(find.byKey(const ValueKey('slot-bamboo-grove')), findsOneWidget);
      // The showiest copy is the one on show.
      final shown = tester.widget<CollectibleCard>(
        find.descendant(of: find.byKey(const ValueKey('slot-bamboo-grove')), matching: find.byType(CollectibleCard)),
      );
      expect(shown.finish, Finish.holo);

      await tester.tap(find.text('Collected'));
      await TestApp.settle(tester);
      expect(find.byKey(const ValueKey('missing-early-start')), findsNothing);
      expect(find.byKey(const ValueKey('slot-tea-break')), findsOneWidget);

      await tester.tap(find.text('Missing'));
      await TestApp.settle(tester);
      expect(find.byKey(const ValueKey('slot-tea-break')), findsNothing);
      expect(find.byKey(const ValueKey('missing-early-start')), findsOneWidget);

      await tester.tap(find.text('All'));
      await TestApp.settle(tester);
      await tester.tap(find.text('Notes').first);
      await TestApp.settle(tester);
      expect(find.text('Card packs'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('a card opens with its story, and its finishes can be switched', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await own(app, {'bamboo-grove|none': 2, 'bamboo-grove|holo': 1});
      await app.pump(tester, size: phone, location: '/notes/binder');
      await tester.tap(find.byKey(const ValueKey('slot-bamboo-grove')));
      await settleFully(tester);

      expect(find.byKey(const ValueKey('card-lore')), findsOneWidget);
      expect(find.textContaining('Pandas spend up to 14 hours'), findsOneWidget);
      expect(find.text('Photo: Ms Tan'), findsOneWidget);
      expect(find.text('FINISHES · 2 OF ${Finish.values.length} COLLECTED'), findsOneWidget);
      CollectibleCard big() => tester.widget(find.byKey(const ValueKey('detail-card')));
      expect(big().finish, Finish.holo);
      expect(find.text('No finish ×2'), findsOneWidget);

      // Finishes not collected yet are listed, greyed out, and can't be picked.
      final gold = find.byKey(const ValueKey('finish-gold'));
      expect(gold, findsOneWidget);
      expect(find.descendant(of: gold, matching: find.byType(ChoiceChip)), findsNothing);
      expect(find.bySemanticsLabel('Gold, not collected yet'), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const ValueKey('card-lore')), matching: find.byType(ChoiceChip)),
        findsNWidgets(2),
      );
      await tester.ensureVisible(gold);
      await tester.tap(gold);
      await tester.pump();
      expect(big().finish, Finish.holo);

      await tester.ensureVisible(find.byKey(const ValueKey('finish-none')));
      await tester.tap(find.byKey(const ValueKey('finish-none')));
      await tester.pump();
      expect(big().finish, Finish.none);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleFully(tester);
      expect(find.byType(CardDetail), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('a card that never gets some finishes does not list them', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await own(app, {'tea-break|none': 1});
      await app.pump(
        tester,
        location: '/notes/binder',
        overrides: [
          cardLibraryProvider.overrideWith((ref) async {
            final lib = await loadCards(DiskAssetBundle());
            return CardLibrary([
              for (final c in lib.cards)
                CardDef(
                  id: c.id,
                  number: c.number,
                  name: c.name,
                  rarity: c.rarity,
                  photo: c.photo,
                  text: c.text,
                  excluded: c.id == 'tea-break' ? {Finish.misprint, Finish.ghost} : const {},
                ),
            ]);
          }),
        ],
      );
      await tester.tap(find.byKey(const ValueKey('slot-tea-break')));
      await settleFully(tester);
      expect(find.text('FINISHES · 1 OF ${Finish.values.length - 2} COLLECTED'), findsOneWidget);
      expect(find.byKey(const ValueKey('finish-misprint')), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('themes show progress, and the story unlocks once every card is collected', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await own(app, {
        'early-start|none': 1,
        'tea-break|none': 1,
        'rainy-recess|none': 1,
        'panda-professor|holo': 1,
        'bamboo-grove|none': 1,
      });
      await app.pump(tester, location: '/notes/binder');
      expect(find.text('Themes'), findsOneWidget);
      final school = find.byKey(const ValueKey('theme-school-day'));
      final garden = find.byKey(const ValueKey('theme-garden-seasons'));
      expect(find.descendant(of: school, matching: find.text('4 / 4')), findsOneWidget);
      expect(find.descendant(of: school, matching: find.text('Story unlocked. Tap to read it.')), findsOneWidget);
      expect(find.descendant(of: garden, matching: find.text('1 / 4')), findsOneWidget);
      expect(find.byKey(const ValueKey('theme-after-hours')), findsOneWidget);

      await tester.tap(school);
      await settleFully(tester);
      expect(find.text('A Day at School'), findsWidgets);
      expect(find.byKey(const ValueKey('story-text')), findsOneWidget);
      expect(find.textContaining('The panda arrived before the sun'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleFully(tester);

      await tester.tap(garden);
      await settleFully(tester);
      expect(find.byKey(const ValueKey('story-text')), findsNothing);
      expect(find.text('Collect all 4 cards to unlock the story. 3 to go.'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleFully(tester);

      // A card's detail links to its theme too.
      await tester.tap(find.byKey(const ValueKey('slot-bamboo-grove')));
      await settleFully(tester);
      final link = find.byKey(const ValueKey('detail-theme-garden-seasons'));
      expect(find.descendant(of: link, matching: find.text('Seasons in the Garden · 1 of 4')), findsOneWidget);
      await tester.ensureVisible(link);
      await tester.tap(link);
      await settleFully(tester);
      expect(find.byKey(const ValueKey('story-locked')), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('empty filters say so', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(tester, location: '/notes/binder');
      await tester.tap(find.text('Collected'));
      await TestApp.settle(tester);
      expect(find.text('No cards here yet. Open a pack!'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('a full binder has nothing missing', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      final lib = await tester.runAsync(() => loadCards(DiskAssetBundle()));
      await own(app, {for (final c in lib!.cards) '${c.id}|none': 1});
      await app.pump(tester, location: '/notes/binder');
      await tester.tap(find.text('Missing'));
      await TestApp.settle(tester);
      expect(find.text('You have every card. Well done!'), findsOneWidget);
      await app.dispose(tester);
    });
  });

  testWidgets('the booster pack calls back once, however it is opened', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(child: BoosterPack(width: 200, onOpened: () => opened++)),
      ),
    );
    final semantics = tester.ensureSemantics();
    tester.semantics.tap(find.semantics.byLabel(RegExp('sealed')));
    await tester.pumpAndSettle();
    expect(opened, 1);
    await tester.drag(pack, const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(opened, 1);
    semantics.dispose();
  });

  group('pack fanfare and themes in the overview', () {
    CardDef card(String id, Rarity r, {List<String> themes = const []}) => CardDef(
      id: id,
      number: 1,
      name: id,
      rarity: r,
      photo: 'assets/cards/bamboo-grove.jpg',
      text: 't',
      themes: themes,
    );

    Widget host(Widget child, {List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: Material(color: Colors.black, child: child),
      ),
    );

    String? banner(WidgetTester tester) {
      final f = find.byKey(const ValueKey('fanfare-banner'));
      return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
    }

    testWidgets('Epic and Legendary cards pop out with sparkles and a banner', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(
          PackOpening(
            pulls: [
              Pull(card('e', Rarity.epic), Finish.none),
              Pull(card('c', Rarity.common), Finish.none),
              Pull(card('r', Rarity.rare), Finish.none),
              Pull(card('l', Rarity.legendary), Finish.none),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 800));
      expect(banner(tester), 'EPIC!');
      expect(find.byKey(const ValueKey('fanfare-sparkles')), findsOneWidget);
      for (final want in [null, null, 'LEGENDARY!']) {
        await tester.tap(stackTop);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 800));
        expect(banner(tester), want);
      }
      expect(hasFanfare(Rarity.rare), isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('with reduced motion the fanfare still shows, standing still', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pumpWidget(host(PackOpening(pulls: [Pull(card('l', Rarity.legendary), Finish.holo)])));
      await tester.pump();
      expect(banner(tester), 'LEGENDARY!');
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the overview celebrates a theme the pack completed', (tester) async {
      final lib = (await tester.runAsync(() => loadCards(DiskAssetBundle())))!;
      final school = lib.cardsIn('school-day');
      final state = CollectionState(copies: {for (final c in school) '${c.id}|none': 1});
      final pulls = [Pull(school.first, Finish.none, newCard: true), Pull(lib.byId('koi-pond')!, Finish.none)];
      await tester.pumpWidget(
        host(
          PackOpening(pulls: pulls, startWithOverview: true),
          overrides: [
            cardLibraryProvider.overrideWith((ref) async => lib),
            collectionProvider.overrideWith((ref) => Stream.value(state)),
          ],
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      final done = find.byKey(const ValueKey('completed-school-day'));
      expect(done, findsOneWidget);
      expect(find.text('Theme complete: A Day at School. Read the story'), findsOneWidget);
      expect(find.byKey(const ValueKey('completed-garden-seasons')), findsNothing);
      await tester.tap(done);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('story-text')), findsOneWidget);
    });

    testWidgets('a theme finished earlier is not celebrated again', (tester) async {
      final lib = (await tester.runAsync(() => loadCards(DiskAssetBundle())))!;
      final school = lib.cardsIn('school-day');
      final state = CollectionState(copies: {for (final c in school) '${c.id}|none': 2});
      await tester.pumpWidget(
        host(
          PackOpening(pulls: [Pull(school.first, Finish.none)], startWithOverview: true),
          overrides: [
            cardLibraryProvider.overrideWith((ref) async => lib),
            collectionProvider.overrideWith((ref) => Stream.value(state)),
          ],
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(find.byKey(const ValueKey('completed-school-day')), findsNothing);
    });
  });
}
