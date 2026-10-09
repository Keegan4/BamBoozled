import 'package:bamboozled/app.dart';
import 'package:bamboozled/data/local/app_database.dart';
import 'package:bamboozled/data/providers.dart';
import 'package:bamboozled/data/repositories/task_repository.dart';
import 'package:bamboozled/data/sync/sync_service.dart';
import 'package:bamboozled/domain/models/priority.dart';
import 'package:bamboozled/features/tasks/task_editor.dart';
import 'package:bamboozled/features/tasks/widgets/task_card.dart';
import 'package:drift/drift.dart' show DatabaseConnection, driftRuntimeOptions;
import 'package:drift/native.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fakes.dart';

/// Thursday 8 October 2026, 9:00 am — the date used in the Figma mockups.
final testNow = DateTime(2026, 10, 8, 9);

class FixedClock extends ClockNotifier {
  @override
  DateTime build() => testNow;
}

/// A clock fixed at a different moment, for testing greetings and "This Fri" style labels.
class ClockAt extends ClockNotifier {
  ClockAt(this.moment);
  final DateTime moment;

  @override
  DateTime build() => moment;
}

/// Titles of the cards in the "Do next" list, top to bottom.
List<String> doNextTitles(WidgetTester tester) => tester
    .widgetList<TaskCard>(find.descendant(of: find.byKey(const ValueKey('do-next')), matching: find.byType(TaskCard)))
    .map((c) => c.task.title)
    .toList();

/// The card for the task with [title] (first match).
Finder cardFor(String title) => find.widgetWithText(TaskCard, title).first;

class TestApp {
  TestApp._(this.db, this.repo);
  final AppDatabase db;
  final TaskRepository repo;

  /// [ticking] makes the clock the repository stamps tasks with move forward a minute on every use,
  /// so "most recently finished" has a clear answer. (By default every stamp is exactly [testNow].)
  static Future<TestApp> create({bool withSampleTasks = true, String? name = 'Ms Tan', bool ticking = false}) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    var ids = 0;
    var minutes = 0;
    final repo = TaskRepository(
      db,
      clock: ticking ? () => testNow.add(Duration(minutes: minutes++)) : () => testNow,
      newId: () => 'id${ids++}',
    );
    await repo.ensureDefaultCategories();
    if (name != null) await db.setSetting(displayNameKey, name);
    if (withSampleTasks) await addSampleTasks(repo);
    return TestApp._(db, repo);
  }

  /// Same tasks as the Figma mockup.
  static Future<void> addSampleTasks(TaskRepository repo) async {
    Future<void> add(String title, DateTime due, Priority p, String cat) =>
        repo.addTask(TaskDraft(title: title, dueAt: due, priority: p, categoryId: cat));
    await add('Submit term report', DateTime(2026, 10, 7, 23, 59), Priority.medium, 'admin');
    await add('Mark 3A essays', DateTime(2026, 10, 9, 17), Priority.high, 'teaching');
    await add('Reply to parent emails', DateTime(2026, 10, 8, 18), Priority.low, 'admin');
    await add('Plan CCA trip', DateTime(2026, 10, 15, 9), Priority.urgent, 'cca');
    await add('Prepare Sec 2 quiz', DateTime(2026, 10, 12, 23, 59), Priority.high, 'teaching');
    await add('Staff meeting slides', DateTime(2026, 10, 14, 15), Priority.medium, 'meetings');
    await add('Book dentist', DateTime(2026, 10, 16, 23, 59), Priority.low, 'personal');
    final done = await repo.addTask(
      TaskDraft(
        title: 'Print worksheets',
        dueAt: DateTime(2026, 10, 6, 8),
        priority: Priority.medium,
        categoryId: 'teaching',
      ),
    );
    await repo.setDone(done.id, true);
  }

  Widget widget({
    List<Override> overrides = const [],
    String location = '/',
    DateTime? now,
    TaskRepository? repository,
  }) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      taskRepositoryProvider.overrideWithValue(repository ?? repo),
      clockProvider.overrideWith(now == null ? FixedClock.new : () => ClockAt(now)),
      routerProvider.overrideWith((ref) => buildRouter(initialLocation: location)),
      assetBundleProvider.overrideWithValue(DiskAssetBundle()),
      ...overrides,
    ],
    child: const BamBoozledApp(),
  );

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1440, 1000),
    List<Override> overrides = const [],
    String location = '/',
    DateTime? now,
    TaskRepository? repository,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(widget(overrides: overrides, location: location, now: now, repository: repository));
    await settle(tester);
  }

  /// Lets drift streams deliver (they run on real async) and the UI settle.
  static Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Provider overrides that make the app behave as if Supabase were configured, with a fake
  /// sign-in service and a sync service talking to an in-memory server. Nothing touches the network.
  SyncedOverrides synced({FakeAuthService? auth, FakeServer? server}) {
    final fakeAuth = auth ?? FakeAuthService();
    final fakeServer = server ?? FakeServer();
    final sync = SyncService(repo: repo, remote: fakeServer, db: db, clock: () => testNow);
    final client = SupabaseClient(
      'http://localhost:1',
      'unused',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    return SyncedOverrides(
      auth: fakeAuth,
      server: fakeServer,
      sync: sync,
      client: client,
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        authServiceProvider.overrideWithValue(fakeAuth),
        currentUserProvider.overrideWith((ref) => fakeAuth.userChanges()),
        syncServiceProvider.overrideWith((ref) {
          final user = ref.watch(currentUserProvider).value;
          return user == null ? null : sync;
        }),
      ],
    );
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await repo.dispose();
      await db.close();
    });
  }
}

class SyncedOverrides {
  SyncedOverrides({
    required this.auth,
    required this.server,
    required this.sync,
    required this.client,
    required this.overrides,
  });
  final FakeAuthService auth;
  final FakeServer server;
  final SyncService sync;
  final SupabaseClient client;
  final List<Override> overrides;
}

/// The title box of the add/edit task form (the first text box in it), whatever its hint text says.
Finder titleField() => find.descendant(of: find.byType(TaskEditor), matching: find.byType(TextField)).first;

/// Reads app assets straight from the project folder, without caching. rootBundle caches each
/// file's Future, and a Future made in one widget test never completes in the next one.
class DiskAssetBundle extends AssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      final files = Directory('assets').listSync(recursive: true).whereType<File>().map((f) => f.path);
      return const StandardMessageCodec().encodeMessage({
        for (final path in files)
          path: [
            {'asset': path},
          ],
      })!;
    }
    final bytes = await File(key).readAsBytes();
    return ByteData.sublistView(bytes);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async => File(key).readAsString();
}
