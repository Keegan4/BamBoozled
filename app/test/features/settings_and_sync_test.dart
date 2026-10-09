import 'package:bamboozled/core/theme/colors.dart';
import 'package:bamboozled/data/providers.dart';
import 'package:bamboozled/data/sync/sync_service.dart';
import 'package:bamboozled/features/auth/sign_in_dialog.dart';
import 'package:bamboozled/features/settings/sync_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';
import '../helpers.dart';

const phone = Size(412, 915);

/// A synced app with a fake sign-in service. (The Supabase client is never used, so it needs no cleanup.)
Future<(TestApp, SyncedOverrides)> syncedApp(
  WidgetTester tester, {
  bool signedIn = false,
  Size size = const Size(1440, 1000),
  String location = '/settings',
}) async {
  final app = await TestApp.create();
  final synced = app.synced(auth: FakeAuthService(user: signedIn ? fakeUser() : null));
  await app.pump(tester, size: size, overrides: synced.overrides, location: location);
  return (app, synced);
}

Icon indicatorIcon(WidgetTester tester) =>
    tester.widget<Icon>(find.descendant(of: find.byType(SyncIndicator), matching: find.byType(Icon)));

Future<void> setStatus(WidgetTester tester, SyncedOverrides s, SyncStatus status) async {
  s.sync.status.value = status;
  await TestApp.settle(tester);
}

void main() {
  group('Settings without a sync server', () {
    testWidgets('explains that tasks stay on this device and offers no sign-in', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, location: '/settings');
      expect(find.text('Sync between devices'), findsOneWidget);
      expect(find.textContaining('on this device only'), findsOneWidget);
      expect(find.text('Sign in to sync'), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('shows no cloud icon anywhere', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester);
      expect(find.byType(SyncIndicator), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
      expect(find.byIcon(Icons.cloud_done_rounded), findsNothing);
      await app.dispose(tester);
    });
  });

  group('your name', () {
    testWidgets('is pre-filled, can be changed, and shows in the greeting', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, location: '/settings');
      final field = find.widgetWithText(TextField, 'Ms Tan');
      expect(field, findsOneWidget);
      await tester.enterText(field, '  Mr Lim ');
      await tester.tap(find.text('Save'));
      await TestApp.settle(tester);
      expect(find.text('Name saved'), findsOneWidget);
      expect(await tester.runAsync(() => app.db.getSetting(displayNameKey)), 'Mr Lim');

      await tester.tap(find.text('Home'));
      await TestApp.settle(tester);
      expect(find.text('Good morning, Mr Lim'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('can be cleared, which goes back to a plain greeting', (tester) async {
      final app = await TestApp.create();
      await app.pump(tester, location: '/settings');
      await tester.enterText(find.widgetWithText(TextField, 'Ms Tan'), '');
      await tester.tap(find.text('Save'));
      await TestApp.settle(tester);
      expect(await tester.runAsync(() => app.db.getSetting(displayNameKey)), isNull);
      await tester.tap(find.text('Home'));
      await TestApp.settle(tester);
      expect(find.text('Good morning'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('pressing enter saves, and the box stops at 40 characters', (tester) async {
      final app = await TestApp.create(name: null);
      await app.pump(tester, location: '/settings');
      await tester.enterText(find.widgetWithText(TextField, ''), 'x' * 60);
      expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text.length, 40);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await TestApp.settle(tester);
      expect((await tester.runAsync(() => app.db.getSetting(displayNameKey)))!.length, 40);
      await app.dispose(tester);
    });
  });

  group('Settings with a sync server', () {
    testWidgets('signed out: invites you to sign in', (tester) async {
      final (app, _) = await syncedApp(tester);
      expect(find.textContaining('see the same tasks on your phone and your computer'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Sign in to sync'), findsOneWidget);
      expect(find.text('Sign out'), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('signed in: shows the account, sync button and sign out', (tester) async {
      final (app, _) = await syncedApp(tester, signedIn: true);
      expect(find.text('Signed in as ms.tan@school.edu.sg'), findsOneWidget);
      expect(find.text('Waiting to sync'), findsOneWidget);
      expect(find.text('Sync now'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Sign in to sync'), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('Sync now uploads the tasks and shows when it finished', (tester) async {
      final (app, s) = await syncedApp(tester, signedIn: true);
      await tester.tap(find.text('Sync now'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await TestApp.settle(tester);
      expect(s.server.tasks, hasLength(8));
      expect(find.text('Last synced at 9:00 am'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('while syncing and after a failure the page says so', (tester) async {
      final (app, s) = await syncedApp(tester, signedIn: true);
      await setStatus(tester, s, const SyncStatus(phase: SyncPhase.syncing));
      expect(find.text('Syncing…'), findsOneWidget);
      await setStatus(tester, s, const SyncStatus(phase: SyncPhase.error, message: 'Couldn’t sync — will retry'));
      final message = tester.widget<Text>(find.text('Couldn’t sync — will retry'));
      expect(message.style!.color, PandaColors.overdue);
      await app.dispose(tester);
    });

    testWidgets('Sign out signs out and goes back to the invitation', (tester) async {
      final (app, s) = await syncedApp(tester, signedIn: true);
      await tester.tap(find.text('Sign out'));
      await TestApp.settle(tester);
      expect(s.auth.signOuts, 1);
      expect(find.widgetWithText(FilledButton, 'Sign in to sync'), findsOneWidget);
      expect(find.text('Sign out'), findsNothing);
      await app.dispose(tester);
    });
  });

  group('sign-in dialog', () {
    Future<(TestApp, SyncedOverrides)> openDialog(WidgetTester tester) async {
      final (app, s) = await syncedApp(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in to sync'));
      await TestApp.settle(tester);
      expect(find.byType(SignInDialog), findsOneWidget);
      return (app, s);
    }

    Future<void> sendCodeTo(WidgetTester tester, String email) async {
      await tester.enterText(find.byType(TextField).last, email);
      await tester.tap(find.text('Email me a code'));
      await TestApp.settle(tester);
    }

    testWidgets('starts by asking for an email address', (tester) async {
      final (app, _) = await openDialog(tester);
      expect(find.text('Sign in to sync'), findsWidgets);
      expect(find.text('We’ll email you a 6-digit code. No password needed.'), findsOneWidget);
      expect(find.text('Email me a code'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('Cancel closes it', (tester) async {
      final (app, s) = await openDialog(tester);
      await tester.tap(find.text('Cancel'));
      await TestApp.settle(tester);
      expect(find.byType(SignInDialog), findsNothing);
      expect(s.auth.sentCodes, isEmpty);
      await app.dispose(tester);
    });

    for (final bad in ['', 'ms.tan', 'ms.tan@', 'ms.tan@school', '@school.edu', 'ms tan@school.edu']) {
      testWidgets('rejects "$bad" without contacting the server', (tester) async {
        final (app, s) = await openDialog(tester);
        await sendCodeTo(tester, bad);
        expect(find.text('Please enter a valid email address'), findsOneWidget);
        expect(s.auth.sentCodes, isEmpty);
        await app.dispose(tester);
      });
    }

    testWidgets('a valid email moves on to the code, trimming spaces', (tester) async {
      final (app, s) = await openDialog(tester);
      await sendCodeTo(tester, '  ms.tan@school.edu.sg ');
      expect(s.auth.sentCodes, ['ms.tan@school.edu.sg']);
      expect(find.text('Check your email'), findsOneWidget);
      expect(find.text('We sent a 6-digit code to ms.tan@school.edu.sg. Type it below.'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the code box takes digits only, at most six', (tester) async {
      final (app, _) = await openDialog(tester);
      await sendCodeTo(tester, 'ms.tan@school.edu.sg');
      await tester.enterText(find.byType(TextField).last, '12ab34-56789');
      expect(tester.widget<TextField>(find.byType(TextField).last).controller!.text, '123456');
      await app.dispose(tester);
    });

    testWidgets('a correct code signs in, closes the dialog and updates Settings', (tester) async {
      final (app, s) = await openDialog(tester);
      await sendCodeTo(tester, 'ms.tan@school.edu.sg');
      await tester.enterText(find.byType(TextField).last, '123456');
      await tester.tap(find.text('Sign in'));
      await TestApp.settle(tester);
      expect(s.auth.verified, [('ms.tan@school.edu.sg', '123456')]);
      expect(find.byType(SignInDialog), findsNothing);
      expect(find.text('Signed in — your tasks will now sync.'), findsOneWidget);
      expect(find.text('Signed in as ms.tan@school.edu.sg'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('a wrong code explains and lets you try again', (tester) async {
      final (app, s) = await openDialog(tester);
      await sendCodeTo(tester, 'ms.tan@school.edu.sg');
      s.auth.failVerify = true;
      await tester.enterText(find.byType(TextField).last, '000000');
      await tester.tap(find.text('Sign in'));
      await TestApp.settle(tester);
      expect(find.text('That code didn’t work. Check it, or ask for a new one.'), findsOneWidget);
      expect(find.byType(SignInDialog), findsOneWidget);

      s.auth.failVerify = false;
      await tester.enterText(find.byType(TextField).last, '123456');
      await tester.tap(find.text('Sign in'));
      await TestApp.settle(tester);
      expect(find.byType(SignInDialog), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('if the email cannot be sent it says so and stays on the first step', (tester) async {
      final (app, s) = await openDialog(tester);
      s.auth.failSend = true;
      await sendCodeTo(tester, 'ms.tan@school.edu.sg');
      expect(find.textContaining('We couldn’t send the email'), findsOneWidget);
      expect(find.text('Email me a code'), findsOneWidget);

      s.auth.failSend = false;
      await tester.tap(find.text('Email me a code'));
      await TestApp.settle(tester);
      expect(find.text('Check your email'), findsOneWidget);
      expect(find.textContaining('We couldn’t send the email'), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('"Use a different email" goes back a step', (tester) async {
      final (app, _) = await openDialog(tester);
      await sendCodeTo(tester, 'ms.tan@school.edu.sg');
      await tester.tap(find.text('Use a different email'));
      await TestApp.settle(tester);
      expect(find.text('Email me a code'), findsOneWidget);
      expect(find.text('Check your email'), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('fits on a phone with the keyboard-sized window', (tester) async {
      final (app, s) = await syncedApp(tester, size: const Size(412, 500));
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in to sync'));
      await TestApp.settle(tester);
      expect(find.byType(SignInDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(s.auth.sentCodes, isEmpty);
      await app.dispose(tester);
    });
  });

  group('cloud icon in the header', () {
    testWidgets('signed out: crossed-out cloud that explains itself', (tester) async {
      final (app, _) = await syncedApp(tester, location: '/');
      expect(indicatorIcon(tester).icon, Icons.cloud_off_rounded);
      expect(find.byTooltip('Not syncing — sign in to use on all your devices'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('signed in: a tick, with the time of the last sync', (tester) async {
      final (app, s) = await syncedApp(tester, signedIn: true, location: '/');
      expect(indicatorIcon(tester).icon, Icons.cloud_done_rounded);
      await setStatus(tester, s, SyncStatus(lastSyncedAt: testNow));
      expect(find.byTooltip('Synced at 9:00 am'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('while syncing it shows the sync arrows', (tester) async {
      final (app, s) = await syncedApp(tester, signedIn: true, location: '/');
      await setStatus(tester, s, const SyncStatus(phase: SyncPhase.syncing));
      expect(indicatorIcon(tester).icon, Icons.cloud_sync_rounded);
      expect(find.byTooltip('Syncing…'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('after a failure it turns red and says it will retry', (tester) async {
      final (app, s) = await syncedApp(tester, signedIn: true, location: '/');
      await setStatus(tester, s, const SyncStatus(phase: SyncPhase.error, message: 'x'));
      expect(indicatorIcon(tester).icon, Icons.cloud_off_rounded);
      expect(indicatorIcon(tester).color, PandaColors.overdue);
      expect(find.byTooltip('Couldn’t sync — will retry'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('tapping it opens Settings', (tester) async {
      final (app, _) = await syncedApp(tester, location: '/');
      await tester.tap(find.byType(SyncIndicator));
      await TestApp.settle(tester);
      expect(find.text('Sync between devices'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('it is also in the phone header', (tester) async {
      final (app, _) = await syncedApp(tester, size: phone, location: '/');
      expect(find.byType(SyncIndicator), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      await app.dispose(tester);
    });
  });

  testWidgets('the sync service is only running while signed in', (tester) async {
    final (app, s) = await syncedApp(tester, location: '/');
    expect(app.db, isNotNull);
    expect(s.auth.currentUser, isNull);
    await tester.runAsync(() => s.auth.verifyCode('ms.tan@school.edu.sg', '123456'));
    await TestApp.settle(tester);
    expect(indicatorIcon(tester).icon, Icons.cloud_done_rounded);
    await tester.runAsync(s.auth.signOut);
    await TestApp.settle(tester);
    expect(indicatorIcon(tester).icon, Icons.cloud_off_rounded);
    await app.dispose(tester);
  });
}
