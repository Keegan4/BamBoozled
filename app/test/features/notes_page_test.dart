import 'dart:ui' show ImageFilter;

import 'package:bamboozled/core/theme/colors.dart';
import 'package:bamboozled/core/theme/panda_theme.dart';
import 'package:bamboozled/data/daily_notes/daily_note_library.dart';
import 'package:bamboozled/data/daily_notes/daily_note_store.dart';
import 'package:bamboozled/data/providers.dart';
import 'package:bamboozled/domain/models/daily_note.dart';
import 'package:bamboozled/features/notes/notes_page.dart';
import 'package:bamboozled/features/notes/widgets/daily_card.dart';
import 'package:bamboozled/features/notes/widgets/note_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

const tall = Size(1440, 1800);
const phone = Size(412, 915);
final day1 = DateTime(2026, 10, 9, 9);
final day2 = DateTime(2026, 10, 10, 9);

final seed = dailyNoteSeedProvider.overrideWith((ref) async => 'test-seed');

/// Lets animations (blur, flip) finish as well as the database.
Future<void> settleFully(WidgetTester tester) async {
  await TestApp.settle(tester);
  await tester.pump(const Duration(seconds: 1));
  await TestApp.settle(tester);
}

Finder todaysCard() => find.byKey(const ValueKey('todays-card'));
DailyNote todaysNote(WidgetTester tester) => tester.widget<DailyCard>(todaysCard()).note;
CardStage todaysStage(WidgetTester tester) => tester.widget<DailyCard>(todaysCard()).stage;
Finder thumbs() => find.descendant(of: find.byKey(const ValueKey('collected')), matching: find.byType(InkWell));

Future<TestApp> openNotes(WidgetTester tester, {DateTime? now, Size size = tall, TestApp? app}) async {
  final a = app ?? await TestApp.create(withSampleTasks: false);
  // Start from scratch so new overrides (e.g. another day) take effect.
  if (app != null) await tester.pumpWidget(const SizedBox());
  await a.pump(tester, size: size, location: '/notes', now: now ?? day1, overrides: [seed]);
  await settleFully(tester);
  return a;
}

Future<void> tapToday(WidgetTester tester) async {
  await tester.tap(todaysCard());
  await settleFully(tester);
}

void main() {
  group('today’s card', () {
    testWidgets('starts hidden: a blurred photo with "Tap to reveal"', (tester) async {
      final app = await openNotes(tester);
      expect(find.text('Today’s card'), findsOneWidget);
      expect(find.text('Tap to reveal'), findsOneWidget);
      expect(find.text('Tap the card to reveal today’s photo.'), findsOneWidget);
      expect(todaysStage(tester), CardStage.hidden);
      expect(find.descendant(of: todaysCard(), matching: find.byType(ImageFiltered)), findsOneWidget);
      expect(find.text(todaysNote(tester).text), findsNothing, reason: 'the message stays hidden');
      await app.dispose(tester);
    });

    testWidgets('tap reveals the photo, tap again flips to the message, then taps flip back and forth', (tester) async {
      final app = await openNotes(tester);
      final note = todaysNote(tester);

      await tapToday(tester);
      expect(todaysStage(tester), CardStage.revealed);
      expect(find.text('Tap to reveal'), findsNothing);
      expect(find.text('Tap to flip'), findsOneWidget);
      expect(
        find.descendant(of: todaysCard(), matching: find.byType(ImageFiltered)),
        findsNothing,
        reason: 'unblurred',
      );

      await tapToday(tester);
      expect(todaysStage(tester), CardStage.back);
      expect(find.text(note.text), findsOneWidget);
      expect(find.text(note.title!), findsOneWidget);

      await tapToday(tester);
      expect(todaysStage(tester), CardStage.revealed);
      expect(find.text(note.text), findsNothing);
      await tapToday(tester);
      expect(todaysStage(tester), CardStage.back);
      await app.dispose(tester);
    });

    testWidgets('once opened it counts down to the next card at midnight', (tester) async {
      final app = await openNotes(tester);
      await tapToday(tester);
      expect(find.text('A new card in 15 h.'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the countdown reads naturally close to midnight', (tester) async {
      for (final (time, text) in [
        (DateTime(2026, 10, 9, 21, 30), 'A new card in 2 h 30 min.'),
        (DateTime(2026, 10, 9, 23, 20), 'A new card in 40 min.'),
        (DateTime(2026, 10, 9, 23, 59, 30), 'A new card in a minute.'),
      ]) {
        final app = await TestApp.create(withSampleTasks: false);
        await tester.runAsync(() => DailyNoteStore(app.db).setStage(time, 'bamboo-forest', CardStage.revealed));
        await openNotes(tester, now: time, app: app);
        expect(find.text(text), findsOneWidget, reason: '$time');
        await app.dispose(tester);
      }
    });

    testWidgets('leaving the tab and coming back keeps the card as it was', (tester) async {
      final app = await openNotes(tester);
      await tapToday(tester);
      await tapToday(tester);
      await tester.tap(find.text('Home').first);
      await TestApp.settle(tester);
      await tester.tap(find.text('Notes').first);
      await settleFully(tester);
      expect(todaysStage(tester), CardStage.back);
      await app.dispose(tester);
    });

    testWidgets('the next day brings a new, hidden card and yesterday’s goes into Collected', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await openNotes(tester, app: app);
      final first = todaysNote(tester);
      await tapToday(tester);

      await openNotes(tester, now: day2, app: app);
      expect(todaysStage(tester), CardStage.hidden);
      expect(todaysNote(tester).id, isNot(first.id), reason: 'no repeats until every card has been seen');
      expect(find.text('Collected · 1'), findsOneWidget);
      expect(find.text('Fri 9 Oct'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the same person gets the same card on another device', (tester) async {
      final phoneApp = await openNotes(tester);
      final onPhone = todaysNote(tester);
      await phoneApp.dispose(tester);
      final laptop = await openNotes(tester);
      expect(todaysNote(tester), onPhone);
      await laptop.dispose(tester);
    });

    testWidgets('can be opened with the keyboard and is described to screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      final app = await openNotes(tester);
      expect(find.bySemanticsLabel('Today’s card, hidden. Tap to reveal the photo.'), findsOneWidget);
      bool cardFocused() =>
          FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<DailyCard>() != null;
      for (var i = 0; i < 40 && !cardFocused(); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(cardFocused(), isTrue, reason: 'reachable with Tab');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settleFully(tester);
      expect(todaysStage(tester), CardStage.revealed);
      expect(find.bySemanticsLabel(RegExp(r'^Card photo: .+\. Tap to flip and read it\.$')), findsOneWidget);
      handle.dispose();
      await app.dispose(tester);
    });

    testWidgets('fits on a phone', (tester) async {
      final app = await openNotes(tester, size: phone);
      expect(tester.takeException(), isNull);
      final card = tester.getRect(todaysCard());
      expect(card.width, lessThanOrEqualTo(phone.width - 32));
      await tapToday(tester);
      await tapToday(tester);
      expect(tester.takeException(), isNull);
      await app.dispose(tester);
    });

    testWidgets('with no cards it says how to add them', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await app.pump(
        tester,
        size: tall,
        location: '/notes',
        now: day1,
        overrides: [seed, dailyNotesProvider.overrideWith((ref) async => const DailyNoteLibrary([]))],
      );
      await settleFully(tester);
      expect(find.text('No cards yet'), findsOneWidget);
      expect(todaysCard(), findsNothing);
      await app.dispose(tester);
    });
  });

  group('looking at collected cards again', () {
    /// Three days of cards opened, now on the fourth day.
    Future<TestApp> withCollection(WidgetTester tester, {Size size = tall}) async {
      final app = await TestApp.create(withSampleTasks: false);
      await tester.runAsync(() async {
        final store = DailyNoteStore(app.db);
        await store.setStage(DateTime(2026, 10, 6), 'bamboo-forest', CardStage.back);
        await store.setStage(DateTime(2026, 10, 7), 'morning-light', CardStage.revealed);
        await store.setStage(DateTime(2026, 10, 8), 'starry-night', CardStage.back);
      });
      await openNotes(tester, app: app, size: size);
      return app;
    }

    testWidgets('they are listed newest first, with the day they were opened', (tester) async {
      final app = await withCollection(tester);
      expect(find.text('Collected · 3'), findsOneWidget);
      final dates = ['Thu 8 Oct', 'Wed 7 Oct', 'Tue 6 Oct'].map((d) => tester.getTopLeft(find.text(d)).dx).toList();
      expect(dates, orderedEquals([...dates]..sort()));
      await app.dispose(tester);
    });

    testWidgets('a click opens the card straight on the photo, with everything else blurred', (tester) async {
      final app = await withCollection(tester);
      await tester.tap(thumbs().first);
      await settleFully(tester);
      final viewer = find.byType(NoteViewer);
      expect(viewer, findsOneWidget);
      final card = tester.widget<DailyCard>(find.descendant(of: viewer, matching: find.byType(DailyCard)));
      expect(card.note.id, 'starry-night');
      expect(card.stage, CardStage.revealed, reason: 'goes straight to the second stage');
      expect(find.descendant(of: viewer, matching: find.text('Tap to reveal')), findsNothing);
      expect(find.descendant(of: viewer, matching: find.text('Tap to flip')), findsOneWidget);
      final blur = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(blur.filter, isA<ImageFilter>());
      await app.dispose(tester);
    });

    testWidgets('a click on the card flips it to the message, and back again', (tester) async {
      final app = await withCollection(tester);
      await tester.tap(thumbs().first);
      await settleFully(tester);
      final viewerCard = find.descendant(of: find.byType(NoteViewer), matching: find.byType(DailyCard));
      await tester.tap(viewerCard);
      await settleFully(tester);
      expect(tester.widget<DailyCard>(viewerCard).stage, CardStage.back);
      expect(find.text("Even pandas need a good night's sleep.\nClose the laptop on time tonight."), findsOneWidget);
      expect(find.descendant(of: viewerCard, matching: find.text('Thu 8 Oct')), findsOneWidget);
      await tester.tap(viewerCard);
      await settleFully(tester);
      expect(tester.widget<DailyCard>(viewerCard).stage, CardStage.revealed);
      await app.dispose(tester);
    });

    testWidgets('it closes by clicking outside, with the close button, or with Escape', (tester) async {
      final app = await withCollection(tester);
      for (final close in <Future<void> Function()>[
        () => tester.tapAt(const Offset(20, 900)),
        () => tester.tap(find.byTooltip('Close')),
        () => tester.sendKeyEvent(LogicalKeyboardKey.escape),
      ]) {
        await tester.tap(thumbs().first);
        await settleFully(tester);
        expect(find.byType(NoteViewer), findsOneWidget);
        await close();
        await settleFully(tester);
        expect(find.byType(NoteViewer), findsNothing);
        expect(find.byType(BackdropFilter), findsNothing, reason: 'the blur goes away too');
      }
      await app.dispose(tester);
    });

    testWidgets('opening an old card does not change today’s card', (tester) async {
      final app = await withCollection(tester);
      await tester.tap(thumbs().last);
      await settleFully(tester);
      await tester.tap(find.descendant(of: find.byType(NoteViewer), matching: find.byType(DailyCard)));
      await settleFully(tester);
      await tester.tap(find.byTooltip('Close'));
      await settleFully(tester);
      expect(todaysStage(tester), CardStage.hidden);
      await app.dispose(tester);
    });

    testWidgets('today’s card joins the collection once revealed, marked Today', (tester) async {
      final app = await withCollection(tester);
      await tapToday(tester);
      expect(find.text('Collected · 4'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the gallery shows small thumbnails side by side, 3 across on a phone, and the viewer fits a phone', (
      tester,
    ) async {
      var app = await withCollection(tester);
      double rowY(int i) => tester.getTopLeft(thumbs().at(i)).dy;
      expect(rowY(0), rowY(2), reason: 'three in one row on a computer');
      expect(tester.getSize(thumbs().first).width, lessThanOrEqualTo(160));
      await app.dispose(tester);

      app = await withCollection(tester, size: phone);
      await tester.scrollUntilVisible(thumbs().first, 300, scrollable: find.byType(Scrollable).first);
      expect(rowY(0), rowY(2));
      await tester.tap(thumbs().first);
      await settleFully(tester);
      final card = tester.getRect(find.byKey(const ValueKey('viewer-card')));
      expect(card.width, lessThanOrEqualTo(phone.width - 32));
      expect(card.bottom, lessThanOrEqualTo(phone.height));
      expect(tester.takeException(), isNull);
      await app.dispose(tester);
    });

    testWidgets('a card no longer in notes.yaml is left out of the collection', (tester) async {
      final app = await TestApp.create(withSampleTasks: false);
      await tester.runAsync(
        () => DailyNoteStore(app.db).setStage(DateTime(2026, 10, 6), 'deleted-card', CardStage.back),
      );
      await openNotes(tester, app: app);
      expect(find.textContaining('Collected'), findsNothing);
      await app.dispose(tester);
    });
  });

  group('the card on its own', () {
    const note = DailyNote(id: 'x', photo: 'assets/daily_notes/bamboo-forest.jpg', title: 'Hi', text: 'Message');

    testWidgets('with reduced motion it changes at once, without animating', (tester) async {
      Widget card(CardStage stage) => MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Center(
            child: SizedBox(
              width: 300,
              child: DailyCard(note: note, stage: stage, onTap: () {}),
            ),
          ),
        ),
      );
      await tester.pumpWidget(card(CardStage.hidden));
      await tester.pumpWidget(card(CardStage.back));
      await tester.pump();
      expect(find.text('Message'), findsOneWidget, reason: 'already flipped after a single frame');
    });

    testWidgets('a card without a title still reads well', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              child: DailyCard(
                note: const DailyNote(id: 'x', photo: 'assets/daily_notes/bamboo-forest.jpg', text: 'Only text'),
                stage: CardStage.back,
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Only text'), findsOneWidget);
    });

    testWidgets('follows dark mode: the back of the card uses the dark paper colour', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildPandaTheme(brightness: Brightness.dark),
          home: Center(
            child: SizedBox(
              width: 300,
              child: DailyCard(note: note, stage: CardStage.back, onTap: () {}),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      final card = tester.widget<Material>(find.byKey(const ValueKey('card-back')));
      expect(card.color, PandaPalette.dark.rice);
    });

    testWidgets('the Notes page builds on its own', (tester) async {
      expect(const NotesPage(), isA<Widget>());
    });
  });
}
